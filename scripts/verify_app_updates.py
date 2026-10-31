#!/usr/bin/env python3
"""Verify native update UI, preferences, signatures, and replacement of temporary app copies."""
import argparse
from pathlib import Path
import functools
import http.server
import os
import plistlib
import re
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

NS='http://www.andymatuschak.org/xml-namespaces/sparkle'
ACCOUNT='dev.slate.browser'

def run_command(args,**kwargs):
    return subprocess.run([str(x) for x in args],check=True,capture_output=True,**kwargs)

def verify(app,sparkle,log_path,screenshot):
    logs=[]
    with tempfile.TemporaryDirectory(prefix='slate-update-test-',dir='/private/tmp') as scratch:
        root=Path(scratch); web=root/'web';web.mkdir()
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=str(web)))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        base=f'http://127.0.0.1:{server.server_port}'
        def stage(target,identifier,build=None):
            run_command(['/usr/bin/ditto','--norsrc','--noextattr',app,target])
            info_path=target/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
            assert info['SlateVerificationEnabled'], 'Native checks need a verify-enabled build'
            info['CFBundleIdentifier']=identifier
            info['SUEnableAutomaticChecks']=False
            if build:info['CFBundleVersion']=build
            info_path.write_bytes(plistlib.dumps(info))
            run_command(['/usr/bin/codesign','--force','--sign','-',target])
            return info
        def feed(path,build,version,archive=None):
            ET.register_namespace('sparkle',NS)
            rss=ET.Element('rss',version='2.0');channel=ET.SubElement(rss,'channel')
            ET.SubElement(channel,'title').text='Slate Test Updates'
            if archive:
                item=ET.SubElement(channel,'item')
                ET.SubElement(item,'title').text='Slate test update'
                ET.SubElement(item,f'{{{NS}}}version').text=build
                ET.SubElement(item,f'{{{NS}}}shortVersionString').text=version
                ET.SubElement(item,f'{{{NS}}}minimumSystemVersion').text='12.0'
                signature=run_command([sparkle/'bin/sign_update','--account',ACCOUNT,'-p',archive]).stdout.decode().strip()
                ET.SubElement(item,'enclosure',{'url':f'{base}/{archive.name}','length':str(archive.stat().st_size),
                    'type':'application/octet-stream',f'{{{NS}}}edSignature':signature})
            ET.ElementTree(rss).write(path,encoding='utf-8',xml_declaration=True)
            run_command([sparkle/'bin/sign_update','--account',ACCOUNT,path])
        def launch(case,commands,feed_path,install=False,tamper=False):
            identifier=f'dev.slate.browser.update-test.{uuid.uuid4().hex}'
            case_root=root/case;case_root.mkdir();staged=case_root/'Slate.app'
            info=stage(staged,identifier)
            if install:
                new=case_root/'new/Slate.app';new.parent.mkdir()
                new_info=stage(new,identifier,'20261031.2')
                archive=web/f'{case}.zip'
                run_command(['/usr/bin/ditto','--norsrc','--noextattr','-c','-k','--keepParent',new,archive])
                feed(feed_path,new_info['CFBundleVersion'],new_info['CFBundleShortVersionString'],archive)
            else:feed(feed_path,info['CFBundleVersion'],info['CFBundleShortVersionString'])
            if tamper:
                feed_path.write_bytes(feed_path.read_bytes().replace(b'Slate Test Updates',b'Untrusted Updates'))
            command_file=case_root/'commands.txt';command_file.write_text('\n'.join(commands)+'\n')
            data=case_root/'data';data.mkdir();(data/'sentinel').write_text('preserved')
            env=dict(os.environ,SLATE_AUTOMATED_INPUT_ONLY='1',SLATE_DATA_DIR=str(data),SLATE_COMMAND_FILE=str(command_file),SLATE_TEST_UPDATE_FEED=f'{base}/{feed_path.name}',SLATE_HEADLESS_UPDATE_TEST='1')
            output=case_root/'run.log'
            try:
                with output.open('wb') as handle:
                    process=subprocess.Popen([str(staged/'Contents/MacOS/Slate')],env=env,stdout=handle,stderr=subprocess.STDOUT)
                    if install:
                        # The first process has already loaded its commands. Relaunch should just quit.
                        deadline=time.monotonic()+25
                        while time.monotonic()<deadline and process.poll() is None:
                            if 'SLATE_UPDATER_CHECK result=update-available' in output.read_text(errors='replace'):
                                command_file.write_text('quit\n');break
                            time.sleep(.1)
                    process.wait(timeout=35)
                log=output.read_text(errors='replace')
                assert process.returncode==0, f'{case}: Slate exit {process.returncode}'
                checks=re.findall(r'SLATE_UPDATER_CHECK .*failures=(\d+)',log)
                assert checks and all(x=='0' for x in checks), f'{case}: failed checks {checks}'
                if install:
                    deadline=time.monotonic()+15
                    while time.monotonic()<deadline:
                        try:
                            if plistlib.loads((staged/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='20261031.2': break
                        except FileNotFoundError:pass
                        time.sleep(.1)
                    else:raise AssertionError('The temporary app was not replaced by Sparkle')
                    assert 'SLATE_UPDATER_FOUND' in log and 'SLATE_UPDATER_INSTALL' in log
                    run_command(['/usr/bin/codesign','--verify','--deep','--strict',staged])
                assert (data/'sentinel').read_text()=='preserved'
                return len(checks)
            finally:
                if output.exists():logs.append(f'\nCASE {case}\n'+output.read_text(errors='replace'))
                # Only terminate helper/app processes inside this case's temporary directory.
                import signal
                for record in subprocess.check_output(['/bin/ps','-axo','pid=,command='],text=True).splitlines():
                    fields=record.strip().split(None,1)
                    if len(fields)==2 and fields[1].startswith(str(case_root)+os.sep):
                        try:os.kill(int(fields[0]),signal.SIGTERM)
                        except ProcessLookupError:pass
                if 'process' in locals() and process.poll() is None: process.kill();process.wait()
                subprocess.run(['/usr/bin/defaults','delete',identifier],capture_output=True)
        try:
            commands=['checkupdater ready 0 0','updaterprefs 1 1','checkupdater ready 1 1','updaterprefs 0 1','checkupdater ready 0 0',
                      'updaterprefs 1 0','checkupdater ready 1 0','updatercheck','sleep 1','checkupdater up-to-date 1 0']
            if screenshot:commands += [f'snapsettings {screenshot}']
            commands += ['quit']
            checks=launch('current',commands,web/'current.xml')
            checks+=launch('tampered',['updatercheck','sleep 1','checkupdater check-failed 0 0','quit'],web/'tampered.xml',tamper=True)
            commands=['updatercheck','sleep 1','checkupdater update-available 0 0']
            for _ in range(10):commands += ['updaterinstall','sleep 0.5']
            commands += ['quit']
            checks+=launch('install',commands,web/'install.xml',install=True)
        finally:
            server.shutdown();server.server_close();log_path.write_text('\n'.join(logs))
        print(f'{checks} native updater checks passed; signed update installed into a temporary app copy and data remained intact.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--sparkle',type=Path,default=Path(__file__).resolve().parents[1]/'third_party/Sparkle-2.10.1')
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--screenshot',type=Path)
    args=parser.parse_args()
    verify(args.app.resolve(),args.sparkle.resolve(),args.log.resolve(),args.screenshot.resolve() if args.screenshot else None)
