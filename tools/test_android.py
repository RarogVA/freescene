#!/usr/bin/env python3
"""Run both native flavor suites with the version declared by this checkout."""
import os
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
version = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)$', (root/'pubspec.yaml').read_text(), re.M)
if not version:
    raise SystemExit('Missing version/build in pubspec.yaml')
environment = dict(os.environ)
if sys.platform == 'darwin':
    environment.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    environment.setdefault('JAVA_HOME', subprocess.check_output(['/usr/libexec/java_home', '-v', '17'], text=True).strip())
subprocess.run(['flutter', 'pub', 'get', '--enforce-lockfile'], cwd=root, env=environment, check=True)
subprocess.run([str(root/'android/gradlew'), '-p', str(root/'android'),
                '-Pflutter.versionName='+version[1], '-Pflutter.versionCode='+version[2],
                ':app:testMobileDebugUnitTest', ':app:testTvDebugUnitTest'], cwd=root, env=environment, check=True)
