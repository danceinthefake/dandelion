#!/usr/bin/env python3
"""Tidies `mix test --trace` output: ExUnit prints each test name twice (when
it starts and when it ends) and Docker's output lands in the middle of the
lines. Keeps one line per test, "  test NAME (TIME)", and everything else as it
was. usage: clean_trace.py < raw > clean"""
import re
import sys

done = re.compile(r".*\* test (.+?) \((\d+(?:\.\d+)?)ms\)")
for line in sys.stdin:
    line = line.rstrip("\n")
    m = done.search(line)
    if m:
        ms = float(m.group(2))
        t = f"{ms/1000:.1f} s" if ms >= 1000 else f"{ms:.0f} ms"
        print(f"  test {m.group(1)} ({t})")
    elif re.search(r"\* test .*\[L#\d+\]", line) or re.match(r"\s*(Container|Network|Volume) ", line):
        continue
    else:
        print(line)
