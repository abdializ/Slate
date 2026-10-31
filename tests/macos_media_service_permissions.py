#!/usr/bin/env python3
"""Check real macOS service access in two disposable signed, sandboxed apps.

No browser, video window, page account, signing key or network is used. The old
policy must fail PiP lookup; the release policy must reach the real PiP service.
"""
from pathlib import Path
import json, plistlib, subprocess, sys, tempfile

probe, source, artifacts = map(Path,sys.argv[1:4])
fixed=plistlib.loads((source/'platform/macos/Slate.entitlements').read_bytes())
key='com.apple.security.temporary-exception.mach-lookup.global-name'
needed={'com.apple.PIPAgent','dev.slate.browser-spki','dev.slate.browser-spks'}
assert set(fixed.get(key,[]))==needed
old=dict(fixed);old.pop(key,None)
results={}
with tempfile.TemporaryDirectory(prefix='slate-media-services-',dir='/private/tmp') as tmp:
 for label,entitlements in [('before',old),('after',fixed)]:
  app=Path(tmp)/(label+'.app');binary=app/'Contents/MacOS';binary.mkdir(parents=True)
  identifier='dev.slate.tests.media-services.'+label
  (app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier,CFBundleExecutable='probe',CFBundlePackageType='APPL',LSBackgroundOnly=True)))
  target=binary/'probe';target.write_bytes(probe.read_bytes());target.chmod(0o755)
  ent=Path(tmp)/(label+'.entitlements');ent.write_bytes(plistlib.dumps(entitlements))
  subprocess.run(['/usr/bin/codesign','--force','--sign','-','--identifier',identifier,'--entitlements',str(ent),str(app)],check=True,capture_output=True)
  run=subprocess.run([str(target)],capture_output=True,text=True,check=True,timeout=15)
  results[label]=json.loads(run.stdout)
  assert results[label]['sandboxed']==1, results
  assert results[label]['unrelated']==1, results
assert all(results['before'][name]==1 for name in ['pip','spki','spks']), results
assert results['before']['pip_bootstrap']!=0, results
assert all(results['after'][name]==0 for name in ['pip','spki','spks']), results
assert results['after']['pip_bootstrap']==0, results
artifacts.mkdir(parents=True,exist_ok=True)
(artifacts/'permissions.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS: old sandbox blocks PiP; corrected signed sandbox reaches PiP and permits its own updater channels; unrelated services remain blocked.')
