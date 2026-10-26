#!/usr/bin/env python3
"""Runs a Rust test command with RUST_BACKTRACE=1, its output passed through, and fails when a test passed although a
thread it did not join panicked (docs/dev/lint.md). Have it print a passing test's output (cargo test's --show-output,
cargo nextest's --success-output immediate): a panic there on the test's own thread is one the test caught on purpose,
on any other thread one that nobody saw.

  python3 tools/lint/panics.py cargo nextest run --locked --success-output immediate
  python3 tools/lint/panics.py cargo test --locked -- --show-output
"""

import os
import re
import subprocess
import sys


def main(command):
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
                            env=dict(os.environ, RUST_BACKTRACE="1"))
    test, lost = None, []
    for line in proc.stdout:
        sys.stdout.write(line)
        # cargo test's section of a test's output, or nextest's line above it: PASS [ 0.01s] (1/9) <binary> <test>
        if section := re.match(r"---- (.+) stdout ----$|\s+[A-Z][A-Z0-9 /-]* \[[^]]*\] (?:\(\s*\d+/\d+\) )?\S+ (\S+)$",
                               line):
            test = section[1] or section[2]
        elif line.startswith(("successes:", "failures:", "test result:", "     Running ", "   Doc-tests ", "────")):
            test = None
        # nextest indents what a test printed
        elif (panic := re.match(r"\s*thread '([^']*)'(?: \(\d+\))? panicked at (\S+?):?$", line)) and panic[1] != test:
            lost.append(f"{test or 'outside any test'}: thread '{panic[1]}' panicked at {panic[2]}")
    status = proc.wait()
    if status == 0 and lost:
        print("panics.py: these threads panicked, but no test joined them and failed:", *lost, sep="\n  ")
        return 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
