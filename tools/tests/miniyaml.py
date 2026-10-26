#!/usr/bin/env python3
"""A small YAML reader for the repository's own tests (no third-party packages are available in CI or the gate).

    miniyaml.py --selftest

Supports the subset used by GitHub issue forms and similar config files: block mappings and sequences, plain,
'single' and "double" quoted scalars, booleans, integers, null, flow lists of scalars ([a, b]), literal and folded
block scalars (| and >, with - and + chomping), the empty mapping {} and comments. Anything else (anchors, tags,
flow mappings, multiple documents) raises ValueError instead of being misread.
"""
import re
import sys


class Line:
    def __init__(self, number, raw):
        self.number = number
        self.raw = raw
        self.indent = len(raw) - len(raw.lstrip(" "))
        self.text = raw.strip()

    @property
    def skippable(self):
        return not self.text or self.text.startswith("#")


def scalar(text, number):
    text = text.strip()
    if text == "{}":
        return {}
    if text[:1] in "&*!{%@`" or (text.startswith("[") and not text.endswith("]")):
        raise ValueError(f"line {number}: unsupported YAML syntax: {text}")
    if text.startswith("["):
        inner = text[1:-1].strip()
        return [scalar(part, number) for part in split_flow(inner, number)] if inner else []
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        body = text[1:-1]
        return body.replace("''", "'") if text[0] == "'" else body.replace('\\"', '"').replace("\\\\", "\\")
    text = re.sub(r"\s+#.*$", "", text)
    if text in ("true", "True"):
        return True
    if text in ("false", "False"):
        return False
    if text in ("null", "~", ""):
        return None
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return text


def split_flow(inner, number):
    parts, current, quote = [], "", None
    for char in inner:
        if quote:
            current += char
            quote = None if char == quote else quote
        elif char in "\"'":
            quote = char
            current += char
        elif char == ",":
            parts.append(current)
            current = ""
        elif char in "[]{}":
            raise ValueError(f"line {number}: nested flow collections are not supported")
        else:
            current += char
    parts.append(current)
    return parts


def split_key(text, number):
    match = re.match(r"""^("[^"]*"|'[^']*'|[^\s:#'"-][^:#]*?|-[^\s:][^:#]*?)\s*:(?:\s+(.*))?$""", text)
    if not match:
        raise ValueError(f"line {number}: expected 'key: value', got: {text}")
    key = match.group(1)
    if key[0] in "\"'":
        key = key[1:-1]
    return key, (match.group(2) or "").strip()


