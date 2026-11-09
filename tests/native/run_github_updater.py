#!/usr/bin/env python3
"""Compile and exercise updater security fixtures without network or user credentials."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/github-updater-tests'
ENV = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, env=ENV, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip', type=Path)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--version')
    parser.add_argument('--arch', choices=['arm64','x86_64'], default='arm64')
    args = parser.parse_args()
    if any((args.zip, args.app, args.version)) and not all((args.zip, args.app, args.version)):
        parser.error('--zip, --app and --version must be supplied together')
    build=BUILD/args.arch; build.mkdir(parents=True, exist_ok=True)
    binary = build/'github-updater-test'
    with (build/'compile.log').open('w') as log:
        run('xcrun', 'clang', '-arch', args.arch, '-fobjc-arc', '-mmacosx-version-min=13.0', '-framework', 'Cocoa',
            '-framework', 'Security', ROOT/'tests/native/github_updater.m', '-o', binary,
            stdout=log, stderr=log)
    run('/usr/bin/codesign','--force','--sign','-',binary,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if args.zip:
        result = run(binary, '--validate', args.zip.resolve(), args.app.resolve(), args.version,
                     capture_output=True, text=True)
        print(result.stdout.strip())
        return
    with tempfile.TemporaryDirectory(prefix='freescene-github-updater-test-') as temporary:
        fixture = Path(temporary)
        (fixture/'hash.bin').write_bytes(b'abc')
        def archive(name, entries):
            with zipfile.ZipFile(fixture/name, 'w', compression=zipfile.ZIP_DEFLATED) as out:
                for path, data, mode in entries:
                    entry = zipfile.ZipInfo(path)
                    entry.create_system = 3
                    entry.external_attr = mode << 16
                    out.writestr(entry, data)
        regular = stat.S_IFREG | 0o644
        link = stat.S_IFLNK | 0o777
        archive('safe.zip', [('FreeScene.app/Contents/Info.plist', b'fixture', regular)])
        archive('framework-links.zip', [
            ('FreeScene.app/Contents/Frameworks/F.framework/Versions/A/F', b'fixture', regular),
            ('FreeScene.app/Contents/Frameworks/F.framework/Versions/Current', b'A', link),
            ('FreeScene.app/Contents/Frameworks/F.framework/F', b'Versions/Current/F', link),
        ])
        archive('traversal.zip', [('FreeScene.app/../escape', b'bad', regular)])
        archive('absolute.zip', [('/tmp/escape', b'bad', regular)])
        archive('backslash.zip', [('FreeScene.app/..\\escape', b'bad', regular)])
        archive('symlink-escape.zip', [('FreeScene.app/Contents/escape', b'../../../outside', link)])
        archive('symlink-ancestor.zip', [
            ('FreeScene.app/Contents/alias', b'inside', link),
            ('FreeScene.app/Contents/alias/file', b'bad', regular),
        ])
        archive('duplicate-case.zip', [('FreeScene.app/Contents/file', b'a', regular), ('FreeScene.app/Contents/FILE', b'b', regular)])
        archive('special-file.zip', [('FreeScene.app/Contents/socket', b'', stat.S_IFIFO | 0o644)])
        with zipfile.ZipFile(fixture/'unicode-override.zip', 'w') as out:
            entry = zipfile.ZipInfo('FreeScene.app/Contents/safe')
            value = b'\x01\0\0\0\0../../outside'
            entry.extra = struct.pack('<HH', 0x7075, len(value)) + value
            out.writestr(entry, b'bad')
        damaged = bytearray((fixture/'safe.zip').read_bytes())
        damaged[30] = ord('X')
        (fixture/'local-mismatch.zip').write_bytes(damaged)
        (fixture/'damaged.zip').write_bytes((fixture/'safe.zip').read_bytes()[:-10])
        cfile = fixture/'fixture.c'
        cfile.write_text('int main(void) { return 0; }\n')
        def bundle(name, *, identity='local.freescene.freescene', architecture=args.arch, minimum='13.0'):
            app = fixture/name
            (app/'Contents/MacOS').mkdir(parents=True)
            with (app/'Contents/Info.plist').open('wb') as output:
                plistlib.dump(dict(CFBundleIdentifier=identity, CFBundleShortVersionString='1.2.1',
                                  CFBundleVersion='20', CFBundleExecutable='Fixture', CFBundlePackageType='APPL',
                                  LSMinimumSystemVersion=minimum), output)
            run('xcrun', 'clang', '-arch', architecture, '-mmacosx-version-min=13.0', cfile,
                '-o', app/'Contents/MacOS/Fixture', stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            run('/usr/bin/codesign', '--force', '--sign', '-', app,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return app
        valid = bundle('valid.app')
        bundle('wrong-id.app', identity='other.application')
        bundle('wrong-arch.app', architecture='x86_64' if args.arch=='arm64' else 'arm64')
        bundle('future-os.app', minimum='99.0')
        bad = bundle('bad-signature.app')
        executable = bad/'Contents/MacOS/Fixture'
        data = bytearray(executable.read_bytes()); data[4096] ^= 1; executable.write_bytes(data)
        (fixture/'app-link.app').symlink_to(valid, target_is_directory=True)
        internal = fixture/'internal-links.app'
        (internal/'Contents/F.framework/Versions/A').mkdir(parents=True)
        (internal/'Contents/F.framework/Versions/A/F').write_bytes(b'fixture')
        (internal/'Contents/F.framework/Versions/Current').symlink_to('A')
        (internal/'Contents/F.framework/F').symlink_to('Versions/Current/F')
        escaping = fixture/'escape-links.app'
        escaping.mkdir()
        (escaping/'escape').symlink_to('../valid.app')
        special = fixture/'special-files.app'
        special.mkdir()
        os.mkfifo(special/'fifo')
        stage = fixture/'dmg-stage'
        stage.mkdir()
        shutil.copytree(valid, stage/'FreeScene.app', symlinks=True)
        (stage/'Applications').symlink_to('/Applications')
        run('/usr/bin/hdiutil', 'create', '-quiet', '-srcfolder', stage, '-format', 'UDZO', fixture/'valid.dmg')
        linked = fixture/'linked-stage'
        linked.mkdir()
        (linked/'FreeScene.app').symlink_to(valid)
        run('/usr/bin/hdiutil', 'create', '-quiet', '-srcfolder', linked, '-format', 'UDZO', fixture/'linked-app.dmg')
        (fixture/'damaged.dmg').write_bytes(b'not a disk image')
        result = run(binary, fixture, capture_output=True, text=True)
        report = json.loads(result.stdout)
        (build/'result.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report))

if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or error.stdout or f'Fixture command failed with exit status {error.returncode}')
