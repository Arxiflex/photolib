"""Check the scenario ADRs of M2-45, M2-46 and M3-22: competitors compared, invariants stated, a catalogue of well
over a hundred scenarios generated from named dimensions, each row complete and checked against the invariants, and
every row in a numbered proposal for the owner's sign-off; once the owner answered, Accepted with the answers' caveats,
a proposal the owner left open still to confirm.

    check_scenario_adrs.py [root]
"""
import re
import sys
from pathlib import Path

import checklib
from checklib import check, finish

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else checklib.ROOT)
MIN_ROWS = 120
CLIENTS = ("android", "ios", "desktop", "web")
ADRS = {
    "0200-device-and-server-copies.md": {
        "columns": ["id", "dims", "story", "worst", "clients show", "app and server do", "never", "alternatives",
                    "inv"],
        "products": ["Google Photos", "Apple Photos", "Immich", "Ente", "Mylio", "Synology Photos", "PhotoPrism"],
        "invariants": [r"one logical asset is one tile", r"server copy is the source of truth once verified",
                       r"deletion follows intent and never resurrects",
                       r"nothing leaves a device unless its backup is verified", r"every space claim is exact"],
        "required_dims": ["p"],
        "every_client": True,
        "links": ["0201", "0202"],
        "docs": [r"\b02\b", r"04 §4", r"05 §6\.1", r"05 §6\b", r"10 §3\.6", r"10 §11"],
        "answered": 576,
        "answers": [r"private hashes are keyed", r"until a key-holding device has seen both", r"M5-14", r"M2-48",
                    r"ADR-0092 stays[^.]*owner kept this reading[^.]*photolib-design#668"],
    },
    "0201-sources.md": {
        "columns": ["id", "dims", "story", "worst", "user sees", "photolib does", "alternatives", "inv"],
        "products": ["Folio", "PixFolio", "PhotoPrism", "Nextcloud Memories", "Mylio", "Synology Photos", "Immich",
                     "Aves", "Fossify", "digiKam", "Plex", "Jellyfin", "rclone"],
        "invariants": [r"originals are never touched without a write policy", r"a disconnected source never deletes",
                       r"one logical asset is one tile", r"every estimate is shown before (the )?work starts"],
        "required_dims": ["k"],
        "links": ["0200", "0202"],
        "docs": [r"LIB-13", r"LIB-14", r"MOB-06", r"ING-22", r"API-09", r"07 §1\b", r"07 §4", r"07 §5", r"07 §10",
                 r"10 §5", r"10 §8", r"10 §11", r"\b05\b"],
        "model": ["device", "folder", "managed", "external", "drive", "share", "bucket"],
        "model_rows": ["card", "vocabulary", "provenance", "offline", "cache", "cost", "auth", "link or import",
                       "writes"],
        "answered": 579,
        "open": [6],
        "answers": [r"Google's verification for Drive scopes", r"#571", r"kept this status[^.]*photolib-design#670"],
    },
    "0202-albums-across-custody.md": {
        "columns": ["id", "dims", "story", "worst", "surfaces show", "server does", "guarantee", "reverse",
                    "alternatives", "inv"],
        "products": ["Google Photos", "Apple Photos", "Immich", "Ente", "Mylio", "Synology Photos", "PhotoPrism",
                     "digiKam", "Lightroom"],
        "invariants": [r"never drops an album member",
                       r"never deletes an asset because a library is offline or a file is missing",
                       r"content hash and library-relative path",
                       r"restores everything on reconnection without user action"],
        "required_dims": ["p"],
        "groups": "ABCDEFG",
        "links": ["0200", "0201"],
        "docs": [r"04 §4", r"04 §9", r"05 §7", r"06 §13", r"07 §4", r"10 §3\.6", r"12 §5", r"12 §6"],
        "answered": 581,
        "answers": [r"M5-14", r"photolib-design#571", r"gap G2"],
    },
}
CODE = re.compile(r"\b([a-z])(\d+)\b")
ROW_REF = re.compile(r"\b([A-Z]{1,2})(\d+)(?:[–-]\1?(\d+))?\b")


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def tables(text):
    """Every table as (header, rows), header cells lower-cased."""
    out, header = [], None
    for line in text.splitlines():
        if not line.startswith("|"):
            header = None
        elif header is None:
            header = [c.lower() for c in cells(line)]
            out.append((header, []))
        elif not set(line) <= set("|-: "):
            out[-1][1].append(cells(line))
    return out


