#!/usr/bin/env python3
"""Controlled macOS tab benchmark; never uses an existing browser profile.

Requires a Release Slate build with SLATE_ENABLE_VERIFY=ON, Google Chrome,
and permission to inspect your own processes with /usr/bin/footprint.
See docs/BENCHMARKS.md for the workload and limits. Output excludes paths,
PIDs, account names, profile data, and raw process/memory-inspection logs.
"""
import argparse
import ctypes
import datetime
import hashlib
import http.server
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import statistics
import subprocess
import tempfile
import threading
import time
import uuid

MIB = 1024 * 1024
FIXTURE = b'''<!doctype html><meta charset="utf-8"><title>Tab benchmark</title>
<style>body{font:16px system-ui;margin:24px}article{padding:4px;border-bottom:1px solid #ddd}</style>
<h1>Local tab workload</h1><input value="original"><main></main>
<script>
const parts=location.pathname.split('/'),label=parts[2],tab=Number(parts[3]);
window.benchmarkHeap=new Uint8Array(2*1024*1024);
window.benchmarkHeap.fill(37);
const fragment=document.createDocumentFragment();
for(let i=0;i<1500;i++){
 const row=document.createElement('article');
 row.textContent=`Tab ${tab}, row ${i}: a repeatable local document.`;
 fragment.append(row);
}
document.querySelector('main').append(fragment);
window.benchmarkState=`state-${tab}`;
document.querySelector('input').value=`edited-${tab}`;
void document.body.offsetHeight;
fetch(`/ready/${label}/${tab}`,{method:'POST',body:JSON.stringify({page_ms:performance.now()})});
</script>'''


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def processes():
    # Executable names only: never capture another app's URL-bearing argv.
    result = {}
    for line in run(['/bin/ps', '-axo', 'pid=,ppid=,comm=']).splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) == 3:
            result[int(fields[0])] = (int(fields[1]), fields[2])
    return result


LIBPROC = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
LIBPROC.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                               ctypes.c_void_p, ctypes.c_int]
LIBPROC.proc_pidinfo.restype = ctypes.c_int


def coalition(pid):
    # Apple XNU PROC_PIDCOALITIONINFO=20: two IDs and three reserved uint64s.
    info = (ctypes.c_uint64 * 5)()
    size = ctypes.sizeof(info)
    if LIBPROC.proc_pidinfo(pid, 20, 0, info, size) != size:
        return None
    return tuple(info[:2])


def owned_pids(main, browser, require_helpers=True):
    table = processes()
    if main not in table:
        raise RuntimeError('The isolated browser exited before measurement')
    owned = {main}
    while True:
        children = {pid for pid, (parent, _) in table.items() if parent in owned}
        if children <= owned:
            break
        owned |= children
    group = coalition(main)
    if not group or not all(group):
        if require_helpers:
            raise RuntimeError('Cannot attribute helpers to the test browser')
    else:
        chrome_root = str(Path(table[main][1]).parents[2]) + '/'
        owned |= {pid for pid, (_, executable) in table.items()
                  if (('com.apple.WebKit.' in executable if browser == 'Slate'
                       else executable.startswith(chrome_root))) and coalition(pid) == group}
    if require_helpers:
        if browser == 'Slate' and not any('com.apple.WebKit.WebContent' in table[pid][1] for pid in owned):
            raise RuntimeError('No attributed WebKit content process; refusing main-only data')
        if browser == 'Chrome' and not any('Google Chrome Helper' in table[pid][1] for pid in owned):
            raise RuntimeError('No attributed Chrome helper; refusing main-only data')
    return sorted(owned)


def pressure():
    return int(run(['/usr/sbin/sysctl', '-n', 'kern.memorystatus_vm_pressure_level']))


def footprint(main, browser, scratch):
    targets = owned_pids(main, browser)
    raw = scratch / 'footprint.json'
    command = ['/usr/bin/footprint', '-f', 'bytes', '-j', str(raw)]
    for pid in targets:
        command += ['-p', str(pid)]
    run(command, timeout=30)
    data = json.loads(raw.read_text())
    raw.unlink()
    found = {item['pid'] for item in data.get('processes', [])}
    if found != set(targets):
        raise RuntimeError('Footprint target set changed during sampling')
    if data.get('errors'):
        raise RuntimeError('Footprint reported inspection errors')
    if data.get('bytes per unit') != 1:
        raise RuntimeError('Unexpected footprint units')
    total = data['total footprint']
    if total <= 0:
        raise RuntimeError('Invalid footprint sample')
    return {'footprint_mib': round(total / MIB, 3), 'process_count': len(targets),
            'pressure_level': pressure()}


