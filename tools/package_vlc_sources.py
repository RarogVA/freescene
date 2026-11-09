#!/usr/bin/env python3
"""Fetch checksum-pinned VLC/contrib sources and collect distribution notices."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'tools/vlc-dependencies.json'


def digest(path, algorithm='sha256'):
    result = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def fetch(package, cache):
    target = cache / package['archive']
    algorithm = 'sha512' if 'sha512' in package else 'sha256'
    if not target.exists():
        temporary = target.with_name(target.name + '.part')
        subprocess.run(['curl', '-fLsS', '--retry', '2', '--max-time', '300',
                        '-o', str(temporary), package['url']], check=True)
        temporary.replace(target)
    if digest(target, algorithm) != package[algorithm]:
        raise RuntimeError('Source checksum mismatch: ' + target.name)
    return target


def read_members(archive, suffixes):
    result = []
    with tarfile.open(archive) as source:
        for suffix in suffixes:
            matches = [member for member in source.getmembers()
                       if member.isfile() and member.name.endswith('/' + suffix)]
            if not matches:
                raise RuntimeError(f'Missing {suffix} in {archive.name}')
            # Select the shortest path, e.g. project COPYING rather than tests.
            member = min(matches, key=lambda entry: len(entry.name))
            result.append(source.extractfile(member).read().decode('utf-8', errors='replace'))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/vlc-audit/sources')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text())
    packages = [dict(id='vlc', name='libVLC', version=manifest['vlcVersion'],
                     license='LGPL-2.1-or-later', **manifest['vlcSource'])] + manifest['packages']
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda package: fetch(package, args.cache), packages))
    notices = {
        'vlc': ['COPYING.LIB'], 'dvbpsi':['COPYING'], 'ffmpeg': ['COPYING.LGPLv2.1'],
        'gsm': ['COPYRIGHT'], 'lame': ['COPYING'], 'openjpeg': ['LICENSE'],
        'zlib': ['LICENSE'], 'freetype2': ['docs/FTL.TXT'],
        'fribidi': ['COPYING'], 'harfbuzz': ['COPYING'],
        'ebml': ['LICENSE.LGPL'], 'matroska': ['LICENSE.LGPL'],
        'speexdsp': ['COPYING'], 'gettext': ['gettext-runtime/intl/COPYING.LIB'],
    }
    sections = [
        'FreeScene uses libVLC and libraries from the FFmpeg project under LGPL 2.1 or later.\n'
        'Complete VLC/contrib sources, patches and build recipes accompany the binary Release:\n'
        'https://github.com/RarogVA/freescene/releases\n'
        'FreeScene own code is MIT. No restriction on debugging modified libraries is imposed.\n'
        'VLC securetransport TLS module: Copyright (C) 2013 David Fuhrmann; LGPL-2.1-or-later.\n'
        'Portions of this software are copyright © 2022 The FreeType Project (www.freetype.org).\n'
        'All rights reserved. FreeType is used under the FreeType License (FTL).\n'
    ]
    for package in packages:
        heading = f"{package['name']} {package['version']} — {package['license']}"
        sections.append(heading + '\n' + '=' * len(heading) + '\n' +
                        '\n'.join(read_members(args.cache / package['archive'], notices[package['id']])))
    with tarfile.open(args.cache / manifest['vlcSource']['archive']) as source:
        opus = source.extractfile('vlc-3.0.21/modules/codec/opus_header.c').read().decode()
        sections.append('VLC MPEG-TS Opus header parser — BSD-2-Clause\n' + opus.split('*/', 1)[0] + '*/')
    notice_path = ROOT / 'licenses/VLC-THIRD-PARTY-NOTICES.txt'
    notice_path.write_text('\n\n'.join(sections) + '\n')
    source_directory = args.output / 'FreeScene-VLC-sources'
    source_directory.mkdir(exist_ok=True)
    for package in packages:
        shutil.copy2(args.cache / package['archive'], source_directory / package['archive'])
    shutil.copy2(MANIFEST, source_directory / MANIFEST.name)
    shutil.copy2(ROOT / 'docs/vlc-distribution.md', source_directory / 'README.md')
    shutil.copy2(notice_path, source_directory / notice_path.name)
    shutil.copy2(ROOT / 'tools/audit_vlc_distribution.py', source_directory / 'audit_vlc_distribution.py')
    for name in ('vlc-distribution-arm64.json', 'vlc-distribution-x86_64.json',
                 'vlc-module-headers.json'):
        shutil.copy2(ROOT / 'validation/freescene' / name, source_directory / name)
    archive = args.output / (source_directory.name + '.tar.gz')
    with tarfile.open(archive, 'w:gz') as output:
        output.add(source_directory, arcname=source_directory.name)
    report = dict(sources=[dict(id=p['id'], archive=p['archive'], sha256=digest(args.cache / p['archive']))
                           for p in packages], archive=archive.name, archiveSHA256=digest(archive))
    (args.output / 'vlc-sources.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(archive=str(archive), sha256=report['archiveSHA256'], packages=len(packages))))


if __name__ == '__main__':
    main()
