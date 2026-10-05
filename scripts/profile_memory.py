#!/usr/bin/env python3
import os
import sys
import time
import json
import socket
import shutil
import tempfile
import threading
import subprocess
from http.server import HTTPServer, SimpleHTTPRequestHandler

SLATE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
APP_BINARY = os.path.join(SLATE_ROOT, 'build', 'platform', 'macos', 'Slate.app', 'Contents', 'MacOS', 'Slate')
FIXTURES_DIR = os.path.join(SLATE_ROOT, 'tests', 'fixtures')

class QuietServer(HTTPServer):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

class CustomHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FIXTURES_DIR, **kwargs)
    def log_message(self, format, *args):
        pass

def get_free_port():
    s = socket.socket()
    s.bind(('', 0))
    p = s.getsockname()[1]
    s.close()
    return p

def get_slate_webkit_pids(slate_pid):
    """Finds all WebKit helper processes belonging to Slate via container files in lsof."""
    try:
        pids = subprocess.check_output(['pgrep', '-f', 'WebKit']).decode().split()
    except Exception:
        return []
    slate_pids = []
    for p in pids:
        try:
            out = subprocess.check_output(['lsof', '-p', p], stderr=subprocess.DEVNULL).decode()
            if 'dev.slate.browser' in out:
                slate_pids.append(int(p))
        except Exception:
            pass
    return slate_pids

def sample_footprint(pid):
    """Returns physical footprint in bytes using macOS /usr/bin/footprint."""
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        tmp_path = tf.name
    try:
        res = subprocess.run(['/usr/bin/footprint', '-p', str(pid), '-j', tmp_path],
                             capture_output=True, text=True, timeout=5)
        if res.returncode == 0 and os.path.exists(tmp_path):
            with open(tmp_path, 'r') as f:
                data = json.load(f)
            procs = data.get('processes', [])
            if procs:
                return procs[0].get('footprint', 0)
        return 0
    except Exception:
        return 0
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

def sample_rss(pid):
    """Returns Resident Set Size in bytes via ps."""
    try:
        out = subprocess.check_output(['ps', '-o', 'rss=', '-p', str(pid)]).decode().strip()
        return int(out) * 1024
    except Exception:
        return 0

def measure_memory_state(main_pid):
    wk_pids = get_slate_webkit_pids(main_pid)

    main_footprint = sample_footprint(main_pid)
    main_rss = sample_rss(main_pid)

    wk_footprint_total = 0
    wk_rss_total = 0
    wk_details = {}

    for p in wk_pids:
        fp = sample_footprint(p)
        rss = sample_rss(p)
        try:
            comm = subprocess.check_output(['ps', '-p', str(p), '-o', 'comm=']).decode().strip()
            name = os.path.basename(comm)
        except Exception:
            name = f"proc_{p}"
        wk_details[p] = {"name": name, "footprint_mb": round(fp / (1024 * 1024), 2), "rss_mb": round(rss / (1024 * 1024), 2)}
        wk_footprint_total += fp
        wk_rss_total += rss

    return {
        "main_footprint_mb": round(main_footprint / (1024 * 1024), 2),
        "wk_footprint_mb": round(wk_footprint_total / (1024 * 1024), 2),
        "total_footprint_mb": round((main_footprint + wk_footprint_total) / (1024 * 1024), 2),
        "main_rss_mb": round(main_rss / (1024 * 1024), 2),
        "wk_rss_mb": round(wk_rss_total / (1024 * 1024), 2),
        "total_rss_mb": round((main_rss + wk_rss_total) / (1024 * 1024), 2),
        "webkit_pids": wk_pids,
        "webkit_details": wk_details
    }

