"""Build the headless close/episode regression against real bundled libraries."""
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
flutter = Path(shutil.which('flutter')).resolve().parents[1]
framework = flutter / 'bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64'
vlc = root / 'build/native/vlc'
environment = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
command = ['xcrun', 'clang++', '-std=c++17', '-fobjc-arc', '-F'+str(framework),
           '-framework', 'FlutterMacOS', '-I'+str(root/'build/native/include'),
           '-L'+str(vlc/'lib'), '-lvlc', '-L'+str(root/'build/native'), '-lFreeSceneEngine']
host=root/'packages/freescene_provider_host/macos/freescene_provider_host/Sources/freescene_provider_host'
command += ['-I'+str(host/'include'), '-x', 'objective-c++', str(host/'FreesceneProviderHostPlugin.m')]
for name in ['Cocoa', 'QuartzCore', 'WebKit', 'CoreText', 'Security', 'UserNotifications', 'UniformTypeIdentifiers']:
    command += ['-framework', name]
for path in [framework, vlc/'lib', root/'build/native']:
    command += ['-Wl,-rpath,'+str(path)]
command += ['tests/native/player_lifecycle.mm', '-o', 'build/player-lifecycle-test']
with (root/'build/player-lifecycle-build.log').open('w') as log:
    subprocess.run(command, cwd=root, env=environment, stdout=log, stderr=log, check=True)
with (root/'build/player-lifecycle.json').open('w') as output:
    subprocess.run(['build/player-lifecycle-test'], cwd=root, stdout=output, check=True)
print((root/'build/player-lifecycle.json').read_text())
