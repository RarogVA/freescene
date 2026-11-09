#!/usr/bin/env python3
"""Resize the approved source into the existing macOS, Android and TV icon slots."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/app-icon.png'


def resize(size, target):
    subprocess.run(['sips', '-z', str(size), str(size), str(SOURCE), '--out', str(target)],
                   check=True, stdout=subprocess.DEVNULL)


def main():
    icons = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for size in (16, 32, 64, 128, 256, 512, 1024):
        resize(size, icons / f'app_icon_{size}.png')
    android = ROOT / 'android/app/src'
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        resize(size, android / f'main/res/mipmap-{density}/ic_launcher.png')
    for flavor in ('main', 'tv'):
        resize(512, android / f'{flavor}/res/drawable/brand_icon.png')


if __name__ == '__main__':
    main()
