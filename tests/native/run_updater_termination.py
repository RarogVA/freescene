#!/usr/bin/env python3
"""Reproduce the main-queue quit deadlock, then exercise real helper/relaunch.

Only uniquely identified Cocoa fixture apps in fresh system-temp directories
are started. The installed FreeScene, Keychain and user profile are untouched.
"""
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT/'build/updater-termination-tests'
ENVIRONMENT = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], env=ENVIRONMENT, check=True, **kwargs)


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    app = OUTPUT/'quit-fixture'
    helper = OUTPUT/'FreeSceneUpdateHelper'
    with (OUTPUT/'compile.log').open('w') as log:
        for source, target in [(ROOT/'tests/native/updater_termination.m', app),
                               (ROOT/'macos/Native/FSUpdateHelper.m', helper)]:
            run('xcrun', 'clang', '-fobjc-arc', '-arch', 'arm64', '-mmacosx-version-min=13.0',
                '-framework', 'Cocoa', '-framework', 'Security', source, '-o', target,
                stdout=log, stderr=log)
    return app, helper


def bundle(parent, name, binary, version, identity):
    app = parent/name
    (app/'Contents/MacOS').mkdir(parents=True)
    executable = app/'Contents/MacOS/Fixture'
    executable.write_bytes(binary.read_bytes()); executable.chmod(0o755)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleName': 'FreeScene Updater Termination Fixture',
        'CFBundleIdentifier': identity, 'CFBundleExecutable': 'Fixture',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': version,
        'CFBundleShortVersionString': '1.0.0', 'LSMinimumSystemVersion': '13.0',
        'LSUIElement': True,
    }))
    run('/usr/bin/codesign', '--force', '--sign', '-', app,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return app


def marker(root, name):
    path = root/(name+'.json')
    return json.loads(path.read_text()) if path.exists() else None


def stop_owned_process(root, pid):
    # PIDs are taken solely from this fresh fixture's marker. Check the actual
    # command path as well, so a stale/reused PID cannot identify another app.
    state = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'comm='],
                           capture_output=True, text=True)
    command = state.stdout.strip()
    if command.startswith(str(root)+'/') or command == str(OUTPUT/'FreeSceneUpdateHelper'):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def main():
    binary, helper = build()
    checks = {}
    with tempfile.TemporaryDirectory(prefix='freescene-update-helper-test-') as temporary:
        root = Path(temporary)
        app = bundle(root, 'FreeScene.app', binary, 'old',
                     'local.freescene.quit-control.'+uuid.uuid4().hex)
        process = subprocess.Popen([str(app/'Contents/MacOS/Fixture'), 'direct-control',
                                    str(helper), str(root/'Unused.app'), str(root/'Backup.app')],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   env=ENVIRONMENT)
        try:
            try:
                process.wait(timeout=3)
                raise AssertionError('The direct main-queue termination control unexpectedly exited')
            except subprocess.TimeoutExpired:
                assert marker(root, 'shutdown-worker-finished') == {'saved': True}
                assert not marker(root, 'shutdown-completed')
                assert not marker(root, 'old-exited')
                checks['directMainQueueTerminateDeadlockReproduced'] = True
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)

    with tempfile.TemporaryDirectory(prefix='freescene-update-helper-test-') as temporary:
        root = Path(temporary)
        identity = 'local.freescene.quit-handoff.'+uuid.uuid4().hex
        app = bundle(root, 'FreeScene.app', binary, 'old', identity)
        staged = bundle(root, 'Staged.app', binary, 'new', identity)
        backup = root/'Backup.app'
        process = subprocess.Popen([str(app/'Contents/MacOS/Fixture'), 'updater-handoff',
                                    str(helper), str(staged), str(backup)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   env=ENVIRONMENT)
        try:
            started = time.monotonic()
            assert process.wait(timeout=10) == 0, 'Old fixture application did not exit normally'
            assert marker(root, 'ready') == {'ready': True}
            assert marker(root, 'shutdown-completed') == {'saved': True}
            assert marker(root, 'old-exited'), 'AppKit did not finish normal application termination'
            checks['productionReadinessHandlerQuitsAfterAsyncShutdown'] = True
            deadline = time.monotonic()+20
            while time.monotonic() < deadline:
                if marker(root, 'relaunched-exited') and not backup.exists():
                    break
                time.sleep(0.05)
            assert marker(root, 'relaunched'), 'Production helper did not launch the new temporary app'
            assert marker(root, 'relaunched-exited'), 'Relaunched temporary app did not exit normally'
            info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
            assert info['CFBundleVersion'] == 'new', 'Production helper did not install the staged app'
            assert not staged.exists() and not backup.exists(), 'Successful install did not finish cleanup'
            checks['productionHelperWaitsSwapsAndRelaunchesTemporaryApp'] = True
            checks['backupRemovedOnlyAfterConfirmedLaunch'] = True
            checks['handoffSeconds'] = round(time.monotonic()-started, 3)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            for name in ['helper', 'relaunched']:
                value = marker(root, name)
                if value:
                    stop_owned_process(root, value['pid'])
    report = {'passed': True, 'checks': checks,
              'actualCocoaTerminationExercised': True,
              'temporaryApplicationRelaunchPerformed': True,
              'installedApplicationChanged': False, 'userKeychainRead': False,
              'userProfileRead': False}
    (OUTPUT/'result.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
