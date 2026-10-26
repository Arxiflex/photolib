"""Fails on two versions of one line near each other, which a union merge (merge=union in .gitattributes) of two
edits of the same lines leaves behind. python3 tools/tests/check_union.py <file>..."""

import difflib
import re
import sys

# Measured on main's 187 landings (photolib-design#546): no landed AGENTS.md or tools/README.md trips these, and they
# catch 102 of the 128 unions that replaying those landings 1 to 3 behind each other made of them.
WINDOW, RATIO, SHORTEST = 40, 0.7, 30


def near_duplicates(text):
    lines = [(n, re.sub(r"\]\([^)]*\)", "]", line.strip())) for n, line in enumerate(text.splitlines(), 1)]
    lines = [(n, line) for n, line in lines if len(line) >= SHORTEST]
    for i, (n, a) in enumerate(lines):
        for m, b in lines[i + 1 : i + 1 + WINDOW]:
            match = difflib.SequenceMatcher(None, a, b, autojunk=False)
            if min(match.real_quick_ratio(), match.quick_ratio()) >= RATIO and match.ratio() >= RATIO:
                yield n, m


found = 0
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        for n, m in near_duplicates(handle.read()):
            found += 1
            print(f"{path}:{n} and {m} are two versions of one line, as a union merge leaves them: keep one")
sys.exit(1 if found else 0)
