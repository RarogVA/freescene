"""Check the macOS download set, write combined checksums, and print release links."""
import argparse
import hashlib
from pathlib import Path
import re


def dmg_names(version, arch):
    if not re.fullmatch(r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)', version):
        raise ValueError('Expected a three-part stable version')
    if arch not in ('arm64', 'x86_64'):
        raise ValueError('Unsupported architecture')
    number = tuple(map(int, version.split('.')))
    versioned = f'FreeScene-{version}-macos-{arch}.dmg'
    stable = f'FreeScene-macos-{arch}.dmg'
    if number < (2, 0, 5):
        return [versioned]
    return [stable, versioned] if number == (2, 0, 5) else [stable]


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def check_images(directory, version, architectures):
    groups = []
    for arch in architectures:
        names = dmg_names(version, arch)
        legacy_alias = directory / f'FreeScene-macos-{arch}.dmg'
        if names[0] != legacy_alias.name and legacy_alias.is_file():
            # Older releases could publish an additional stable download link.
            names.append(legacy_alias.name)
        groups.append(names)
    images = [directory / name for group in groups for name in group]
    if set(directory.glob('*.dmg')) != set(images):
        raise ValueError('Unexpected or missing macOS disk image')
    for group in groups:
        if len(group) == 2 and sha256(directory / group[0]) != sha256(directory / group[1]):
            raise ValueError('Transition images must be identical')
    return images


def finalize(directory, version):
    images = check_images(directory, version, ('arm64', 'x86_64'))
    assets = sorted([*images, *directory.glob('*.apk'), *directory.glob('*.tar.gz')])
    manifest = directory / 'SHA256SUMS.txt'
    lines = ''.join(f'{sha256(path)}  {path.name}\n' for path in assets)
    temporary = manifest.with_suffix('.tmp')
    temporary.write_text(lines, encoding='utf-8')
    temporary.replace(manifest)
    for label, arch in [('Apple Silicon (M1 и новее)', 'arm64'), ('Intel', 'x86_64')]:
        name = dmg_names(version, arch)[0]
        print(f'[Скачать для Mac с {label}](https://github.com/RarogVA/freescene/releases/download/v{version}/{name})')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    finalize(args.directory, args.version)
