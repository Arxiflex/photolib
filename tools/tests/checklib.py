"""Shared by the check_*.py helpers: `check` prints "ok: ..." or "FAIL: ..."; `finish` sets the exit status."""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
failures = 0


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        return handle.read()


def check(condition, description, failure=None):
    global failures
    if condition:
        print(f"ok: {description}")
    else:
        failures += 1
        print(f"FAIL: {failure or description}", file=sys.stderr)
    return bool(condition)


def fail(message):
    check(False, message)


def finish():
    if failures:
        print(f"{failures} assertion(s) failed", file=sys.stderr)
        sys.exit(1)
