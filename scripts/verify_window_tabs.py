#!/usr/bin/env python3
# File purpose: Checks detached-window tabs, shortcuts, popup routing, and view-preserving tab
# transfers.

"""Native multi-window tabs regression; isolated profile and loopback pages only.

Requires SLATE_ENABLE_VERIFY=ON. Exercises production shortcut, plus-button and
screen-space drop routing, and verifies WKWebViews are reused across transfers.
"""
import argparse
import functools
import http.server
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading


# Slate note: The scripted moves verify that transferring a live tab retains its edited fields and
# JavaScript state.
def verify(app, log_path):
    with tempfile.TemporaryDirectory(prefix='slate-window-tabs-') as scratch:
        root = Path(scratch)
        pages = root / 'pages'
        pages.mkdir()
        for name in ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'popup']:
            (pages / f'{name}.html').write_text(
                f'<html><head><title>{name.title()}</title></head>'
                f'<body style="font:24px system-ui"><h1>{name}</h1><input value="original"></body></html>')

        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(pages)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}'
        def edit(tab):
            return f"windowexec {tab} window.moveToken='{tab}';document.querySelector('input').value='edited {tab}'"
        def intact(tab):
            return f"windowexec {tab} (()=>{{if(window.moveToken!=='{tab}'||document.querySelector('input').value!=='edited {tab}')throw Error('WINDOW_STATE_LOST');return 'WINDOW_STATE_OK_{tab}'}})()"
        commands = [f'go {url}/alpha.html', 'sleep 0.5', edit(1),
                    'newtab', f'go {url}/beta.html', 'sleep 0.5', edit(2),
                    'newtab', f'go {url}/gamma.html', 'sleep 0.5', edit(3),
                    'verifywindow main 3 1,2,3', 'tearoff 2', 'verifywindow 2 2 2',
                    'verifywindowkey 2 t', 'verifywindow 2 4 2,4',
                    'verifywindow main 3 1,3', 'verifywindowkey 2 1', 'verifywindow 2 2 2,4',
                    'verifywindowclick 2 4', 'verifywindow 2 4 2,4',
                    'verifywindowclick 2 2', 'verifywindow 2 2 2,4',
                    'verifywindowkey 2 next', 'verifywindow 2 4 2,4',
                    f'detachedgo 4 {url}/delta.html', 'sleep 0.5', edit(4),
                    'verifywindowkey 2 n', 'verifywindow 5 5 5',
                    f'detachedgo 5 {url}/epsilon.html', 'sleep 0.5', edit(5),
                    'verifywindowplus 5', 'verifywindow 5 6 5,6',
                    'verifywindowkey 5 t', 'verifywindowkey 5 t', 'verifywindowkey 5 t', 'verifywindowkey 5 t',
                    'verifywindow 5 10 5,6,7,8,9,10', 'select 5',
                    'verifydrop 2 5 6', 'verifywindow 5 2 5,2,6,7,8,9,10',
                    'verifywindow 4 4 4', intact(2),
                    'verifydrop 2 main 1', 'verifywindow main 2 2,1,3',
                    'verifywindow 5 6 5,6,7,8,9,10', intact(2),
                    'verifydrop 4 5 5', 'verifywindow 5 4 4,5,6,7,8,9,10', intact(4),
                    'verifydrop 3 5 6', 'sleep 0.2', 'verifywindow 5 3 4,5,3,6,7,8,9,10',
                    'verifywindow main 2 2,1', intact(3),
                    'verifywindowkey main 9', 'verifywindowkey main w', 'sleep 0.3',
                    'verifywindow main 2 2', 'verifywindow 5 3 4,5,3,6,7,8,9,10',
                    'verifydrop 3 5 4', 'verifywindow 5 3 3,4,5,6,7,8,9,10',
                    'verifywindowkey 5 9', 'verifywindow 5 10 3,4,5,6,7,8,9,10',
                    'verifywindowkey 5 w', 'sleep 0.2', 'verifywindow 5 9 3,4,5,6,7,8,9',
                    'verifywindowclose 6', 'sleep 0.2', 'verifywindow 5 9 3,4,5,7,8,9',
                    'tearoff 4', 'verifywindow 4 4 4', 'verifywindow 5 9 3,5,7,8,9',
                    'verifydrop 4 main 0', 'sleep 0.2', 'verifywindow main 4 2,4', intact(4), intact(5),
                    f"windowexec 5 window.open('{url}/popup.html','_blank');void 0", 'sleep 0.7',
                    'verifywindow 5 11 3,5,7,8,9,11',
                    'verifywindowkey 5 shiftw', 'sleep 0.3', 'verifywindow main 4 2,4',
                    'verifywindowdrag 4 page', 'verifywindow 4 4 4', 'verifywindow main 2 2',
                    'verifywindowkey 4 t', 'verifywindow 4 12 4,12',
                    'verifywindowdrag 4 page', 'verifywindow 4 4 4', 'verifywindow 12 12 12',
                    'verifydrop 4 main 0', 'sleep 0.2', 'verifywindow main 4 2,4',
                    'verifydrop 12 main 0', 'verifywindow main 12 2,4,12',
                    'verifywindowkey main w', 'sleep 0.3', 'verifywindow main 4 2,4',
                    'sleep 0.2', 'quit']
        staged = root / 'Slate.app'
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(app), str(staged)], check=True)
        subprocess.run(['/usr/bin/xattr', '-cr', str(staged)], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(staged)], check=True, capture_output=True)
        env = dict(os.environ, SLATE_AUTOMATED_INPUT_ONLY='1', SLATE_DATA_DIR=str(root / 'data'), SLATE_COMMAND_FILE=str(root / 'commands.txt'))
        log_path.parent.mkdir(parents=True, exist_ok=True)
        def run(commands):
            (root / 'commands.txt').write_text('\n'.join(commands) + '\n')
            result = subprocess.run([str(staged / 'Contents/MacOS/Slate')], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            log_path.write_bytes(result.stdout)
            assert result.returncode == 0, f'Slate exited with {result.returncode}; see {log_path}'
            return result.stdout.decode(errors='replace')
        try:
            log = run(commands)
            checks = re.findall(r'SLATE_WINDOW_TABS .*failures=(\d+)', log)
            assert len(checks) == sum(c.startswith('verifywindow ') for c in commands), 'Native window checks did not run'
            expected_windows = []
            window_count = 0
            for command in commands:
                if command in ['tearoff 2', 'verifywindowkey 2 n', 'tearoff 4', 'verifywindowdrag 4 page']:
                    window_count += 1
                elif command in ['verifydrop 4 5 5', 'verifydrop 4 main 0', 'verifywindowkey 5 shiftw', 'verifydrop 12 main 0']:
                    window_count -= 1
                if command.startswith('verifywindow '):
                    expected_windows.append(str(window_count))
            assert re.findall(r'SLATE_WINDOW_TABS .*secondary_windows=(\d+)', log) == expected_windows, 'An empty source window was retained'
            assert all(c == '0' for c in checks), f'Window membership, active page or view reuse failed; see {log_path}'
            assert re.findall(r'SLATE_WINDOW_DROP .*moved=(\d+)', log) == ['1'] * 8, 'Tab-bar drop failed'
            assert not re.search(r'SLATE_JS_ERROR:.*WINDOW_STATE_LOST', log), 'Transfer lost page/form state'
            for tab in [2,3,4,5]:
                assert f'SLATE_JS_RESULT: WINDOW_STATE_OK_{tab}' in log, f'Missing page-state check for {tab}'
            assert 'SLATE_POPUP_TAB id=11' in log, 'Popup was not created in its source window'
            assert re.findall(r'SLATE_WINDOW_TABS .*secondary_windows=(\d+)', log)[-1] == '0', 'Closing the secondary window leaked another window'
            restored = run(['sleep 0.5', 'verifywindow main 4 2,4', 'quit'])
            log_path.write_text(log + '\n--- RELAUNCH ---\n' + restored)
            assert re.findall(r'SLATE_WINDOW_TABS .*failures=(\d+)', restored) == ['0'], 'Remaining tabs did not survive restart'
        finally:
            server.shutdown()
            server.server_close()
        print(f'{len(checks)} native window checks passed: new tabs, plus button, shortcuts, switching, overflow, eight transfers and in-window tear-off, reorder, close and source-window popup.')
        print('Existing page views, JavaScript and edited forms preserved; last-tab transfer closes only its empty source; remaining tabs survive restart.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    verify(args.app.resolve(), args.log.resolve())