class Parser:
    def __init__(self, text):
        self.lines = [Line(n, raw.rstrip("\n").replace("\t", "    ")) for n, raw in enumerate(text.splitlines(), 1)]
        if any(line.text == "---" or line.text == "..." for line in self.lines if line.indent == 0):
            raise ValueError("multiple documents and document markers are not supported")
        self.pos = 0

    def peek(self):
        while self.pos < len(self.lines) and self.lines[self.pos].skippable:
            self.pos += 1
        return self.lines[self.pos] if self.pos < len(self.lines) else None

    def parse(self):
        first = self.peek()
        if first is None:
            return None
        value = self.block(first.indent)
        if self.peek() is not None:
            raise ValueError(f"line {self.peek().number}: unexpected indentation")
        return value

    def block(self, indent):
        line = self.peek()
        if line.text == "-" or line.text.startswith("- "):
            return self.sequence(indent)
        return self.mapping(indent)

    def sequence(self, indent):
        items = []
        while True:
            line = self.peek()
            if line is None or line.indent != indent or not (line.text == "-" or line.text.startswith("- ")):
                break
            rest = line.text[1:].lstrip()
            if not rest:
                self.pos += 1
                nxt = self.peek()
                items.append(self.block(nxt.indent) if nxt and nxt.indent > indent else None)
            elif re.match(r"""^("[^"]*"|'[^']*'|[^\s:#'"\[-][^:#]*?)\s*:(\s|$)""", rest):
                offset = indent + 1
                offset += len(line.raw[offset:]) - len(line.raw[offset:].lstrip(" "))
                self.lines[self.pos] = Line(line.number, " " * offset + rest)
                items.append(self.mapping(offset))
            else:
                self.pos += 1
                items.append(scalar(rest, line.number))
        return items

    def mapping(self, indent):
        result = {}
        while True:
            line = self.peek()
            if line is None or line.indent < indent:
                break
            if line.indent > indent:
                raise ValueError(f"line {line.number}: unexpected indentation")
            if line.text == "-" or line.text.startswith("- "):
                break
            key, rest = split_key(line.text, line.number)
            if key in result:
                raise ValueError(f"line {line.number}: duplicate key '{key}'")
            self.pos += 1
            if rest[:1] in ("|", ">"):
                result[key] = self.block_scalar(rest, indent)
            elif rest and not rest.startswith("#"):
                result[key] = scalar(rest, line.number)
            else:
                nxt = self.peek()
                if nxt and nxt.indent > indent:
                    result[key] = self.block(nxt.indent)
                elif nxt and nxt.indent == indent and (nxt.text == "-" or nxt.text.startswith("- ")):
                    result[key] = self.sequence(indent)
                else:
                    result[key] = None
        return result

    def block_scalar(self, header, parent_indent):
        match = re.fullmatch(r"([|>])([+-]?)\s*(#.*)?", header)
        if not match:
            raise ValueError(f"unsupported block scalar header: {header}")
        style, chomp = match.group(1), match.group(2)
        body = []
        while self.pos < len(self.lines):
            line = self.lines[self.pos]
            if line.text and line.indent <= parent_indent:
                break
            body.append(line)
            self.pos += 1
        while body and not body[-1].text:
            body.pop()
        indents = [line.indent for line in body if line.text]
        strip = min(indents) if indents else 0
        rows = [line.raw[strip:] if line.text else "" for line in body]
        if style == "|":
            text = "\n".join(rows)
        else:
            text = re.sub(r"(?<!\n)\n(?!\n)", " ", "\n".join(rows))
        return text if chomp == "-" else text + "\n"


def load(text):
    return Parser(text).parse()


def selftest():
    failures = 0

    def expect(text, want):
        nonlocal failures
        try:
            got = load(text)
        except ValueError as error:
            got = f"ValueError: {error}"
        if got != want:
            print(f"FAIL: miniyaml selftest: {text!r}\n  want {want!r}\n  got  {got!r}", file=sys.stderr)
            failures += 1

    expect("a: 1\nb: two\nc: true\nd: 'x y'\ne: \"q\"\nf:\n", {"a": 1, "b": "two", "c": True, "d": "x y", "e": "q", "f": None})
    expect("labels: [bug, \"needs triage\"]\nnone: []\n", {"labels": ["bug", "needs triage"], "none": []})
    expect("body:\n  - type: input\n    id: version\n    attributes:\n      label: Version\n  - type: markdown\n",
           {"body": [{"type": "input", "id": "version", "attributes": {"label": "Version"}}, {"type": "markdown"}]})
    expect("opts:\n- a\n- b\n", {"opts": ["a", "b"]})
    expect("opts:\n  - a # note\n  - 'b: c'\n  - \"d\"\n", {"opts": ["a", "b: c", "d"]})
    expect("v: |\n  line one\n\n  ### heading\n    indented\nnext: 1\n", {"v": "line one\n\n### heading\n  indented\n", "next": 1})
    expect("v: |-\n  keep\nn: >\n  fold\n  me\n", {"v": "keep", "n": "fold me\n"})
    expect("# only a comment\n\na: 1  # trailing\n", {"a": 1})
    expect("url: https://example.com/a#b\n", {"url": "https://example.com/a#b"})
    expect("- a\n-\n  - b\n", ["a", [ "b"]])
    expect("a: 1\na: 2\n", "ValueError: line 2: duplicate key 'a'")
    expect("a: &anchor 1\n", "ValueError: line 1: unsupported YAML syntax: &anchor 1")
    expect("a: {}\nb: [x]\n", {"a": {}, "b": ["x"]})
    expect("a: {b: 1}\n", "ValueError: line 1: unsupported YAML syntax: {b: 1}")
    expect("a: 1\n---\nb: 2\n", "ValueError: multiple documents and document markers are not supported")
    expect("a: 1\n  b: 2\n", "ValueError: line 2: unexpected indentation")
    return failures


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(1 if selftest() else 0)
    print(__doc__, file=sys.stderr)
    sys.exit(2)