def main():
    print("=" * 84)
    print("SLATE BROWSER — CONTROLLED MEMORY PROFILING (/usr/bin/footprint)")
    print("=" * 84)

    port = get_free_port()
    server = QuietServer(('127.0.0.1', port), CustomHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    print(f"[*] Local fixture HTTP server started on http://127.0.0.1:{port}/")

    test_data_dir = os.path.expanduser("~/Downloads/slate_profile_test_dir")
    shutil.rmtree(test_data_dir, ignore_errors=True)
    os.makedirs(test_data_dir, exist_ok=True)
    cmd_file = os.path.join(test_data_dir, "commands.txt")
    with open(cmd_file, "w") as f:
        f.write("# Memory profiling commands\n")

    env = os.environ.copy()
    env["SLATE_DATA_DIR"] = test_data_dir
    env["SLATE_COMMAND_FILE"] = cmd_file

    def send_cmd(cmd, delay=0.35):
        with open(cmd_file, "a") as f:
            f.write(cmd + "\n")
        time.sleep(delay)

    print("[*] Launching Slate...")
    proc = subprocess.Popen([APP_BINARY], env=env, stderr=subprocess.PIPE, text=True)
    slate_pid = proc.pid
    print(f"[*] Slate main process PID: {slate_pid}")

    results = []

    try:
        # Condition 1: Idle startup (about:blank)
        print("\n[1/7] Condition 1: Idle Startup (about:blank)...")
        time.sleep(2.5)
        m1 = measure_memory_state(slate_pid)
        m1["condition"] = "1. Idle Startup (about:blank)"
        results.append(m1)
        print(f"      -> Physical Footprint: Main={m1['main_footprint_mb']}MB, WebKit={m1['wk_footprint_mb']}MB, Total={m1['total_footprint_mb']}MB (RSS: Main={m1['main_rss_mb']}MB, Total={m1['total_rss_mb']}MB)")

        # Condition 2: 1 tab (single website)
        print("\n[2/7] Condition 2: 1 Tab (single website fixture)...")
        send_cmd(f"go http://127.0.0.1:{port}/security_bridge_top.html", delay=2.5)
        m2 = measure_memory_state(slate_pid)
        m2["condition"] = "2. 1 Tab (single website)"
        results.append(m2)
        print(f"      -> Physical Footprint: Main={m2['main_footprint_mb']}MB, WebKit={m2['wk_footprint_mb']}MB, Total={m2['total_footprint_mb']}MB (RSS: Main={m2['main_rss_mb']}MB, Total={m2['total_rss_mb']}MB)")
        print(f"      -> Active WebKit processes: {m2['webkit_details']}")

        # Condition 3: 5 tabs (same website)
        print("\n[3/7] Condition 3: 5 Tabs (same website)...")
        for i in range(4):
            send_cmd("newtab", delay=0.4)
            send_cmd(f"go http://127.0.0.1:{port}/security_bridge_top.html", delay=1.0)
        time.sleep(2.0)
        m3 = measure_memory_state(slate_pid)
        m3["condition"] = "3. 5 Tabs (same website)"
        results.append(m3)
        print(f"      -> Physical Footprint: Main={m3['main_footprint_mb']}MB, WebKit={m3['wk_footprint_mb']}MB, Total={m3['total_footprint_mb']}MB (RSS: Main={m3['main_rss_mb']}MB, Total={m3['total_rss_mb']}MB)")

        # Condition 4: 1 active video (local video / YouTube)
        print("\n[4/7] Condition 4: 1 Active Video...")
        # Close tabs down to 1 tab
        for _ in range(4):
            send_cmd("closetab", delay=0.3)
        time.sleep(1.0)
        send_cmd(f"go http://127.0.0.1:{port}/mse.html", delay=1.5)
        send_cmd("playvideo", delay=2.5)
        m4 = measure_memory_state(slate_pid)
        m4["condition"] = "4. 1 Active Video (MSE Playback)"
        results.append(m4)
        print(f"      -> Physical Footprint: Main={m4['main_footprint_mb']}MB, WebKit={m4['wk_footprint_mb']}MB, Total={m4['total_footprint_mb']}MB (RSS: Main={m4['main_rss_mb']}MB, Total={m4['total_rss_mb']}MB)")

        # Condition 5: 5 tabs with 1 active video
        print("\n[5/7] Condition 5: 5 Tabs with 1 Active Video...")
        for _ in range(4):
            send_cmd("newtab", delay=0.4)
            send_cmd(f"go http://127.0.0.1:{port}/security_bridge_top.html", delay=0.8)
        time.sleep(2.5)
        m5 = measure_memory_state(slate_pid)
        m5["condition"] = "5. 5 Tabs with 1 Active Video"
        results.append(m5)
        print(f"      -> Physical Footprint: Main={m5['main_footprint_mb']}MB, WebKit={m5['wk_footprint_mb']}MB, Total={m5['total_footprint_mb']}MB (RSS: Main={m5['main_rss_mb']}MB, Total={m5['total_rss_mb']}MB)")

        # Condition 6: Memory after closing all tabs
        print("\n[6/7] Condition 6: Memory After Closing All Tabs...")
        for _ in range(5):
            send_cmd("closetab", delay=0.3)
        time.sleep(2.0)
        m6 = measure_memory_state(slate_pid)
        m6["condition"] = "6. After Closing All Tabs"
        results.append(m6)
        print(f"      -> Physical Footprint: Main={m6['main_footprint_mb']}MB, WebKit={m6['wk_footprint_mb']}MB, Total={m6['total_footprint_mb']}MB (RSS: Main={m6['main_rss_mb']}MB, Total={m6['total_rss_mb']}MB)")

        # Condition 7: Memory after idle (stabilization)
        print("\n[7/7] Condition 7: Memory After Idle (stabilization)...")
        print("      (Waiting 8s for memory stabilization)...")
        time.sleep(8.0)
        m7 = measure_memory_state(slate_pid)
        m7["condition"] = "7. After Idle (stabilization)"
        results.append(m7)
        print(f"      -> Physical Footprint: Main={m7['main_footprint_mb']}MB, WebKit={m7['wk_footprint_mb']}MB, Total={m7['total_footprint_mb']}MB (RSS: Main={m7['main_rss_mb']}MB, Total={m7['total_rss_mb']}MB)")

    finally:
        print("\n[*] Terminating Slate...")
        send_cmd("quit", delay=0.5)
        time.sleep(1.0)
        try:
            proc.terminate()
            proc.wait(timeout=2.0)
        except Exception:
            proc.kill()
        server.shutdown()
        shutil.rmtree(test_data_dir, ignore_errors=True)

    print("\n" + "=" * 90)
    print("EMPIRICAL FOOTPRINT PROFILING RESULTS SUMMARY (macOS /usr/bin/footprint)")
    print("=" * 90)
    fmt = "{:<32} | {:<12} | {:<12} | {:<12} | {:<12}"
    print(fmt.format("Condition", "Main Footprint", "WebKit FP", "Total FP", "Total RSS"))
    print("-" * 90)
    for r in results:
        print(fmt.format(
            r["condition"],
            f"{r['main_footprint_mb']} MB",
            f"{r['wk_footprint_mb']} MB",
            f"{r['total_footprint_mb']} MB",
            f"{r['total_rss_mb']} MB"
        ))
    print("=" * 90)

    out_file = os.path.join(SLATE_ROOT, "build", "memory_profile_footprint.json")
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"[*] Full profile saved to: {out_file}")

if __name__ == "__main__":
    main()
