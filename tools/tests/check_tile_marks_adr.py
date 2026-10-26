"""Check ADR-0215 (M1-36): the survey of how 15 galleries mark a tile's kind, one row per product with every column
filled and sourced and a screenshot kept beside the ADR; the mark complaints with counts; a proposal whose every
decision names its alternative, its reason and a screenshot; mock-ups at three densities in light and dark; the
hand-off task with the line that leaves M1-32; and the owner's acceptance.

    check_tile_marks_adr.py [root]
"""
import re
import struct
import sys
from pathlib import Path

import checklib
from checklib import check, finish

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else checklib.ROOT)
ADR = ROOT / "docs/adr/0215-tile-kind-marks.md"
ASSETS = "assets/0215/"
COLUMNS = ["product", "build", "live or motion", "panorama", "360° photo", "360° video", "video, duration", "slo-mo",
           "time-lapse", "burst or stack", "gif or animated", "raw", "hdr", "spatial", "edited", "favourite", "shared",
           "cloud or local", "glyph or text", "corner", "size", "scrim", "small tiles", "switch off", "screen reader",
           "screenshot"]
PRODUCTS = ["Apple Photos", "Google Photos", "Samsung Gallery", "OneDrive", "Amazon Photos", "Synology Photos",
            "Immich", "Ente", "PhotoPrism", "Nextcloud Memories", "Piwigo", "LibrePhotos", "Aves", "Fossify Gallery",
            "Simple Gallery"]
DECISIONS = ["Kinds", "Precedence", "Slots", "Glyphs", "Sizes", "Hide threshold", "Setting", "Painter",
             "Screen-reader labels", "List view"]
MOCKUPS = [f"mockup-{density}-{theme}.png" for density in ("months", "days", "comfortable")
           for theme in ("light", "dark")]
HANDOFF = ["Title", "Body", "Acceptance", "Size", "Dependencies"]
M1_32 = "a GIF badge on animated tiles with grid animation off by default"
SOURCE = re.compile(r"\[([a-z]{2}\d+)\]")
MAX_BYTES, MAX_WIDTH = 300_000, 1280


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def table(text, first):
    """The table whose header starts with `first`: its header cells lower-cased, and its rows."""
    lines = text.splitlines()
    i = next((i for i, line in enumerate(lines) if line.startswith("|") and cells(line)[0].lower() == first), None)
    if i is None:
        return [], []
    end = next((j for j in range(i, len(lines)) if not lines[j].startswith("|")), len(lines))
    return [c.lower() for c in cells(lines[i])], [cells(row) for row in lines[i + 2:end]]


def section(text, heading):
    """The text under the first heading that starts with `heading`, up to the next heading of its level or above."""
    match = re.search(rf"^(#+) {re.escape(heading)}\b.*$", text, re.MULTILINE)
    if not match:
        return ""
    rest = text[match.end():]
    end = re.search(rf"^#{{1,{len(match.group(1))}}} ", rest, re.MULTILINE)
    return rest[:end.start()] if end else rest


def width(path):
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">I", data[16:20])[0]
    i = 2
    while data[:2] == b"\xff\xd8" and i < len(data) - 9:
        marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            return struct.unpack(">H", data[i + 7:i + 9])[0]
        i += 2 + length
    return None


def image(link):
    path = ADR.parent / link
    if not check(path.is_file(), f"{link} exists"):
        return
    size, w = path.stat().st_size, width(path)
    check(size <= MAX_BYTES and w is not None and w <= MAX_WIDTH, f"{link} is a PNG or JPEG of at most {MAX_WIDTH} px "
          f"and {MAX_BYTES // 1000} KB", f"{link}: {size} bytes, {w} px wide")


def main():
    if not check(ADR.is_file(), f"{ADR.relative_to(ROOT)} exists"):
        return
    text = ADR.read_text(encoding="utf-8")
    defined = set(re.findall(r"^\[([a-z]{2}\d+)\]: https?://\S+", text, re.MULTILINE))

    header, rows = table(text, "product")
    check(header == COLUMNS, "the survey table has the 26 columns", f"survey columns are {header}")
    named = [row[0] for row in rows]
    check(named == PRODUCTS, "the survey has one row per product, all 15", f"survey rows are {named}")
    shots = set()
    for row in rows:
        if not check(len(row) == len(COLUMNS), f"{row[0]} has every column", f"{row[0]}: {len(row)} cells"):
            continue
        unsourced = [COLUMNS[i] for i, cell in enumerate(row[1:-1], 1) if not set(SOURCE.findall(cell)) & defined
                     or not SOURCE.sub("", cell).strip(" ,;·")]
        check(not unsourced, f"{row[0]}: every cell is filled and cites a source",
              f"{row[0]}: no value or source in {unsourced}")
        links = re.findall(rf"\(({re.escape(ASSETS)}[^)]+)\)", row[-1])
        check(links, f"{row[0]} links its screenshot", f"{row[0]} links no screenshot under {ASSETS}")
        shots.update(links)
    for link in sorted(shots):
        image(link)

    complaints = section(text, "Complaints")
    counted = re.findall(r"^\|[^|]+\|\s*(\d+)\s*\|\s*(\d+)\s*\|", complaints, re.MULTILINE)
    check(len(counted) >= 5 and "review" in complaints.lower(), "the complaints from the corpus and the review study "
          "are counted", f"{len(counted)} counted complaint rows")

    for decision in DECISIONS:
        body = section(text, decision)
        check(body and "Alternative" in body and "Why" in body and ASSETS in body,
              f"the decision '{decision}' names an alternative, a reason and a screenshot",
              f"the decision '{decision}' lacks a section, an alternative, a reason or a screenshot")
    for mockup in MOCKUPS:
        check(f"({ASSETS}{mockup})" in text, f"links mock-up {mockup}")
        image(ASSETS + mockup)

    handoff = section(text, "Hand-off")
    missing = [part for part in HANDOFF if not re.search(rf"\*\*{part}\*\*", handoff)]
    check(not missing, "the hand-off task has a title, body, acceptance, size and dependencies",
          f"hand-off lacks {missing}")
    check(M1_32 in handoff, "the hand-off names the M1-32 line to move")
    accepted = r"^\* \*\*Status\*\*: Accepted — 2026-10-21\. The owner kept every decision[^*]*photolib-design#590"
    check(re.search(accepted, text, re.MULTILINE), "the ADR is Accepted, as the owner kept every decision (#590)")


main()
finish()
