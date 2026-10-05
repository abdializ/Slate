#!/usr/bin/env python3
"""Compatibility entry point for the isolated whole-browser tab benchmark.

See docs/BENCHMARKS.md. Requires --slate-app and --output; never deletes
an existing browser profile or a fixed user folder.
"""
from benchmark_tabs import main

if __name__ == '__main__':
    main()
