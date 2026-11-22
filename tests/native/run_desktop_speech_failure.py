"""Check production macOS speech error mapping without recording or permission prompts."""
import json
import os
import platform
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
out = root / 'build/native-desktop-speech-tests'
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
with (out / 'build.log').open('w') as log:
    subprocess.run(['xcrun', 'swiftc', '-target', platform.machine() + '-apple-macos13.0',
                    str(root / 'macos/Runner/DesktopSpeechFailure.swift'),
                    str(root / 'tests/native/desktop_speech_failure.swift'),
                    '-o', str(out / 'speech-failure-test')],
                   cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
result = subprocess.check_output([out / 'speech-failure-test'], text=True)
report = json.loads(result)
(out / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print(result.strip())
