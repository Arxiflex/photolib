#!/usr/bin/env python3
"""A small Markdown linter for the gate: a stdlib subset of markdownlint's defaults, so it needs no npm.

    mdlint.py <file>...

MD001 heading levels rise by one, MD012 no repeated blank lines, MD013 lines up to 120 characters (code blocks, tables
and unbreakable lines excepted), MD022 blank lines around headings, MD025 one title, MD031 code fences closed and
surrounded by blank lines, MD040 code fences name a language, MD041 the file starts with its title.
Prints "path:line: RULE message" per problem and exits 1 when there is one.
"""
import re
import sys

MAX_LINE = 120
FENCE = re.compile(r"^\s*(?:```|~~~)(.*)$")
HEADING = re.compile(r"^(#{1,6})\s+\S")


def lint(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    problems = []

    def flag(number, rule, message):
        problems.append(f"{path}:{number}: {rule} {message}")

    in_fence, level, titles = False, 0, 0
    if not lines[0].startswith("# "):
        flag(1, "MD041", "the file must start with a '# ' title")
    for number, line in enumerate(lines, 1):
        before = lines[number - 2] if number > 1 else ""
        after = lines[number] if number < len(lines) else ""
        fence = FENCE.match(line)
        if fence:
            if not in_fence and not fence.group(1).strip():
                flag(number, "MD040", "code fence needs a language")
            if before.strip() and not in_fence:
                flag(number, "MD031", "blank line needed before a code fence")
            if after.strip() and in_fence:
                flag(number, "MD031", "blank line needed after a code fence")
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line == "" and before == "" and number > 1:
            flag(number, "MD012", "more than one blank line in a row")
        if len(line) > MAX_LINE and not line.lstrip().startswith("|") and re.search(r"\s", line[MAX_LINE:]):
            flag(number, "MD013", f"line is {len(line)} characters; the limit is {MAX_LINE}")
        heading = HEADING.match(line)
        if heading:
            new_level = len(heading.group(1))
            if new_level > level + 1:
                flag(number, "MD001", f"heading level {new_level} follows level {level}")
            level = new_level
            titles += new_level == 1
            if titles == 2 and new_level == 1:
                flag(number, "MD025", "a second top-level heading")
            if (number > 1 and before.strip()) or after.strip():
                flag(number, "MD022", "headings need a blank line before and after")
    if in_fence:
        flag(len(lines), "MD031", "code fence is never closed")
    return problems


if __name__ == "__main__":
    found = [problem for path in sys.argv[1:] for problem in lint(path)]
    if found:
        print("\n".join(found), file=sys.stderr)
        sys.exit(1)