def section(text, title):
    """The text under the first heading named `title`, up to the next heading of the same or a higher level."""
    match = re.search(rf"^(#+) {re.escape(title)}\s*$", text, re.MULTILINE)
    if not match:
        return ""
    rest = text[match.end():]
    end = re.search(rf"^#{{1,{len(match.group(1))}}} ", rest, re.MULTILINE)
    return rest[:end.start()] if end else rest


def covers_every_client(cell):
    words = cell.lower()
    if re.search(r"\b(all|every client|others|elsewhere)\b", words):
        return True
    seen = {c for c in CLIENTS if re.search(rf"\b{c}\b", words)}
    if re.search(r"\bphones?\b", words):
        seen |= {"android", "ios"}
    return seen == set(CLIENTS)


def check_adr(name, spec):
    path = ROOT / "docs/adr" / name
    if not check(path.is_file(), f"{name} exists"):
        return
    text = path.read_text(encoding="utf-8")
    index = (ROOT / "docs/adr/README.md").read_text(encoding="utf-8")
    status = re.search(r"^\* \*\*Status\*\*: (.*(?:\n  .*)*)", text, re.MULTILINE)
    status = status.group(1) if status else ""
    answered = spec.get("answered")
    if answered:
        check(re.match(r"Accepted — \d{4}-\d\d-\d\d", status) and f"photolib-design#{answered}" in status,
              f"{name} is Accepted with the owner's answers (photolib-design#{answered})")
        check(re.search(rf"\({re.escape(name)}\) \| [^|]+ \| Accepted", index), f"the index lists {name} as Accepted")
    else:
        check(status.startswith("**Proposed** — owner to confirm"), f"{name} is Proposed")
        check(re.search(rf"\({re.escape(name)}\) \| [^|]+ \| \*\*Proposed — owner to confirm\*\* \|", index),
              f"the index lists {name} as Proposed")
    for pattern in spec.get("answers", []):
        check(re.search(pattern, text), f"{name} states the owner's answer /{pattern}/")
    for other in spec["links"]:
        check(re.search(rf"\]\({other}-[a-z-]+\.md\)", text), f"{name} links ADR-{other}")

    tags = sorted(set(re.findall(r"<(?!https?://)[A-Za-z][^>`]*>", re.sub(r"`[^`]*`", "", text))))
    check(not tags, f"{name} has no placeholder Markdown would swallow as HTML", f"{name} has raw tags {tags}")

    others = section(text, "How others behave")
    sources = re.findall(r"^\* [A-Z]+\d+[a-z]? — \[[^\]]+\]\(https?://[^)]+\)", others, re.MULTILINE)
    check(len(sources) >= 20, f"{name} cites at least 20 sources", f"{name} cites {len(sources)} sources")
    refs = re.sub(r"^\* [A-Z]+\d+[a-z]? — .*$", "", text, flags=re.MULTILINE)
    cited = {f"{a}{n}" for a, b, c in re.findall(r"\b([A-Z]{2})(\d+)(?:–\1(\d+))?\b", refs)
             for n in range(int(b), int(c or b) + 1)}
    unused = [ref for ref in (line.split()[1] for line in sources) if ref not in cited]
    check(not unused, f"{name} cites every source it lists", f"{name} lists sources it never cites: {unused}")
    for product in spec["products"]:
        compared = any(product.lower() in " ".join(h + [r[0] for r in rows]).lower() for h, rows in tables(others))
        check(compared, f"{name} compares {product}")
    check(re.search(r"^#+ Complaints", others, re.MULTILINE), f"{name} lists the complaints each behaviour caused")

    invariants = dict(re.findall(r"^\* \*\*(I\d+) — ([^*]+)\*\*", text, re.MULTILINE))
    for pattern in spec["invariants"]:
        check(any(re.search(pattern, v, re.IGNORECASE) for v in invariants.values()), f"{name} states /{pattern}/")

    dims = {}
    for header, rows in tables(text):
        if header == ["dimension", "values"]:
            for row in rows:
                for letter, number in re.findall(r"`([a-z])(\d+)`", row[1]):
                    dims[letter + number] = row[0]
    check(dims, f"{name} names the dimensions of its catalogue")
    check(section(text, "How the catalogue was generated").strip(), f"{name} says how the catalogue was generated")

    rows = [r for header, rs in tables(text) if header[:2] == ["id", "dims"] for r in rs]
    check(all(h == spec["columns"] for h, _ in tables(text) if h[:2] == ["id", "dims"]),
          f"{name}'s scenario tables have the columns {spec['columns']}")
    check(len(rows) >= MIN_ROWS, f"{name} decides at least {MIN_ROWS} scenarios",
          f"{name} decides {len(rows)} scenarios, fewer than {MIN_ROWS}")
    ids, used = [], set()
    for row in rows:
        rid = row[0]
        ids.append(rid)
        problems = []
        if len(row) != len(spec["columns"]) or not all(row):
            problems.append("needs every column filled")
        codes = {a + b for a, b in CODE.findall(row[1] if len(row) > 1 else "")}
        used |= codes
        if not codes or codes - dims.keys():
            problems.append(f"names unknown or no dimensions {sorted(codes - dims.keys()) or ''}")
        for letter in spec["required_dims"]:
            if not any(c.startswith(letter) for c in codes):
                problems.append(f"names no '{letter}' dimension")
        refs = set(re.findall(r"\bI\d+\b", row[-1]))
        if not refs or refs - invariants.keys():
            problems.append("is checked against no or unknown invariants")
        if spec.get("every_client") and len(row) > 4 and not covers_every_client(row[4]):
            problems.append("does not say what every client shows")
        if problems:
            check(False, "", f"{name} row {rid} " + "; ".join(problems))
    check(len(ids) == len(set(ids)), f"{name}'s rows have unique ids")
    for code in sorted(dims.keys() - used):
        check(False, "", f"{name}: no scenario has the dimension value {code} ({dims[code]})")
    for group in spec.get("groups", ""):
        check(any(re.fullmatch(rf"{group}\d+", i) for i in ids), f"{name} decides scenarios of group {group}")

    proposals = re.findall(r"^\d+\. .*(?:\n {3}.*)*", section(text, "Proposals for sign-off"), re.MULTILINE)
    check(proposals, f"{name} numbers its proposals for sign-off")
    covered = set()
    for proposal in proposals:
        for refs in re.findall(r"\(rows? ([^)]*)\)", proposal):
            for prefix, start, end in ROW_REF.findall(refs):
                covered |= {f"{prefix}{n}" for n in range(int(start), int(end or start) + 1)}
    missing = [i for i in ids if i not in covered]
    check(not missing, f"every row of {name} is in a numbered proposal",
          f"{name}: rows in no proposal: {', '.join(missing[:20])}")
    for number in spec.get("open", []):
        proposal = next((p for p in proposals if p.startswith(f"{number}. ")), "")
        check("open, owner to confirm" in proposal and f"proposal {number}" in status,
              f"{name}'s proposal {number} stays open, owner to confirm")

    changes = section(text, "Design changes after sign-off")
    for doc in spec["docs"]:
        check(re.search(doc, changes), f"{name} records how /{doc}/ changes")

    if "model" in spec:
        model = [(h, rs) for h, rs in tables(text) if set(spec["model"]) <= set(h)]
        check(model, f"{name} applies the Sources model to every source kind in one table")
        names = " ".join(r[0].lower() for _, rs in model for r in rs)
        for rule in spec["model_rows"]:
            check(rule in names, f"{name}'s model table has the {rule} rule")
        check(any(h[:2] == ["rank", "provider"] for h, _ in tables(text)), f"{name} ranks the providers")


for adr, spec in ADRS.items():
    check_adr(adr, spec)
finish()