def samples(main, browser, scratch, count):
    result = []
    for _ in range(count):
        for attempt in range(1, 4):
            try:
                sample = footprint(main, browser, scratch)
                sample['sampling_attempts'] = attempt
                result.append(sample)
                break
            except RuntimeError as error:
                print(f'  Rejected sample: {error}; attempt {attempt}/3', flush=True)
                if attempt == 3:
                    raise
                time.sleep(1)
        time.sleep(1)
    print(f"  {browser}: {statistics.median(s['footprint_mib'] for s in result):.1f} MiB", flush=True)
    return result


class Workload:
    def __init__(self):
        self.requests = {}
        self.ready = {}
        self.lock = threading.Lock()
        workload = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                match = re.fullmatch(r'/page/([a-z0-9-]+)/(\d+)', self.path)
                if not match:
                    self.send_response(404)
                    self.end_headers()
                    return
                key = (match[1], int(match[2]))
                with workload.lock:
                    workload.requests.setdefault(key, time.monotonic())
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('Content-Length', str(len(FIXTURE)))
                self.end_headers()
                self.wfile.write(FIXTURE)

            def do_POST(self):
                match = re.fullmatch(r'/ready/([a-z0-9-]+)/(\d+)', self.path)
                if not match:
                    self.send_response(404)
                    self.end_headers()
                    return
                payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                key = (match[1], int(match[2]))
                with workload.lock:
                    workload.ready[key] = {'request_to_ready_ms': round(
                        (time.monotonic() - workload.requests[key]) * 1000, 3),
                        'page_reported_ms': round(payload['page_ms'], 3),
                        'ready_at': time.monotonic()}
                self.send_response(204)
                self.end_headers()

        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def url(self, label, tab):
        return f'http://127.0.0.1:{self.server.server_port}/page/{label}/{tab}'

    def count(self, label):
        with self.lock:
            return sum(key[0] == label for key in self.ready)

    def wait(self, label, count, timeout=45):
        wait_for(lambda: self.count(label) == count, timeout)

    def durations(self, label):
        with self.lock:
            return [dict(tab=tab, **{k: v for k, v in value.items() if k != 'ready_at'})
                    for (name, tab), value in sorted(self.ready.items()) if name == label]

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def wait_for(predicate, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise RuntimeError('Benchmark condition timed out; no result published')


def stop(main, browser):
    try:
        owned = owned_pids(main, browser, require_helpers=False)
    except RuntimeError:
        # Main might already have quit cleanly; never fall back to killing by name.
        return
    os.kill(main, signal.SIGTERM)
    for _ in range(50):
        alive = processes()
        if main not in alive:
            break
        time.sleep(0.1)
    for pid in reversed(owned):
        if pid in processes():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def slate_trial(app, workload, scratch, repeat, args):
    label = f'slate-{repeat}'
    root = scratch / label
    root.mkdir()
    data = root / 'data'
    data.mkdir()
    session = {'version': 1, 'tabs': [
        {'id': str(i), 'url': workload.url(label, i), 'title': f'Fixture {i}',
         'selected': i == 1, 'protected': False} for i in range(1, args.tabs + 1)]}
    (data / 'session.json').write_text(json.dumps(session))
    commands = ['waitsignal lazy-measured']
    for i in range(2, args.tabs + 1):
        commands += [f'select {i}', 'sleep 0.4']
    commands += ["exec 'BENCHMARK_STAGE_LOADED'", 'waitsignal loaded-measured', 'select 1',
                 'splitright 2', 'select 3']
    for _ in range(10):
        commands += ['checkswitch 1', 'checkswitch 3', 'checkswitch 2']
    for i in [1, 2]:
        commands += [f'select {i}',
                     f"exec (()=>{{if(window.benchmarkState!=='state-{i}'||document.querySelector('input').value!=='edited-{i}')throw Error('BENCHMARK_STATE_LOST');return 'BENCHMARK_STATE_OK_{i}'}})()"]
    commands += ["exec 'BENCHMARK_STAGE_SWITCHED'", 'waitsignal checks-read', 'quit']
    command_file = root / 'commands.txt'
    command_file.write_text('\n'.join(commands) + '\n')
    staged = root / 'Slate Benchmark.app'
    run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(app), str(staged)])
    info_path = staged / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleIdentifier'] = 'dev.slate.benchmark.' + uuid.uuid4().hex
    info_path.write_bytes(plistlib.dumps(info))
    run(['/usr/bin/xattr', '-cr', str(staged)])
    run(['/usr/bin/codesign', '--force', '--sign', '-', str(staged)])
    log_path = root / 'app.log'
    executable = str((staged / 'Contents/MacOS/Slate').resolve())
    started = time.monotonic()
    # LaunchServices gives this isolated app its own resource/jetsam coalition.
    run(['/usr/bin/open', '-n', '-a', str(staged), '--stderr', str(log_path),
         '--env', f'SLATE_DATA_DIR={data}', '--env', f'SLATE_COMMAND_FILE={command_file}'])
    main = wait_for(lambda: next((pid for pid, (_, name) in processes().items()
                                  if name == executable), None))
    try:
        workload.wait(label, 1, 12)
        startup_ms = (time.monotonic() - started) * 1000
        time.sleep(4)
        print(f'  {args.tabs} saved tabs, one loaded:', flush=True)
        lazy = samples(main, 'Slate', root, args.samples)
        if workload.count(label) != 1:
            raise RuntimeError('Lazy condition loaded extra pages during measurement')
        (data / 'verify-signal-lazy-measured').touch()
        workload.wait(label, args.tabs)
        time.sleep(4)
        print(f'  {args.tabs} pages loaded:', flush=True)
        loaded = samples(main, 'Slate', root, args.samples)
        (data / 'verify-signal-loaded-measured').touch()
        wait_for(lambda: log_path.exists() and 'SLATE_JS_RESULT: BENCHMARK_STAGE_SWITCHED' in log_path.read_text(), 45)
        log = log_path.read_text()
        checks = re.findall(r'SLATE_SWITCH_CHECK selected=(\d+) split=(\d+) failures=(\d+) elapsed_ms=([\d.]+)', log)
        if len(checks) != 30 or any(int(row[2]) for row in checks):
            raise RuntimeError('Warm split/single switch visibility or view reuse failed')
        if log.count('SLATE_ENGINE_NAVIGATE') != args.tabs or 'SLATE_JS_ERROR:' in log:
            raise RuntimeError('Unexpected reload or page-state error during switching')
        if not all(f'SLATE_JS_RESULT: BENCHMARK_STATE_OK_{i}' in log for i in [1, 2]):
            raise RuntimeError('Edited form and JavaScript continuity was not confirmed')
        (data / 'verify-signal-checks-read').touch()
        return {'browser': 'Slate', 'repeat': repeat, 'startup_to_fixture_ready_ms': round(startup_ms, 3),
                'lazy_restore': {'logical_tabs': args.tabs, 'loaded_pages': 1, 'samples': lazy},
                'all_loaded': {'logical_tabs': args.tabs, 'loaded_pages': args.tabs, 'samples': loaded},
                'fixture_loads': workload.durations(label), 'warm_switch_ms': [float(row[3]) for row in checks],
                'warm_switch_count': len(checks), 'page_and_form_continuity_passed': True,
                'unexpected_navigation_count': 0}
    finally:
        stop(main, 'Slate')


