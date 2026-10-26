#!/usr/bin/env python3
"""The Flutter upgrade gate (design 10 §12): a change to the pinned version in app/.fvmrc needs every gate of
.github/PULL_REQUEST_TEMPLATE/flutter-upgrade.md ticked in the pull request description.

    PR_BODY=<description> flutter_upgrade_gate.py <base> <head>

Run from the repository root. Only what the pull request itself changes since it left <base> counts. Exit 0 when the
pin is unchanged, newly added or every gate is ticked, 1 when a gate is missing or the pin removed, 2 on a usage
error.
"""
import json
import os
import re
import subprocess
import sys

PIN = "app/.fvmrc"
TEMPLATE = ".github/PULL_REQUEST_TEMPLATE/flutter-upgrade.md"


def pinned(revision):
    shown = subprocess.run(["git", "show", f"{revision}:{PIN}"], capture_output=True, text=True)
    return json.loads(shown.stdout)["flutter"] if shown.returncode == 0 else None


def main(base, head):
    fork = subprocess.run(["git", "merge-base", base, head], capture_output=True, text=True, check=True).stdout.strip()
    before, after = pinned(fork), pinned(head)
    if before == after:
        print(f"Flutter pin unchanged ({after}): no upgrade gates apply")
        return 0
    if after is None:
        print(f"{PIN} was removed: Flutter must stay pinned", file=sys.stderr)
        return 1
    if before is None:
        print(f"{PIN} pins Flutter {after} for the first time: no upgrade gates apply")
        return 0
    with open(TEMPLATE, encoding="utf-8") as template:
        gates = re.findall(r"^- \[ \] (.+)$", template.read(), re.M)
    body = os.environ.get("PR_BODY", "")
    missing = [gate for gate in gates if not re.search(rf"^\s*- \[[xX]\] {re.escape(gate)}\s*$", body, re.M)]
    if missing:
        print(f"{PIN} moves Flutter {before} -> {after}; tick these gates from {TEMPLATE} in the description:",
              file=sys.stderr)
        print("\n".join(f"  - {gate}" for gate in missing), file=sys.stderr)
        return 1
    print(f"Flutter {before} -> {after}: every upgrade gate is ticked")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(*sys.argv[1:]))
