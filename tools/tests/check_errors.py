#!/usr/bin/env python3
"""The error catalogue (OPS-30) is complete and no user-facing text shows a raw error.

    check_errors.py [<repository root>]

Every reason photolibd sends (`ApiError::new(ErrorCode::…, "reason")`, or through a helper that passes its
`&'static str` argument on) has an entry `'reason': (s) => (s.cause, s.next)` in app/lib/core/problems.dart, and every
entry is such a reason; each cause and next step has a value in every launched app_<locale>.arb. No ARB value holds a
reason or Connect code, an exception class, a stack frame or a bare error number. In Dart (app/lib,
app/packages/*/lib) and TypeScript (viewer/src), an error interpolated or turned into text where text is shown fails,
unless `// error-ok: <why>` is on its line or the line above.
"""
import json
import re
import sys
from pathlib import Path

CATALOGUE = "app/lib/core/problems.dart"
PSEUDO = ("en_XA", "ar_XB")
REASON = r'"([a-z0-9_]+(?:\.[a-z0-9_]+)+)"'
DIRECT = re.compile(r"ApiError::new\(\s*ErrorCode::\w+,\s*" + REASON)
HELPER = re.compile(r"fn (\w+)\s*\(\s*(\w+)\s*:\s*&'static str\s*\)[^{]*\{[^}]*?"
                    r"ApiError::new\(\s*ErrorCode::\w+,\s*(\w+)\s*\)")
ENTRY = re.compile(r"'([a-z0-9_]+(?:\.[a-z0-9_]+)+)'\s*:\s*\(s\)\s*=>\s*"
                   r"\(\s*s\.(\w+)\s*,\s*s\.(\w+)\s*,?\s*\)")
CONNECT = ("invalid_argument", "deadline_exceeded", "not_found", "already_exists", "permission_denied",
           "resource_exhausted", "failed_precondition", "out_of_range", "data_loss")
RAW_TEXT = [
    ("an exception class", re.compile(r"\b[A-Z][A-Za-z]*(?:Exception|Error)\b")),
    ("a stack frame", re.compile(r"#\d+\s+\S|\.(?:dart|rs|ts|js|kt|swift):\d+|\bat [\w.$<>]+ ?\(")),
    ("a bare error number", re.compile(r"(?:\b(?:error|code|err|fehler|erreur|errore|código|codice|fout|błąd|kod"
                                       r"|hata|kode|lỗi|mã|fel)|ошибка|код|помилка|שגיאה|خطأ|त्रुटि|エラー|오류|错误|錯誤)"
                                       r"\s*[#:：]?\s*-?\d{2,}"
                                       r"|\bHTTP\s*[1-5]\d\d\b|\b0x[0-9a-f]{4,}", re.IGNORECASE)),
]
DART_ERROR = re.compile(r"\$\{?(?:error|err|exception|e)\b|\b(?:error|err|exception|e)\.(?:toString\(\)|message\b)")
DART_SHOWN = re.compile(r"(?:\b\w*Text\s*\(|(?<!\.)\b(?:label|labelText|hintText|helperText|errorText|semanticLabel"
                        r"|semanticsLabel|tooltip|message|title|subtitle|content|text|hint)\s*:)[^;]*$")
TS_SHOWN = re.compile(r"(?:textContent|innerText|innerHTML)\s*=[^;]*\b(?:error|err|e)\b"
                      r"|alert\([^;]*\b(?:error|err|e)\b")
LOGGED = re.compile(r"\b(?:fields|error)\s*:|\b_?log\.|\bLogger\(|\bprint\(")
ALLOWED = re.compile(r"//\s*error-ok:\s*\S")


def reasons(root):
    """Every reason in server code, with a file that sends it."""
    found = {}
    for path in sorted((root / "server").glob("crates/*/src/**/*.rs")):
        text = path.read_text()
        for match in DIRECT.finditer(text):
            found.setdefault(match[1], path.relative_to(root))
        for helper in HELPER.finditer(text):
            if helper[2] == helper[3]:
                for match in re.finditer(rf"\b{helper[1]}\(\s*{REASON}\s*\)", text):
                    found.setdefault(match[1], path.relative_to(root))
    return found


def arbs(root):
    return {path.stem.removeprefix("app_"): json.loads(path.read_text())
            for path in sorted((root / "app/lib/l10n").glob("app_*.arb"))}


def shown(root):
    """(file, line, text) of each raw error where text is shown."""
    sources = [*root.glob("app/lib/**/*.dart"), *root.glob("app/packages/*/lib/**/*.dart")]
    for path in sorted(sources):
        name = str(path.relative_to(root))
        if "/l10n/" in name or "/gen/" in name or re.search(r"\.(g|pb\w*)\.dart$", name):
            continue
        yield from _flagged(name, path.read_text(), DART_ERROR, lambda before, _: DART_SHOWN.search(before[-300:]))
    for path in sorted((root / "viewer/src").glob("**/*.ts")) if (root / "viewer/src").is_dir() else []:
        name = str(path.relative_to(root))
        if "/gen/" not in name:
            yield from _flagged(name, path.read_text(), TS_SHOWN, lambda _, line: True)


def _flagged(name, text, pattern, where):
    lines = text.splitlines()
    for match in pattern.finditer(text):
        number = text.count("\n", 0, match.start())
        line = lines[number]
        if LOGGED.search(line) or line.lstrip().startswith("//") or ALLOWED.search(line) or (
                number > 0 and ALLOWED.search(lines[number - 1])):
            continue
        if where(text[:match.start()], line):
            yield name, number + 1, line.strip()


def main(root):
    problems = []
    catalogue = root / CATALOGUE
    entries = {m[1]: (m[2], m[3]) for m in ENTRY.finditer(catalogue.read_text())} if catalogue.is_file() else {}
    sent = reasons(root)
    problems += [f"{path} sends {reason}, which {CATALOGUE} has no cause and next step for"
                 for reason, path in sorted(sent.items()) if reason not in entries]
    problems += [f"{CATALOGUE}: {reason} is no reason photolibd sends"
                 for reason in sorted(entries) if reason not in sent]
    languages = arbs(root)
    for reason, keys in sorted(entries.items()):
        for locale, messages in languages.items():
            if locale in PSEUDO:
                continue
            problems += [f"app_{locale}.arb: no {key}, the {part} of {reason}"
                         for key, part in zip(keys, ("cause", "next step")) if not str(messages.get(key, "")).strip()]
    codes = set(sent) | set(CONNECT)
    for locale, messages in languages.items():
        for key, value in messages.items():
            if key.startswith("@") or not isinstance(value, str):
                continue
            words = set(re.findall(r"[a-z0-9_]+(?:\.[a-z0-9_]+)*", value))
            problems += [f"app_{locale}.arb {key}: shows the code {code}" for code in sorted(codes & words)]
            problems += [f"app_{locale}.arb {key}: shows {what}: {pattern.search(value)[0]}"
                         for what, pattern in RAW_TEXT if pattern.search(value)]
    problems += [f"{name}:{line}: shows a raw error ({text}); show its Problem, or say why with // error-ok:"
                 for name, line, text in shown(root)]
    for problem in problems:
        print(f"FAIL: {problem}", file=sys.stderr)
    if not problems:
        print(f"ok: {len(entries)} reasons have a cause and next step in {len(languages) - len(PSEUDO)} languages; "
              "no user-facing text shows a raw error")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])))
