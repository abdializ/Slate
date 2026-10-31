#!/usr/bin/env python3
"""Exercise the native Ctrl-Tab switcher using disposable local pages and data."""
import argparse
import functools
import http.server
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading


def verify(app, log_path, screenshot=None):
    with tempfile.TemporaryDirectory(prefix='slate-tab-switcher-') as scratch:
        root=Path(scratch)
        pages=root/'pages'; pages.mkdir()
        for name,color in [('Atlas','#d8e8ed'),('Notes','#f4e9cf'),('Journal','#e7dde9')]:
            (pages/f'{name}.html').write_text(f'''<html><head><title>{name}</title></head>
<body style="margin:0;background:{color};font:18px system-ui;color:#263940">
<main style="padding:38px"><small>SLATE WORKSPACE</small><h1>{name}</h1>
<p>A quieter place for your everyday browsing.</p><input value="original"><p>Saved locally. Ready when you are.</p></main></body></html>''')
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(pages)))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        url=f'http://127.0.0.1:{server.server_port}'
        commands=[f'go {url}/Atlas.html','sleep 0.7',
                  "exec window.switcherToken='kept';document.querySelector('input').value='edited'",
                  'newtab',f'go {url}/Notes.html','sleep 0.5',
                  'newtab',f'go {url}/Journal.html','sleep 0.5','select 1',
                  'switcher main tab','checkswitcher 1 1 3 1',
                  'switcher main tab','checkswitcher 1 1 2 1',
                  'switcher main release','checkswitcher 0 0 0 2',
                  'verifywindowkey main next','checkswitcher 0 0 0 1',
                  "exec (()=>{if(window.switcherToken!=='kept'||document.querySelector('input').value!=='edited')throw Error('SWITCHER_STATE_LOST');return 'SWITCHER_STATE_OK'})()",
                  'switcher main tab','switcher main escape','checkswitcher 0 0 0 1',
                  'switcher main back','checkswitcher 1 1 3 1','switcher main escape',
                  'select 2','splitright 3','select 1','switcher main tab',
                  'checkswitcher 1 1 2 1','switcher main release',
                  'checkswitcher 0 0 0 3','checkworkspace',
                  'exitsplit','select 1','tearoff 3','select 1',
                  'switcher main back','checkswitcher 1 1 3 1','switcher main release',
                  'verifywindow 3 3 3',
                  'switcher 3 tab','checkswitcher 1 1 1 1','switcher 3 escape',
                  'select 1','switcher main tab','switcher main mute',
                  'switcher main escape','select 2',
                  'newtab','newtab','newtab','newtab','newtab','newtab','newtab','newtab',
                  'select 1','switcher main tab','checkswitcher 1 1 11 1',
                  'switcher main down','checkswitcher 1 1 6 1',
                  'switcher main up','checkswitcher 1 1 11 1']
        if screenshot:
            commands.insert(commands.index('switcher main tab',commands.index('tearoff 3'))+2,f'switchershot {screenshot.with_name("tab-switcher-windows.png")}')
            commands += [f'switchershot {screenshot}']
        commands += ['switcher main close','sleep 0.3','checkswitcher 1 1 10 1',
                     'switcher main escape','checkswitcher 0 0 0 1',
                     'switcher main tab','switcherpointer main hover 2','checkswitcher 1 1 2 1',
                     'switcherpointer main click 2','checkswitcher 0 0 0 2',
                     'switcher main tab','switcherpointer main click 0','checkswitcher 0 0 0 2','quit']
        (root/'commands.txt').write_text('\n'.join(commands)+'\n')
        staged=root/'Slate.app'
        subprocess.run(['/usr/bin/ditto','--norsrc','--noextattr',str(app),str(staged)],check=True)
        subprocess.run(['/usr/bin/xattr','-cr',str(staged)],check=True)
        subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(staged)],check=True,capture_output=True)
        env=dict(os.environ,SLATE_AUTOMATED_INPUT_ONLY='1',SLATE_DATA_DIR=str(root/'data'),SLATE_COMMAND_FILE=str(root/'commands.txt'))
        try:
            run=subprocess.run([str(staged/'Contents/MacOS/Slate')],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        finally:
            server.shutdown();server.server_close()
        log=run.stdout.decode(errors='replace');log_path.write_text(log)
        checks=re.findall(r'SLATE_SWITCHER_CHECK .*failures=(\d+)',log)
        assert run.returncode==0, f'Exit {run.returncode}; see {log_path}'
        assert len(checks)==18 and all(x=='0' for x in checks), f'Switcher checks: {checks}; see {log_path}'
        assert 'SWITCHER_STATE_OK' in log and not re.search(r'SLATE_JS_ERROR:.*SWITCHER_STATE_LOST',log)
        assert not re.search(r'SLATE_(?:WINDOW|WORKSPACE)_CHECK .*failures=[1-9]',log)
        loads=re.findall(r'SLATE_SWITCHER_CHECK .*loaded=(\d+)',log)
        assert all(x=='3' for x in loads[:9]), 'Opening previews loaded an extra page'
        print(f'{len(checks)} native switcher checks passed; live form state and lazy tabs preserved.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--screenshot',type=Path)
    args=parser.parse_args()
    verify(args.app.resolve(),args.log.resolve(),args.screenshot.resolve() if args.screenshot else None)
