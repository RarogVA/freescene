"""Run silent-startup updater fixtures without user Keychain, network or GUI."""
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
output = root / 'build/startup-updater-tests'
output.mkdir(parents=True, exist_ok=True)
environment = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
binary = output / 'startup-updater-test'
with (output / 'compile.log').open('w') as log:
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-mmacosx-version-min=13.0',
                    '-framework', 'Cocoa', '-framework', 'Security',
                    str(root / 'tests/native/startup_updater.m'), '-o', str(binary)],
                   cwd=root, env=environment, stdout=log, stderr=log, check=True)
result = subprocess.run([str(binary)], cwd=root, capture_output=True, text=True, check=True)
report = json.loads(result.stdout)
(output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
