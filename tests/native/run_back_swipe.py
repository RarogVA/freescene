"""Compile the Cocoa-only back-swipe regression without launching the app."""
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
destination = root / 'build/native-back-swipe-tests'
destination.mkdir(parents=True, exist_ok=True)
environment = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
command = ['xcrun', 'clang++', '-std=c++17', '-fobjc-arc',
           '-mmacosx-version-min=13.0', '-framework', 'Cocoa',
           str(root / 'tests/native/back_swipe.mm'), '-o', str(destination / 'back-swipe-test')]
with (destination / 'build.log').open('w') as log:
    subprocess.run(command, cwd=root, env=environment, stdout=log, stderr=log, check=True)
result = subprocess.run([str(destination / 'back-swipe-test')], cwd=root,
                        capture_output=True, text=True, check=True)
report = json.loads(result.stdout)
(destination / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
