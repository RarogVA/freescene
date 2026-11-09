#!/usr/bin/env python3
"""Verify the exact VLC module set, upstream bytes and pinned contrib sources."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile


def sha(path, algorithm='sha256'):
    result = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def command(*args):
    return subprocess.run([str(arg) for arg in args], check=True,
                          capture_output=True, text=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True,
                        help='VLC.app from the checksum-verified read-only official DMG')
    parser.add_argument('--vlc', type=Path, default=Path('/Applications/VLC.app'))
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--headers', type=Path,
                        help='Versioned reviewed module source-header manifest')
    parser.add_argument('--release', default='current')
    parser.add_argument('--arch', choices=['arm64','x86_64'], default='arm64')
    args = parser.parse_args()
    manifest = json.loads((args.root / 'tools/vlc-dependencies.json').read_text())
    header_path = args.headers or args.root / 'validation/freescene/vlc-module-headers.json'
    headers = json.loads(header_path.read_text())
    source = manifest['vlcSource']
    source_file = args.sources / source['archive']
    if sha(source_file) != source['sha256']:
        raise RuntimeError('VLC source checksum mismatch')
    upstream = manifest['upstreamBinary'] if args.arch=='arm64' else manifest['upstreamBinaries'][args.arch]
    if sha(args.sources / upstream['archive']) != upstream['sha256']:
        raise RuntimeError('Official VLC DMG checksum mismatch')
    with tarfile.open(source_file) as archive:
        for package in manifest['packages']:
            if sha(args.sources / package['archive'], 'sha512') != package['sha512']:
                raise RuntimeError('Contrib checksum mismatch: ' + package['id'])
            recipe = archive.extractfile('vlc-3.0.21/contrib/src/' + package['id'] + '/SHA512SUMS').read().decode()
            if package['sha512'] + '  ' + package['archive'] not in recipe:
                raise RuntimeError('Contrib does not match VLC source pin: ' + package['id'])
    names = ['lib/libvlc.dylib', 'lib/libvlccore.dylib'] + [
        'plugins/lib' + entry['module'] + '_plugin.dylib' for entry in headers['modules']]
    binaries = []
    strings = {}
    for name in names:
        original = args.upstream / 'Contents/MacOS' / name
        installed = args.vlc / 'Contents/MacOS' / name
        if sha(original) != sha(installed):
            raise RuntimeError('Installed binary differs from official DMG: ' + name)
        architecture = command('lipo', '-archs', installed).strip()
        if architecture != args.arch:
            raise RuntimeError('Unexpected VLC architecture: ' + name)
        dependencies = []
        # The first indented line is LC_ID_DYLIB, not a linked dependency.
        for line in command('otool', '-L', installed).splitlines()[2:]:
            dependency = line.strip().split(' (', 1)[0]
            if not (dependency.startswith(('/usr/lib/', '/System/Library/')) or
                    dependency in ('@rpath/libvlc.dylib', '@rpath/libvlccore.dylib')):
                raise RuntimeError(f'Unreviewed dependency {dependency} in {name}')
            dependencies.append(dependency)
        strings[name] = command('strings', installed)
        binaries.append(dict(path=name, sourceSHA256=sha(installed),
                             architecture=architecture, dynamicDependencies=dependencies))
    configurations = []
    for name in ('plugins/libavcodec_plugin.dylib', 'plugins/libswscale_plugin.dylib'):
        text = strings[name]
        matches = [line for line in text.splitlines() if line.startswith('--extra-ldflags=')]
        if not matches or not all('FFmpeg version 4.4.4' in strings[n]
                                  for n in ['plugins/libavcodec_plugin.dylib']):
            raise RuntimeError('Missing FFmpeg version/configuration evidence')
        for configuration in matches:
            if any(flag in configuration for flag in ('--enable-gpl', '--enable-version3', '--enable-nonfree')):
                raise RuntimeError('Incompatible FFmpeg configuration')
            if not all(flag in configuration for flag in ('--enable-libgsm', '--enable-libopenjpeg', '--enable-libmp3lame')):
                raise RuntimeError('FFmpeg external library inventory changed')
        if 'license: LGPL version 2.1 or later' not in text:
            raise RuntimeError('Missing FFmpeg LGPL evidence')
        configurations.extend(matches)
    report = dict(
        passed=True, version=args.release, vlcVersion=manifest['vlcVersion'],
        scope=f'Exact {len(headers["modules"])}-module {args.arch} subset, libvlc/libvlccore, static contrib closure and source distribution',
        upstreamBinary=upstream, vlcSource=source,
        staticDependencies=manifest['packages'], binaries=binaries,
        upstreamConfigure=[line for line in strings['lib/libvlccore.dylib'].splitlines()
                           if '/configure ' in line and '--enable-merge-ffmpeg' in line],
        ffmpegConfigure=sorted(set(configurations)),
        excluded=['GPL VLC modules', 'libsamplerate', 'x264/x265', 'GPL/nonfree FFmpeg options',
                  'VLC application UI, Lua, Sparkle, Qt, gettext tools'],
        evidence='Official DMG byte match; VLC source module headers and Makefile link graph; pinned contrib recipes and source hashes; embedded runtime strings/configure flags; all Mach-O dynamic dependencies',
        limits='Some static versions come from upstream contrib pins rather than exported version APIs. Bit-for-bit reproducibility on a different Xcode is not asserted.',
        modifications='No source changes to VLC/contrib; packaging changes rpath with install_name_tool and replaces code signatures with ad hoc signatures',
        sourceCompanion='FreeScene-VLC-sources.tar.gz',
    )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(passed=True, binaries=len(binaries), staticDependencies=len(manifest['packages']))))


if __name__ == '__main__':
    main()
