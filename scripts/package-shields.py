#!/usr/bin/env python3
import sys, os

def main():
    if len(sys.argv) < 3:
        sys.exit(1)
    src_dir = sys.argv[1]
    dst_dir = sys.argv[2]
    os.makedirs(dst_dir, exist_ok=True)

    for fname in ["slate-network.txt", "compat.txt", "NOTICE.txt"]:
        src = os.path.join(src_dir, fname)
        if os.path.exists(src):
            with open(src, "r", encoding="utf-8", errors="ignore") as f, \
                 open(os.path.join(dst_dir, fname), "w", encoding="utf-8") as out:
                out.write(f.read())

    for fname in ["easylist-network.txt", "easyprivacy-network.txt"]:
        src = os.path.join(src_dir, fname)
        if not os.path.exists(src):
            continue
        with open(src, "r", encoding="utf-8", errors="ignore") as f:
            rules = [line for line in f if line.startswith(("||", "@@||"))][:25000]
        with open(os.path.join(dst_dir, fname), "w", encoding="utf-8") as out:
            out.writelines(rules)

if __name__ == "__main__":
    main()
