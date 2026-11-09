"""Compile and exercise the real native updater against disposable .app trees.

No app, profile, Keychain, Finder, or NSWorkspace launch is used by these tests.
Run: python3 tests/native/update_helper_test.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import selectors
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'build/native-updater-helper-tests'
OUTPUT.mkdir(parents=True, exist_ok=True)
ENVIRONMENT = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
PREFIX = 'freescene-update-helper-test-'
RESULTS: list[dict] = []


def build(source: str, name: str) -> Path:
    target = OUTPUT / name
    command = [
        'xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
        '-arch', 'arm64', '-mmacosx-version-min=13.0',
        '-framework', 'Cocoa', str(ROOT / source), '-o', str(target),
    ]
    subprocess.run(command, env=ENVIRONMENT, check=True, capture_output=True, text=True)
    return target


def make_app(path: Path, payload: str) -> Path:
    (path / 'Contents/Resources').mkdir(parents=True)
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleName': 'FreeScene Updater Fixture',
        'CFBundleIdentifier': 'local.freescene.updater-fixture',
        'CFBundleVersion': payload,
        'CFBundlePackageType': 'APPL',
    }))
    (path / 'Contents/Resources/version.txt').write_text(payload)
    return path


def version(path: Path) -> str:
    return (path / 'Contents/Resources/version.txt').read_text()


def snapshot(path: Path) -> dict:
    result = {}
    for entry in sorted(path.rglob('*')):
        relative = str(entry.relative_to(path))
        if entry.is_symlink():
            result[relative] = ['symlink', os.readlink(entry)]
        elif entry.is_dir():
            result[relative] = ['directory']
        else:
            result[relative] = ['file', entry.read_bytes().hex()]
    return result


def call(binary: Path, args: list, *, fail_rename=False) -> tuple[int, dict]:
    environment = dict(ENVIRONMENT)
    environment.pop('FS_UPDATE_TEST_FAIL_RENAME', None)
    if fail_rename:
        environment['FS_UPDATE_TEST_FAIL_RENAME'] = '1'
    process = subprocess.run(
        [str(binary), *map(str, args)], env=environment, capture_output=True,
        text=True, timeout=15,
    )
    assert not process.stderr, process.stderr
    return process.returncode, json.loads(process.stdout)


def record(name: str, details: dict) -> None:
    RESULTS.append({'name': name, 'passed': True, **details})


def roots(folder: Path) -> tuple[Path, Path, Path]:
    return folder / 'FreeScene.app', folder / 'Staged.app', folder / 'Backup.app'


def rejected(binary: Path, name: str, mutate) -> None:
    with tempfile.TemporaryDirectory(prefix=PREFIX) as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        arguments = mutate(folder, app, staged, backup)
        before = snapshot(folder)
        code, result = call(binary, ['--test-install', *arguments])
        assert code != 0 and result['ok'] is False, (name, result)
        assert snapshot(folder) == before, f'{name}: rejected operation mutated its fixture'
        record(name, {'code': result['code'], 'fixtureUnchanged': True})


def main() -> None:
    binary = build('macos/Native/FSUpdateHelper.m', 'FreeSceneUpdateHelper')
    rollback = build('tests/native/update_helper_rollback.m', 'rollback-after-swap')
    launch_state = build('tests/native/update_helper_launch_state.m', 'launch-state')

    with tempfile.TemporaryDirectory(prefix=PREFIX) as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        # Cleanup of a bundle must not follow an internal symlink outside it.
        external = folder / 'unrelated-data'
        external.mkdir()
        (external / 'keep.txt').write_text('must survive')
        (app / 'Contents/Resources/external-link').symlink_to(external, target_is_directory=True)
        original_staged_inode = staged.stat().st_ino
        code, result = call(binary, ['--test-install', app, staged, backup])
        assert code == 0 and result['ok'] and result['installed'], result
        assert result['backupRemoved'] and not result['launched'], result
        assert version(app) == 'new' and app.stat().st_ino == original_staged_inode
        assert not staged.exists() and not backup.exists()
        assert (external / 'keep.txt').read_text() == 'must survive'
        record('atomic_swap_and_safe_cleanup', {'result': result, 'externalSymlinkTargetPreserved': True})

    with tempfile.TemporaryDirectory(prefix=PREFIX) as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        before = snapshot(folder)
        old_inode, new_inode = app.stat().st_ino, staged.stat().st_ino
        code, result = call(binary, ['--test-install', app, staged, backup], fail_rename=True)
        assert code != 0 and result['rolledBack'], result
        assert result['code'] == 'install_failed_rolled_back'
        assert snapshot(folder) == before
        assert app.stat().st_ino == old_inode and staged.stat().st_ino == new_inode
        assert not backup.exists()
        record('failed_second_rename_restores_original', {'result': result, 'originalAndStagedIdentitiesPreserved': True})

    with tempfile.TemporaryDirectory(prefix=PREFIX) as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        before = snapshot(folder)
        old_inode, new_inode = app.stat().st_ino, staged.stat().st_ino
        code, result = call(rollback, [app, staged, backup])
        assert code == 0 and result['rolledBack'], result
        assert snapshot(folder) == before
        assert app.stat().st_ino == old_inode and staged.stat().st_ino == new_inode
        record('post_swap_launch_error_rollback_core', {'result': result, 'originalAndStagedIdentitiesPreserved': True})

    for mode in ['pending', 'unknown-completion', 'failed']:
        with tempfile.TemporaryDirectory(prefix=PREFIX) as temporary:
            folder = Path(temporary)
            app, staged, backup = roots(folder)
            make_app(app, 'old')
            make_app(staged, 'new')
            old_inode, new_inode = app.stat().st_ino, staged.stat().st_ino
            code, result = call(launch_state, [mode, app, staged, backup])
            assert code != 0 and not result['ok'], result
            assert result['launchRequests'] == 1, result
            if mode == 'failed':
                assert result['code'] == 'launch_failed_rolled_back' and result['rolledBack'], result
                assert version(app) == 'old' and app.stat().st_ino == old_inode
                assert version(staged) == 'new' and staged.stat().st_ino == new_inode
                assert not backup.exists()
                assert result['oldRelaunchRequests'] == 1, result
            else:
                assert result['code'] == 'launch_pending' and result['launchState'] == 'pending', result
                assert result['installed'] and not result['rolledBack'] and not result['backupRemoved'], result
                assert version(app) == 'new' and app.stat().st_ino == new_inode
                assert version(backup) == 'old' and backup.stat().st_ino == old_inode
                assert not staged.exists()
                assert result['oldRelaunchRequests'] == 0, result
                if mode == 'pending':
                    assert result['lateCompletionObserved'], result
            record('launch_state_' + mode, {
                'result': result,
                'bundleStateVerifiedAfterCompletion': True,
                'applicationLaunchPerformed': False,
            })

    with tempfile.TemporaryDirectory(prefix=PREFIX) as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        before = snapshot(folder)
        process = subprocess.Popen(
            [str(binary), '--install', str(os.getpid()), str(app), str(staged), str(backup)],
            env=ENVIRONMENT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                assert selector.select(timeout=5), 'Helper did not send its readiness handshake'
            assert json.loads(process.stdout.readline()) == {'ready': True}
            assert process.poll() is None, 'Helper should still be waiting for its live parent PID'
            assert snapshot(folder) == before, 'No swap is allowed before the application exits'
            # End only this fixture helper before its fake parent exits. This
            # proves readiness ordering without ever reaching NSWorkspace.
            process.terminate()
            process.wait(timeout=5)
            assert snapshot(folder) == before
            record('production_ready_before_pid_exit', {
                'readyHandshake': True, 'fixtureUnchanged': True, 'applicationLaunchPerformed': False,
            })
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()

    rejected(binary, 'relative_app_path', lambda folder, app, staged, backup: ['FreeScene.app', staged, backup])
    rejected(binary, 'relative_staged_path', lambda folder, app, staged, backup: [app, 'Staged.app', backup])
    rejected(binary, 'relative_backup_path', lambda folder, app, staged, backup: [app, staged, 'Backup.app'])
    rejected(binary, 'wrong_extension', lambda folder, app, staged, backup: [app, staged, folder / 'Backup.txt'])
    rejected(binary, 'app_equals_staged', lambda folder, app, staged, backup: [app, app, backup])
    rejected(binary, 'backup_equals_app', lambda folder, app, staged, backup: [app, staged, app])
    rejected(binary, 'traversal_component', lambda folder, app, staged, backup: [app, staged, f'{folder}/nested/../Backup.app'])
    rejected(binary, 'different_parent', lambda folder, app, staged, backup: [app, staged, folder.parent / 'Foreign.app'])
    rejected(binary, 'existing_backup', lambda folder, app, staged, backup: [app, staged, make_app(backup, 'unrelated')])
    rejected(binary, 'missing_staged', lambda folder, app, staged, backup: [app, folder / 'Missing.app', backup])

    def symlink_root(which):
        def mutation(folder, app, staged, backup):
            link = folder / 'Link.app'
            link.symlink_to(app if which == 0 else staged, target_is_directory=True)
            arguments = [app, staged, backup]
            arguments[which] = link
            return arguments
        return mutation

    rejected(binary, 'symlink_app_root', symlink_root(0))
    rejected(binary, 'symlink_staged_root', symlink_root(1))
    rejected(binary, 'symlink_backup_root', symlink_root(2))

    def file_root(folder, app, staged, backup):
        regular = folder / 'File.app'
        regular.write_text('not a bundle directory')
        return [app, regular, backup]

    rejected(binary, 'regular_file_staged_root', file_root)

    with tempfile.TemporaryDirectory(prefix='unrelated-updater-test-') as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        before = snapshot(folder)
        code, result = call(binary, ['--test-install', app, staged, backup])
        assert code != 0 and snapshot(folder) == before
        record('test_mode_rejects_unmarked_temp_directory', {'result': result, 'fixtureUnchanged': True})

    with tempfile.TemporaryDirectory(prefix=PREFIX, dir=OUTPUT) as temporary:
        folder = Path(temporary)
        app, staged, backup = roots(folder)
        make_app(app, 'old')
        make_app(staged, 'new')
        before = snapshot(folder)
        code, result = call(binary, ['--test-install', app, staged, backup])
        assert code != 0 and snapshot(folder) == before
        record('test_mode_rejects_non_system_temp_parent', {'result': result, 'fixtureUnchanged': True})

    for pid in ['0', '1', '-5', 'invalid', '42 trailing']:
        code, result = call(binary, ['--install', pid, '/invalid.app', '/stage.app', '/backup.app'])
        assert code != 0 and result['code'] == 'invalid_pid'
        record('invalid_pid_' + pid, {'code': result['code']})

    report = {
        'passed': True,
        'checks': len(RESULTS),
        'applicationLaunchesPerformed': False,
        'productionHelper': str(binary.relative_to(ROOT)),
        'scenarios': RESULTS,
    }
    (OUTPUT / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
