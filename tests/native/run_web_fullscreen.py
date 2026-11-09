"""Run headless fullscreen checks, or build a local manual WebKit UI fixture."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parents[2]
(root / 'build').mkdir(exist_ok=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ui', action='store_true', help='Build the manual fixture without launching it')
args = parser.parse_args()
environment = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
output = root / 'build/web-fullscreen-test'
source = root / 'tests/native/web_fullscreen.m'
if args.ui:
    contents = root / 'build/FreeSceneFullscreenFixture.app/Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.freescene.fullscreen-fixture',
        'CFBundleName': 'FreeScene Fullscreen Fixture',
        'CFBundleExecutable': 'FullscreenFixture',
        'CFBundlePackageType': 'APPL',
        'LSMinimumSystemVersion': '13.0',
        'NSHighResolutionCapable': True,
    }))
    output = contents / 'MacOS/FullscreenFixture'
    source = root / 'tests/native/web_fullscreen_ui.m'
subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-mmacosx-version-min=13.0',
                '-framework', 'Cocoa', '-framework', 'WebKit', str(source), '-o', str(output)],
               cwd=root, env=environment, check=True)
if args.ui:
    subprocess.run(['codesign', '--force', '--sign', '-', str(contents.parent)], check=True)
    print(contents.parent)
else:
    result = subprocess.check_output([str(output)], cwd=root, text=True)
    (root / 'build/web-fullscreen.json').write_text(result)
    print(result.strip())
