#!/usr/bin/env python3
"""Build and package an Apple Silicon or Intel macOS app with the installed Xcode."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

from sign_freescene import DEFAULT_IDENTITY_DIR, load_identity, sign_bundle, validate_identity


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xcode', type=Path, default=Path('/Applications/Xcode.app'))
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--arch', choices=['arm64','x86_64'], default='arm64')
    parser.add_argument('--vlc', type=Path, default=Path('/Applications/VLC.app'))
    parser.add_argument('--channel', choices=['preview', 'stable'], default='preview')
    parser.add_argument('--signing-identity-dir', type=Path, default=DEFAULT_IDENTITY_DIR,
                        help='Existing persistent private signing identity for stable releases')
    parser.add_argument('--vlc-sources', type=Path,
                        help='Required companion source archive for distribution')
    args = parser.parse_args()
    if args.channel == 'stable' and not args.vlc_sources:
        parser.error('Stable releases require the VLC companion source archive')
    if args.channel == 'stable':
        # Fail before building; a stable release never silently falls back to ad hoc.
        validate_identity(load_identity(args.signing_identity_dir))
    destination = args.destination.resolve()
    if destination.exists():
        parser.error('Choose a new destination directory')
    developer = args.xcode.resolve() / 'Contents/Developer'
    if not (developer / 'usr/bin/xcodebuild').is_file():
        parser.error('A complete Xcode installation is required')
    environment = dict(os.environ, DEVELOPER_DIR=str(developer),
                       FLUTTER_XCODE_ARCHS=args.arch,
                       FLUTTER_XCODE_FREESCENE_ARCH=args.arch,
                       FLUTTER_XCODE_FREESCENE_NATIVE_DIR='native' if args.arch=='arm64' else 'native-x86_64',
                       FLUTTER_XCODE_FREESCENE_VLC_PATH=str(args.vlc.resolve()))
    if args.vlc_sources:
        import hashlib
        sources_report = json.loads((args.vlc_sources.parent/'vlc-sources.json').read_text())
        if (not args.vlc_sources.is_file() or
                hashlib.sha256(args.vlc_sources.read_bytes()).hexdigest() != sources_report['archiveSHA256']):
            raise RuntimeError('VLC companion sources checksum mismatch')
        if not (ROOT/'licenses/VLC-THIRD-PARTY-NOTICES.txt').is_file():
            raise RuntimeError('VLC distribution notices are missing')

    def run(*command, capture=False):
        result = subprocess.run(command, cwd=PROJECT, env=environment,
                                check=True, text=True, capture_output=capture)
        return result.stdout.strip() if capture else None

    xcode_version = run('xcodebuild', '-version', capture=True)
    run('flutter', 'build', 'macos', '--release')
    source = PROJECT / 'build/macos/Build/Products/Release/FreeScene.app'
    executable = source / 'Contents/MacOS/FreeScene'
    architecture = run('lipo', '-archs', str(executable), capture=True)
    if architecture != args.arch:
        raise RuntimeError(f'Unexpected application architecture: {architecture}')
    helper = source / 'Contents/Helpers/FreeSceneUpdateHelper'
    if run('lipo', '-archs', str(helper), capture=True) != args.arch:
        raise RuntimeError('The update helper architecture does not match the application')
    for relative in ('Contents/Frameworks/App.framework/App',
                     'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS',
                     'Contents/Frameworks/libFreeSceneEngine.dylib'):
        if args.arch not in run('lipo', '-archs', str(source/relative), capture=True).split():
            raise RuntimeError(f'Missing {args.arch} slice: {relative}')
    signing = sign_bundle(source, args.signing_identity_dir) if args.channel == 'stable' else None
    run('codesign', '--verify', '--strict', str(helper))
    run('codesign', '--verify', '--deep', '--strict', str(source))
    destination.mkdir(parents=True)
    bundle = destination / 'FreeScene.app'
    run('ditto', str(source), str(bundle))
    run('codesign', '--verify', '--deep', '--strict', str(bundle))
    if args.vlc_sources:
        audit = json.loads((bundle/'Contents/Resources/VLC/audit.json').read_text())
        modules = json.loads((bundle/'Contents/Resources/VLC/modules.json').read_text())
        if not audit.get('passed') or not modules.get('auditStatus', '').startswith('passed:'):
            raise RuntimeError('Bundle does not contain a passed VLC distribution audit')
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    suffix = '-preview' if args.channel == 'preview' else ''
    image = destination / f'FreeScene-{version}{suffix}-macos-{args.arch}.dmg'
    run(sys.executable, str(ROOT / 'tools/package_dmg.py'), '--channel', args.channel,
        '--bundle', str(bundle), '--output', str(image))
    report = {
        'passed': True, 'version': version, 'channel': args.channel, 'architecture': architecture,
        'xcode': xcode_version, 'minimumMacOS': info['LSMinimumSystemVersion'],
        'signature': ('persistent self-signed; strict integrity and certificate-pinned requirements verified'
                      if signing else 'local ad hoc; deep strict verification passed'),
        'signing': signing,
        'interfaceFont': 'Play Regular/Bold (SIL OFL 1.1)',
        'updateHelper': f'embedded {args.arch} executable; strict signature verified',
        'bundle': str(bundle), 'diskImage': str(image),
        'vlcSourceCompanion': str(args.vlc_sources) if args.vlc_sources else None,
    }
    (destination / 'build-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
