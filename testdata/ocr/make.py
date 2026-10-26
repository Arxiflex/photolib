#!/usr/bin/env python3
"""Writes the OCR fixtures: one picture of text per script and one carrying an XSS payload, with what each says in
expected.json. Needs Pillow and the DejaVu Sans and Droid Sans Fallback fonts (both licence-clean); the pictures are
committed, so only a change here needs it:  python3 testdata/ocr/make.py"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONTS = "/usr/share/fonts/truetype/"
LATIN = FONTS + "dejavu/DejaVuSans.ttf"
CJK = FONTS + "droid/DroidSansFallbackFull.ttf"

FIXTURES = {
    "latin": ("Lisboa Estação 2026", LATIN),
    "cyrillic": ("Красная площадь, Москва", LATIN),
    "cjk": ("東京駅 丸の内", CJK),
    "xss": ("<img src=x onerror=alert(1)>", LATIN),
}

here = Path(__file__).parent
for name, (text, font) in FIXTURES.items():
    image = Image.new("RGB", (800, 128), "white")
    ImageDraw.Draw(image).text((24, 30), text, font=ImageFont.truetype(font, 44), fill="black")
    image.save(here / f"{name}.png", optimize=True)

# Two lines, one above the other, for the tests of edits: a crop of the top half keeps the first and a turn moves both.
LINES = ("Lisboa Estação 2026", "Rua Augusta 118")
image = Image.new("RGB", (800, 256), "white")
for n, line in enumerate(LINES):
    ImageDraw.Draw(image).text((24, 30 + 128 * n), line, font=ImageFont.truetype(LATIN, 44), fill="black")
image.save(here / "lines.png", optimize=True)
(here / "expected.json").write_text(
    json.dumps({**{name: text for name, (text, _) in FIXTURES.items()}, "lines": "\n".join(LINES)},
               ensure_ascii=False, indent=2) + "\n"
)
