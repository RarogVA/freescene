#!/usr/bin/env python3
"""Build an Android/mobile or Android TV APK, with explicit local-preview signing.

Production uses android/key.properties, never the macOS identity. Local preview
is a release-mode performance build signed by the local Android debug key.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flavor', choices=['mobile', 'tv'], required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--preview', action='store_true')
    modes.add_argument('--release', action='store_true')
    parser.add_argument('--bundle', action='store_true', help='Build AAB instead of APKs')
    args = parser.parse_args()
    if args.release and not (ROOT / 'android/key.properties').is_file():
        parser.error('Production signing requires android/key.properties; see docs/android.md')
    if args.bundle and not (args.release or args.preview):
        parser.error('Use --preview or --release for an app bundle')
    environment = dict(os.environ)
    if sys.platform == 'darwin' and not environment.get('JAVA_HOME'):
        environment['JAVA_HOME'] = subprocess.check_output(
            ['/usr/libexec/java_home', '-v', '17'], text=True).strip()
    if args.preview:
        environment['ORG_GRADLE_PROJECT_localPreview'] = 'true'
    else:
        environment.pop('ORG_GRADLE_PROJECT_localPreview', None)
    subprocess.run([sys.executable, str(ROOT / 'tools/build_android_engine.py')], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/build_android_audio.py')], cwd=ROOT, check=True)
    mode = 'release' if args.release or args.preview else 'debug'
    command = ['flutter', 'build', 'appbundle' if args.bundle else 'apk',
               '--flavor', args.flavor, '--' + mode]
    if not args.bundle:
        command += ['--split-per-abi', '--target-platform', 'android-arm,android-arm64']
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    if args.bundle:
        paths = list((ROOT / f'build/app/outputs/bundle/{args.flavor}{mode.title()}').glob('*.aab'))
    else:
        paths = [ROOT / f'build/app/outputs/flutter-apk/app-{abi}-{args.flavor}-{mode}.apk'
                 for abi in ('armeabi-v7a', 'arm64-v8a')]
    if not paths or any(not path.is_file() for path in paths):
        raise RuntimeError('Expected build artifacts are missing')
    output = ROOT / 'build/android-artifacts' / args.flavor / ('preview' if args.preview else mode)
    output.mkdir(parents=True, exist_ok=True)
    artifacts = []
    for path in paths:
        with zipfile.ZipFile(path) as archive:
            native = [name for name in archive.namelist() if name.endswith('.so')]
            if any('vlc' in name.lower() for name in native):
                raise RuntimeError('macOS VLC payload unexpectedly included in Android')
            if not any('libFreeSceneEngine.so' in name for name in native):
                raise RuntimeError('Android torrent engine missing')
            if not any(name.endswith('/libffmpegJNI.so') for name in native):
                raise RuntimeError('Android audio fallback missing')
        destination = output / path.name
        shutil.copy2(path, destination)
        artifacts.append({'path': str(destination.relative_to(ROOT)), 'bytes': path.stat().st_size,
                          'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    shutil.copy2(ROOT / 'build/android-audio/FreeScene-android-audio-sources.tar.gz', output)
    report = {'flavor': args.flavor, 'mode': mode, 'localPreview': args.preview,
              'productionSigningConfigured': (ROOT / 'android/key.properties').is_file(),
              'artifacts': artifacts}
    (output / 'build-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
