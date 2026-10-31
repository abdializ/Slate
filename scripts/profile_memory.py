#!/usr/bin/env python3
# File purpose: Provides a compatibility command that invokes the current isolated tab benchmark.

"""Compatibility entry point for the isolated whole-browser tab benchmark.

See docs/BENCHMARKS.md. Requires --slate-app and --output; never deletes
an existing browser profile or a fixed user folder.
"""
from benchmark_tabs import main

# Slate note: Forward command-line execution to benchmark_tabs.main instead of maintaining a second
# measurement implementation.
if __name__ == '__main__':
    main()
