#!/usr/bin/env python3
"""Check persistent full-screen window controls in an isolated macOS app.

Requires SLATE_ENABLE_VERIFY=ON. Runs real full-screen transitions, verifies
hit targets and space for browser navigation, and clicks the green exit control.
"""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import uuid


def verify(app, log_path=None):
    with tempfile.TemporaryDirectory(prefix='slate-fullscreen-') as scratch:
        root = Path(scratch)
        data = root / 'data'
        data.mkdir()
        commands = ['setvertical 0', 'sleep 1', 'checkwindowcontrols 0',
                    'fullscreen', 'sleep 3', 'checkwindowcontrols 1',
                    'setvertical 1', 'sleep 1', 'checkwindowcontrols 1',
                    'sidebarwidth 68', 'sleep 1', 'checkwindowcontrols 1',
                    'togglecollapse', 'sleep 1', 'checkwindowcontrols 1',
                    'setvertical 0', 'sleep 1', 'checkwindowcontrols 1',
                    'togglecollapse', 'sleep 1', 'checkwindowcontrols 1',
                    'exitfullscreenbutton', 'sleep 3', 'checkwindowcontrols 0',
                    'fullscreen', 'sleep 3', 'checkwindowcontrols 1',
                    'setvertical 1', 'sleep 1', 'checkwindowcontrols 1']
        commands += ['exitfullscreenbutton', 'sleep 3', 'checkwindowcontrols 0', 'quit']
        command_file = root / 'commands.txt'
        command_file.write_text('\n'.join(commands) + '\n')
        staged = root / 'Slate Fullscreen Test.app'
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(app), str(staged)], check=True)
        info_path = staged / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleIdentifier'] = 'dev.slate.fullscreen-test.' + uuid.uuid4().hex
        info['CFBundleName'] = 'Slate Fullscreen Test'
        info_path.write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/xattr', '-cr', str(staged)], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(staged)], check=True, capture_output=True)
        env = dict(os.environ, SLATE_DATA_DIR=str(data), SLATE_COMMAND_FILE=str(command_file))
        log_file = root / 'app.log'
        with log_file.open('w') as log:
            proc = subprocess.Popen([str(staged / 'Contents/MacOS/Slate')], env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
            try:
                proc.wait(timeout=65)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=10)
                if log_path:
                    log_path.parent.mkdir(parents=True, exist_ok=True)
                    log_path.write_text(log_file.read_text())
        text = log_file.read_text()
        checks = re.findall(r'SLATE_WINDOW_CONTROLS fullscreen=(\d) vertical=(\d) collapsed=(\d) failures=(\d+)', text)
        assert proc.returncode == 0, f'Test app exited with {proc.returncode}'
        assert len(checks) == 11, f'Expected 11 checks, got {len(checks)}; use the latest verification build'
        assert all(row[3] == '0' for row in checks), f'Window control checks failed: {checks}'
        assert sum(row[0] == '0' for row in checks) == 3, 'Green button did not complete both exits'
        assert {row[1:3] for row in checks if row[0] == '1'} >= {('0', '0'), ('0', '1'), ('1', '0'), ('1', '1')}
        print('11 checks passed: persistent full-screen controls in horizontal, vertical, rail and collapsed layouts; two green-button exits; native controls restored.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--log', type=Path)
    args = parser.parse_args()
    verify(args.app.resolve(), args.log)
