#!/usr/bin/env python3
"""Native split-switch regression; requires macOS and SLATE_ENABLE_VERIFY=ON.

Run: python3 scripts/verify_split_switch.py --app build/platform/macos/Slate.app
Uses a temporary app copy, fresh browser data and loopback-only test pages.
"""
import argparse
import functools
import http.server
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import threading


def verify(app, log_path, followup=False):
    with tempfile.TemporaryDirectory(prefix='slate-split-switch-') as scratch:
        root = Path(scratch)
        pages = root / 'pages'
        pages.mkdir()
        for name, color in [('left', '#d5e8fa'), ('right', '#d8efdf'), ('single', '#f1d9da')]:
            (pages / f'{name}.html').write_text(
                f'<html><body style="background:{color};font:40px system-ui">'
                f'<h1>{name}</h1><input value="original"></body></html>')
        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(pages)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}'
        commands = [f'go {url}/left.html', 'sleep 1',
                    "exec window.splitState='left';document.querySelector('input').value='edited left'",
                    'newtab', f'go {url}/right.html', 'sleep 1',
                    "exec window.splitState='right';document.querySelector('input').value='edited right'",
                    'select 1', 'splitright 2', 'sleep 1',
                    'newtab', f'go {url}/single.html', 'sleep 1',
                    'checkswitch 1', 'checkswitch 3', 'checkswitch 2',
                    'newtab', f'go {url}/left.html', 'newtab', f'go {url}/right.html',
                    'select 4', 'splitright 5', 'sleep 1']
        for _ in range(12):
            commands += ['checkswitch 3', 'checkswitch 1', 'checkswitch 5']
        commands += ['swapsplit', 'checkswitch 4', 'newtab', 'checkswitch 6',
                     'checkswitch 2', 'setvertical 1', 'checkswitch 3',
                     'checkswitch 1', 'setvertical 0', 'checkswitch 5',
                     'select 1',
                     "exec (()=>{if(window.splitState!=='left'||document.querySelector('input').value!=='edited left')throw Error('SPLIT_STATE_LOST');return 'SPLIT_STATE_OK_left'})()",
                     'select 2',
                     "exec (()=>{if(window.splitState!=='right'||document.querySelector('input').value!=='edited right')throw Error('SPLIT_STATE_LOST');return 'SPLIT_STATE_OK_right'})()",
                     'select 3', 'simulatepipdecline', 'checkswitch 1',
                     'checkpendingpip 3', 'sleep 2', 'checkhidden 3', 'checkswitch 2', 'quit']
        if followup:
            commands = [f'go {url}/left.html', 'sleep 1', 'newtab', f'go {url}/right.html',
                        'sleep 1', 'select 1', 'setvertical 1', 'verifysidebardrop 2 1',
                        'checkworkspace', 'newtab', f'go {url}/single.html', 'sleep 1',
                        'newtab', f'go {url}/right.html', 'sleep 1', 'select 3',
                        'verifypagedrop 4 left', 'checkworkspace', 'exitsplit', 'select 3',
                        'nativepip 3 1', 'inactivepipframe 3', 'checkpiptab 3 1',
                        'checkswitch 1', 'nativepip 3 0', 'checkpiptab 3 0', 'checkworkspace',
                        'nativepip 3 0', 'checkworkspace', 'setvertical 0',
                        'checkswitch 4', 'checkswitch 2', 'quit']
        command_file = root / 'commands.txt'
        command_file.write_text('\n'.join(commands) + '\n')
        staged = root / 'Slate.app'
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(app), str(staged)], check=True)
        subprocess.run(['/usr/bin/xattr', '-cr', str(staged)], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(staged)], check=True, capture_output=True)
        env = dict(os.environ, SLATE_DATA_DIR=str(root / 'data'), SLATE_COMMAND_FILE=str(command_file))
        try:
            result = subprocess.run([str(staged / 'Contents/MacOS/Slate')], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        finally:
            server.shutdown()
            server.server_close()
        log = result.stdout.decode(errors='replace')
        if log_path:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(log)
        validate(log, result.returncode, followup)


def validate(log, returncode, followup=False):
    switches = re.findall(r'SLATE_SWITCH_CHECK selected=(\d+) split=(\d+) failures=(\d+) elapsed_ms=([\d.]+)', log)
    checks = re.findall(r'SLATE_HIDDEN_CHECK .*failures=(\d+)', log)
    assert returncode == 0, f'Slate exited with {returncode}'
    expected=7 if followup else 47
    assert len(switches) == expected, f'Expected {expected} workspace checks, got {len(switches)}; use a verify-enabled build'
    assert all(int(row[2]) == 0 for row in switches), 'An incoming page was covered, hidden, or recreated'
    if followup:
        drops=re.findall(r'SLATE_VERTICAL_DROP .*failures=(\d+)',log)
        assert drops==['0','0'], 'Vertical sidebar or page drop failed'
        assert re.findall(r'SLATE_PIP_FRAME_CHECK .*failures=(\d+)',log)==['0','0'], 'Inactive ad frame disturbed native PiP'
        assert log.count('SLATE_ENGINE_NAVIGATE')==4, 'A workspace change reloaded a page'
        print('Vertical row/page drops, inactive ad frame and repeated native PiP exits passed; selected pages exposed.')
        return
    else:
        assert checks == ['0'], 'Outgoing page did not finish hiding after its PiP timeout'
        assert re.findall(r'SLATE_PENDING_PIP_CHECK .*failures=(\d+)', log) == ['0'], 'Declined PiP entry timeout was not exercised'
        assert 'SLATE_JS_RESULT: SPLIT_STATE_OK_left' in log and 'SLATE_JS_RESULT: SPLIT_STATE_OK_right' in log and not re.search(r'SLATE_JS_ERROR:.*SPLIT_STATE_LOST', log), 'Page/form state was lost'
        assert log.count('SLATE_ENGINE_NAVIGATE') == 5, 'A tab switch caused an unexpected navigation'
    times = [float(row[3]) for row in switches]
    print(f'{len(switches)} switches passed; existing pages and edited forms preserved; declined PiP cleanup passed.')
    print(f'Synchronous activation: median {statistics.median(times):.2f} ms, max {max(times):.2f} ms (excludes display scanout).')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--followup', action='store_true', help='Check vertical native drag delegates and ad/PiP transitions')
    args = parser.parse_args()
    verify(args.app.resolve(), args.log.resolve() if args.log else None, args.followup)
