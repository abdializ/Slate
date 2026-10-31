#!/usr/bin/env python3
# File purpose: Checks per-pane zoom, zoom persistence, and transient download feedback.

"""Native per-pane zoom, persistence and transient download feedback regression.

Requires a SLATE_ENABLE_VERIFY build. Uses isolated data and loopback downloads.
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


# Slate note: Serve loopback fixtures and drive verification commands against isolated application state.
def verify(app, log_path):
    with tempfile.TemporaryDirectory(prefix='slate-interactions-') as scratch:
        root = Path(scratch)
        pages = root / 'pages'
        pages.mkdir()
        for name, color in [('left', '#d5e8fa'), ('right', '#d8efdf')]:
            (pages / f'{name}.html').write_text(
                f'<html><body style="background:{color};font:32px system-ui">'
                f'<h1>{name}</h1><input value="original"></body></html>')
        (pages / 'download.txt').write_text('Slate download feedback test\n' * 1024)

        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(pages)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}'
        commands = [f'go {url}/left.html', 'sleep 1',
                    "exec window.zoomState='left';document.querySelector('input').value='edited left'",
                    'newtab', f'go {url}/right.html', 'sleep 1',
                    'select 1', 'splitright 2', 'sleep 0.2', 'select 1',
                    'zoomin', 'checkzoom 1 110 2 100',
                    'zoomin', 'checkzoom 1 125 2 100',
                    'select 2', 'checkfeedback', 'zoomout', 'checkzoom 1 125 2 90',
                    'resetzoom', 'checkzoom 1 125 2 100',
                    'select 1', 'zoomout', 'checkzoom 1 110 2 100',
                    'swapsplit', 'zoomin', 'checkzoom 1 125 2 100',
                    'newtab', 'checkzoom 1 125 2 100 3 100',
                    'select 1', 'setvertical 1', 'zoomin', 'checkzoom 1 150 2 100 3 100',
                    'sleep 2.2', 'checkfeedback',
                    f'download {url}/download.txt', 'sleep 0.1', 'checkfeedback',
                    'sleep 1.1', 'checkfeedback', 'setvertical 0',
                    f'download {url}/download.txt', f'download {url}/download.txt',
                    f'download {url}/download.txt', 'sleep 0.1', 'checkfeedback',
                    'sleep 1.1', 'checkfeedback',
                    f"exec (()=>{{let a=document.createElement('a');a.href='{url}/download.txt';a.download='webkit-feedback.txt';document.body.appendChild(a);a.click()}})()",
                    'sleep 0.2', 'checkfeedback', 'sleep 1.1', 'checkfeedback',
                    'tearoff 2', 'sleep 0.2', 'verifywindowkey 2 plus', 'checkzoom 1 150 2 110 3 100',
                    'verifywindowkey 2 zero', 'checkzoom 1 150 2 100 3 100', 'reattach 2', 'select 1',
                    "exec (()=>{if(window.zoomState!=='left'||document.querySelector('input').value!=='edited left')throw Error('ZOOM_STATE_LOST');return 'ZOOM_STATE_OK'})()",
                    'sleep 0.2', 'quit']
        staged = root / 'Slate.app'
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(app), str(staged)], check=True)
        subprocess.run(['/usr/bin/xattr', '-cr', str(staged)], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(staged)], check=True, capture_output=True)
        env = dict(os.environ, SLATE_AUTOMATED_INPUT_ONLY='1', SLATE_DATA_DIR=str(root / 'data'), SLATE_DOWNLOADS_DIR=str(root / 'downloads'),
                   SLATE_COMMAND_FILE=str(root / 'commands.txt'))
        def run(commands):
            (root / 'commands.txt').write_text('\n'.join(commands) + '\n')
            result = subprocess.run([str(staged / 'Contents/MacOS/Slate')], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            if log_path:
                log_path.write_bytes(result.stdout)
            assert result.returncode == 0, f'Slate exited with {result.returncode}'
            return result.stdout.decode(errors='replace')
        try:
            log = run(commands)
            restored = run(['sleep 1', 'checkzoom 1 150 2 100 3 100', 'quit'])
        finally:
            server.shutdown()
            server.server_close()
        if log_path:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(log + '\n--- RELAUNCH ---\n' + restored)
        zoom = re.findall(r'SLATE_ZOOM_CHECK failures=(\d+) indicator=(\d+) target=(\d+) percent=(\d+)', log)
        assert len(zoom) == 10 and all(row[0] == '0' for row in zoom), f'Zoom isolation failed: {zoom}'
        assert [row[2:] for row in zoom[:6]] == [('1','110'),('1','125'),('2','90'),('2','100'),('1','110'),('1','125')], 'Indicator followed the wrong pane'
        feedback = re.findall(r'SLATE_FEEDBACK_CHECK arrivals=(\d+) zoom=(\d+)', log)
        assert feedback == [('0','0'),('0','0'),('1','0'),('0','0'),('1','0'),('0','0'),('1','0'),('0','0')], f'Feedback blocked input, accumulated or leaked: {feedback}'
        assert 'SLATE_JS_RESULT: ZOOM_STATE_OK' in log and not re.search(r'SLATE_JS_ERROR:.*ZOOM_STATE_LOST', log), 'Zoom recreated the page'
        assert re.findall(r'SLATE_ZOOM_CHECK failures=(\d+)', restored) == ['0'], 'Per-tab zoom did not survive restart'
        assert log.count('SLATE_DOWNLOAD_PUBLISHED success=1') == 5, 'URLSession or WebKit download failed'
        print('10 native zoom checks passed: independent panes, reset, swap, new tab, vertical layout, detached window and restart.')
        print('Download feedback passed: visible in both toolbar layouts, bounded to one effect, click-through and removed after arrival.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--log', type=Path)
    args = parser.parse_args()
    verify(args.app.resolve(), args.log)
