#!/usr/bin/env python3
"""Runs `cargo deny check advisories` in a Cargo workspace, its output passed through, and ends with a
`WARN advisories: <id> <crate> <version> in <workspace>` line per finding instead of failing: a RustSec advisory is
published against a locked crate whatever a branch changed, so it is reviewed from the gate's log, never a failed
merge (owner, 2026-10-24, ADR-0058). A failed run that names no crate (no database, a bad configuration) still fails.

  python3 tools/advisories.py cargo deny --locked --config deny.toml check advisories
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main(command):
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    found = []  # [level, id, crate and version] of each diagnostic
    for line in proc.stdout:
        sys.stdout.write(line)
        if head := re.match(r"(error|warning)\[([\w-]+)\]", line):
            found.append([head[1], head[2], None])
        elif found and (crate := re.match(r"\s*\d+ │ (\S+ \d+\.\d+\.\d+\S*) \w+\+\S+$", line)) and not found[-1][2]:
            found[-1][2] = crate[1]
        elif found and (advisory := re.match(r"\s*├ ID: (\S+)", line)):
            found[-1][1] = advisory[1]
    status = proc.wait()
    findings = [f for f in found if f[2]]
    workspace = os.path.relpath(os.getcwd(), ROOT)
    for _, advisory, crate in findings:
        print(f"WARN advisories: {advisory} {crate} in {workspace}")
    return 0 if findings and all(f[2] for f in found if f[0] == "error") else status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