def chrome_trial(app, workload, scratch, repeat, args):
    label = f'chrome-{repeat}'
    root = scratch / label
    root.mkdir()
    base = [str(app / 'Contents/MacOS/Google Chrome'), f'--user-data-dir={root / "profile"}',
            '--no-first-run', '--no-default-browser-check']
    executable = str((app / 'Contents/MacOS/Google Chrome').resolve())
    existing = {pid for pid, (_, name) in processes().items() if name == executable}
    with (root / 'app.log').open('w') as log:
        started = time.monotonic()
        run(['/usr/bin/open', '-n', '-a', str(app), '--args'] + base[1:] +
            ['--new-window', workload.url(label, 1)])
        def find_main():
            candidates = [pid for pid, (_, name) in processes().items()
                          if name == executable and pid not in existing]
            if len(candidates) > 1:
                raise RuntimeError('Ambiguous Chrome launch; refusing process attribution')
            return candidates[0] if candidates else None
        main = wait_for(find_main)
        try:
            workload.wait(label, 1)
            startup_ms = (time.monotonic() - started) * 1000
            time.sleep(4)
            print('  One page loaded:', flush=True)
            single = samples(main, 'Chrome', root, args.samples)
            subprocess.run(base + [workload.url(label, i) for i in range(2, args.tabs + 1)],
                           stdout=log, stderr=log, check=True, timeout=30)
            workload.wait(label, args.tabs)
            time.sleep(4)
            print(f'  {args.tabs} pages loaded:', flush=True)
            loaded = samples(main, 'Chrome', root, args.samples)
            return {'browser': 'Chrome', 'repeat': repeat, 'startup_to_fixture_ready_ms': round(startup_ms, 3),
                    'single_page': {'logical_tabs': 1, 'loaded_pages': 1, 'samples': single},
                    'all_loaded': {'logical_tabs': args.tabs, 'loaded_pages': args.tabs, 'samples': loaded},
                    'fixture_loads': workload.durations(label)}
        finally:
            stop(main, 'Chrome')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slate-app', required=True, type=Path)
    parser.add_argument('--chrome-app', type=Path, default=Path('/Applications/Google Chrome.app'))
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--tabs', type=int, default=24)
    parser.add_argument('--resume', action='store_true', help='Resume matching completed trials from the partial checkpoint')
    args = parser.parse_args()
    if not 3 <= args.tabs <= 30 or not 1 <= args.samples <= 3 or args.repeats < 1:
        parser.error('Use 3–30 tabs, 1–3 samples, and at least one repeat')
    slate = args.slate_app.resolve()
    chrome = args.chrome_app.resolve()
    chrome_info = plistlib.loads((chrome / 'Contents/Info.plist').read_bytes())
    result = {'schema': 1, 'date': datetime.date.today().isoformat(),
              'hardware': {'cpu': run(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string']),
                           'memory_gib': int(run(['/usr/sbin/sysctl', '-n', 'hw.memsize'])) / (1024 ** 3),
                           'os_version': run(['/usr/bin/sw_vers', '-productVersion'])},
              'chrome_version': chrome_info['CFBundleShortVersionString'],
              'slate_revision': run(['git', 'rev-parse', 'HEAD'], cwd=Path(__file__).resolve().parents[1]),
              'slate_binary_sha256': hashlib.sha256((slate / 'Contents/MacOS/Slate').read_bytes()).hexdigest(),
              'fixture_sha256': hashlib.sha256(FIXTURE).hexdigest(),
              'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'metric': 'footprint group total footprint, bytes converted to MiB',
              'workload': {'origin': 'one loopback HTTP origin, no external page requests',
                           'tabs': args.tabs, 'rows_per_page': 1500, 'touched_array_bytes_per_page': 2 * MIB,
                           'repeats': args.repeats, 'samples_per_condition_per_repeat': args.samples},
              'trials': []}
    checkpoint = args.output.with_suffix('.partial.json')
    if args.resume:
        saved = json.loads(checkpoint.read_text())
        if any(saved.get(key) != result[key] for key in result if key != 'trials'):
            raise RuntimeError('Checkpoint does not match this machine, workload, binary, or runner')
        result['trials'] = saved['trials']
    workload = Workload()
    try:
        with tempfile.TemporaryDirectory(prefix='slate-tab-benchmark-') as scratch:
            for repeat in range(1, args.repeats + 1):
                order = ['Slate', 'Chrome'] if repeat % 2 else ['Chrome', 'Slate']
                for browser in order:
                    if any(t['browser'] == browser and t['repeat'] == repeat for t in result['trials']):
                        continue
                    print(f'Run {repeat}/{args.repeats}: {browser}', flush=True)
                    trial = (slate_trial(slate, workload, Path(scratch), repeat, args)
                             if browser == 'Slate' else chrome_trial(chrome, workload, Path(scratch), repeat, args))
                    result['trials'].append(trial)
                    checkpoint.parent.mkdir(parents=True, exist_ok=True)
                    checkpoint.write_text(json.dumps(result, indent=2) + '\n')
                    time.sleep(3)
    finally:
        workload.close()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    checkpoint.unlink(missing_ok=True)
    print('Benchmark passed; sanitized results written.', flush=True)


if __name__ == '__main__':
    main()
