#!/usr/bin/env python3
"""The privacy manifest (docs/admin/privacy.md) is complete.

    check_outbound.py [<repository root>]

Every external endpoint and periodic trigger in product code belongs to a row that names the file in its Code column
and, for an endpoint, its host. Only URL literals and the usual periodic timers are found: review covers the rest.
kernel/src is skipped: its lints forbid sockets and clocks, so its URLs are identifiers such as XMP namespaces. So are a
package's lib/testing.dart and lib/src/testing/, for tests only. So is the server's gainmap.rs, which opens no
connection: its URLs are the XMP namespaces of Ultra HDR and Apple gain maps.
Every connection has a self-hosted alternative; a run-time connection or a task on a timer also a kill switch, a
timeout and a far-future-date test, and the five paths design 06 §10 names have a row. A run-time connection is off by
default, and the master switch `outbound: none` turns every one off (ADR-0058). Code is files of this repository, or
'planned …' until then.
"""
import re
import subprocess
import sys
from pathlib import Path

MANIFEST = "docs/admin/privacy.md"
RUN, BUILD, TIMER = "At run time", "When building from source", "On a timer"
NAMED = ("update check", "map tiles", "model download", "geocoding pack", "push relay")
PRODUCT = re.compile(r"^(app|server|kernel|viewer)/.+\.(dart|rs|ts|js|mjs|kt|java|swift|mm?|c|cc|cpp|h|html|json)$")
NOT_PRODUCT = re.compile(r"/(test|tests|integration_test|test_driver|benches|tool|gen|testvectors|drift_schemas|proto)/"
                         r"|^kernel/src/|^server/crates/photolib-media/src/gainmap\.rs$|/lib/testing\.dart$|/lib/src/testing/|\.g\.dart$|\.pb\w*\.dart$|package-lock\.json$")
URL = re.compile(r"https?://([^/\\\s\"'`<>)$:]+)")
LOCAL = re.compile(r"(localhost|127(\.\d+){3}|\[::1\]|(.+\.)?(example(\.com|\.org|\.net)?|test|invalid)|\{\w*\})")
COMMENT = re.compile(r"(^|\s)(//|#|/\*|<!--)|^\s*\*")
PERIODIC = re.compile(r"Timer\.periodic|time::interval|setInterval\(")
EMPTY = ("", "-", "—")


def tables(text):
    """Rows of the table under each '## ' heading, as {column: cell}."""
    sections, heading, header = {}, None, None
    for line in text.splitlines():
        if line.startswith("## "):
            heading, header = line[3:].strip(), None
        elif line.startswith("|") and heading:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if header is None:
                header = [cell.lower() for cell in cells]
            elif not set(line) <= set("|-: "):
                sections.setdefault(heading, []).append(dict(zip(header, cells)))
    return sections


def findings(root):
    """(file, what, host or None) for each external endpoint and periodic trigger in product code."""
    files = subprocess.run(["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard"],
                           capture_output=True, text=True, check=True).stdout.split()
    for name in files:
        if not PRODUCT.match(name) or NOT_PRODUCT.search(name) or not (root / name).is_file():
            continue
        for line in (root / name).read_text(errors="replace").splitlines():
            for url in URL.finditer(line):
                if not COMMENT.search(line[:url.start()]) and not LOCAL.fullmatch(url.group(1)):
                    yield name, f"contacts {url.group(1)}", url.group(1).lower()
            if PERIODIC.search(line) and not COMMENT.search(line[:PERIODIC.search(line).start()]):
                yield name, "has a periodic trigger", None


def main(root):
    if not (root / MANIFEST).is_file():
        print(f"FAIL: {MANIFEST} is missing", file=sys.stderr)
        return 1
    problems = []
    sections = tables((root / MANIFEST).read_text())
    rows = {section: sections.get(section, []) for section in (RUN, BUILD, TIMER)}
    required = {RUN: ("contacts", "when", "kill switch", "timeout", "self-hosted alternative", "far-future test", "code"),
                BUILD: ("contacts", "self-hosted alternative"),
                TIMER: ("when", "kill switch", "timeout", "far-future test", "code")}
    listed = {}
    for section, entries in rows.items():
        for row in entries:
            name = next(iter(row.values()), "?")
            problems += [f"{name}: no {column}" for column in required[section] if row.get(column, "") in EMPTY]
            code = re.findall(r"`([^`]+)`", row.get("code", ""))
            for path in code:
                listed[path] = listed.get(path, "") + " ".join(row.values()).lower()
            if section == BUILD and row.get("code") in EMPTY:
                continue
            if not code and not row.get("code", "").lower().startswith("planned"):
                problems.append(f"{name}: code must be files of this repository, or 'planned …' until then")
            problems += [f"{name}: {path} does not exist" for path in code if not (root / path).exists()]
            test = re.fullmatch(r'`([^`]+)`: "([^"]+)"', row.get("far-future test", ""))
            if section != BUILD and code:
                if not test or not (root / test[1]).is_file():
                    problems.append(f'{name}: the far-future test must be `<file>`: "<test name>" of an existing file')
                elif test[2] not in (root / test[1]).read_text():
                    problems.append(f'{name}: no test "{test[2]}" in {test[1]}')
    problems += [f"{row.get('connection', '?')}: the kill switch must be off by default" for row in rows[RUN]
                 if row.get("kill switch", "") not in EMPTY and "off by default" not in row["kill switch"]]
    if "`outbound: none`" not in (root / MANIFEST).read_text():
        problems.append(f"{MANIFEST}: no master switch `outbound: none`")
    named = " ".join(row.get("connection", "").lower() for row in rows[RUN])
    problems += [f"{MANIFEST}: no row for the {path}" for path in NAMED if path not in named]
    problems += [f"{path} {what}, but no row of {MANIFEST} lists it" for path, what, host in findings(root)
                 if path not in listed or host and host not in listed[path]]
    for problem in problems:
        print(f"FAIL: {problem}", file=sys.stderr)
    if not problems:
        print(f"ok: {MANIFEST} lists every outbound and periodic path with its controls")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])))
