#!/usr/bin/env python3
# File purpose: Exercises native drag routing, split holds, cancellation, and tear-off gestures.

"""Native split-versus-tear-off regression; isolated profile and loopback pages only.

Requires SLATE_ENABLE_VERIFY=ON. Exercises production drag-intent routing and
actual mouse tracking, including stationary holds, Escape and return to the bar.
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


# Slate note: Run the verification app with isolated browser data and local fixtures; production
# verification commands must be enabled in its build.
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
        modes=['center','quick','holdleft','holdright','leave','switch','reenter']
        commands=[f'go {url}/alpha.html','sleep 0.5','newtab',f'go {url}/beta.html','sleep 0.5',edit(2),'select 1','setvertical 0']
        for mode in modes: commands += [f'verifydragintent 2 {mode}',intact(2)]
        for mode in ['quick','hold','leave','return','escape','rowquick','rowhold']: commands += [f'verifymouseintent 2 {mode}',intact(2)]
        commands += ['newtab', f'go {url}/gamma.html', 'sleep 0.5', 'select 1', 'verifylatestdrag 2 3', intact(2), 'setvertical 1']
        for mode in modes: commands += [f'verifydragintent 2 {mode}',intact(2)]
        commands += ['verifylatestdrag 2 3', 'verifysidebardrop 2 1','exitsplit','select 1','verifypagedrop 2 left','exitsplit','select 1','quit']
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
            checks=re.findall(r'SLATE_DRAG_INTENT .*failures=(\d+)',log)
            assert checks==['0']*14, f'Intent routing failed; see {log_path}'
            assert re.findall(r'SLATE_LATEST_DRAG failures=(\d+)',log)==['0','0'], 'Edge settling, hysteresis or split extraction failed'
            assert re.findall(r'SLATE_VERTICAL_DROP .*failures=(\d+)',log)==['0','0'], 'Sidebar reorder or page split failed'
            assert re.findall(r'SLATE_MOUSE_INTENT .*failures=(\d+)',log)==['0']*7, 'Native mouse tracking failed'
            assert log.count('SLATE_JS_RESULT: WINDOW_STATE_OK_2')==22, 'Page/form state lost in a drag'
            assert not re.search(r'SLATE_JS_ERROR:.*WINDOW_STATE_LOST',log)
            assert log.count('SLATE_ENGINE_NAVIGATE')==3, 'Drag reloaded a page'
        finally:
            server.shutdown()
            server.server_close()
        print('14 native edge-drag checks passed in horizontal and vertical layouts: quick release, center tear-off, left/right settling, leaving, switching and re-entry.')
        print('Seven actual mouse-tracking checks, edge tolerance, preview-only release, split-half extraction and sidebar reorder passed; existing pages and edited forms retained without reload.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    verify(args.app.resolve(), args.log.resolve())
