#!/usr/bin/env python3
# coding: utf-8
"""Create a drag-to-Applications disk image from a verified FreeScene app."""
import argparse
from pathlib import Path
import subprocess
import plistlib
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--channel', choices=['preview', 'stable'], default='preview')
args = parser.parse_args()
if args.output.suffix.lower() != ".dmg":
    parser.error("macOS application packages must use the .dmg format")
version = plistlib.loads((args.bundle/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
architecture = subprocess.check_output(['lipo','-archs',str(args.bundle/'Contents/MacOS/FreeScene')],text=True).strip()
if architecture not in ('arm64','x86_64'): parser.error('Expected a single supported macOS architecture')
platform = 'Apple Silicon' if architecture=='arm64' else 'Intel x86_64'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.bundle)], check=True)
signature = subprocess.run(['codesign', '--display', '--verbose=2', str(args.bundle)],
                           check=True, capture_output=True, text=True).stderr
if 'Signature=adhoc' in signature:
    signature_text = 'Сборка с локальной ad hoc подписью, без Developer ID и нотаризации.'
elif 'Authority=Developer ID Application:' in signature:
    signature_text = 'Сборка подписана сертификатом Developer ID. Нотаризация проверяется отдельно.'
else:
    signature_text = ('Сборка подписана постоянным локальным сертификатом FreeScene.\n'
                      'Developer ID и нотаризация Apple отсутствуют.')
stage = args.output.parent / 'dmg-content'
stage.mkdir(parents=True, exist_ok=True)
subprocess.run(['ditto', str(args.bundle), str(stage / 'FreeScene.app')], check=True)
if not (stage / 'Applications').exists():
    (stage / 'Applications').symlink_to('/Applications')
repair = stage / 'Исправить запуск.command'
shutil.copyfile(Path(__file__).with_name('fix_macos_launch.command'), repair)
repair.chmod(0o755)
edition = ' Preview' if args.channel == 'preview' else ''
(stage / 'Установка.txt').write_text(f'''FreeScene {version}{edition} — macOS 13+, {platform}

Перетащите FreeScene.app в Applications. Запускайте приложение из Applications.

Если приложение не запускается, откройте «Исправить запуск.command» на этом диске.
Скрипт очищает расширенные атрибуты только /Applications/FreeScene.app.
После завершения снова откройте установленное приложение.

{signature_text}
Если macOS блокирует первый запуск, после попытки открыть приложение используйте
Системные настройки → Конфиденциальность и безопасность → Всё равно открыть.
Инструкция Apple: https://support.apple.com/en-us/102445

Лицензии: FreeScene → О приложении → Лицензии открытого ПО.
Исходники VLC/FFmpeg и contrib: FreeScene-VLC-sources.tar.gz в том же Release.
Это ПО использует библиотеки FFmpeg на условиях LGPL 2.1 или более поздней версии.
''', encoding='utf-8')
subprocess.run(['hdiutil', 'create', '-volname', 'FreeScene', '-srcfolder', str(stage),
                '-format', 'UDZO', '-o', str(args.output)], check=True)
