#!/usr/bin/env python3
"""Decodable HEIC twins of the corpus' HEIC records, which tools/heic/bench.mjs decodes in browsers.

    twins.py <out dir>

The corpus' HEIC payloads are placeholders. A twin has its record's size, bit depth and transform (irot, imir, clap),
laid out as an iPhone writes it: 512-pixel HEVC tiles in a grid and a 320-pixel `thmb` item (one image elsewhere).
Its picture is the record's corpus picture with grain, so that it codes to about what a 12 MP phone photo does. x265
codes the tiles through the pillow-heif of requirements.txt, installed once (network on the first run) into a venv
cached as tools/tests/test_corpus.sh caches its Pillow. twins.json lists each twin with the colours it must show.
"""
import io
import json
import os
import random
import struct
import subprocess
import sys
from array import array
from multiprocessing import Pool
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools/corpus"))
from containers import Heif, box, full
from picture import rows

GOLDEN = ROOT / "testdata/corpus/golden"
TILE, THUMB, GRAIN, QUALITY = 512, 320, 32, 60


def plan(record):
    """The twin of a golden record, or None when it is no HEIC."""
    if record["format"] != "heic":
        return None
    quirks = set(record.get("quirks", []))
    width, height = record["metadata"]["width"], record["metadata"]["height"]
    clap = [width - 32, height - 24] if "heif_clap" in quirks else None
    rotation = 3 if "heif_irot" in quirks else None
    shown = clap or [width, height]
    return {
        "path": record["path"], "width": width, "height": height, "depth": 10 if "bit_depth_10" in quirks else 8,
        "grid": record.get("vendor") == "apple", "rotation": rotation, "mirror": 0 if "heif_imir" in quirks else None,
        "clap": clap, "shown": shown[::-1] if rotation else shown,
    }


def plans():
    return [p for f in sorted(GOLDEN.rglob("*.json")) if (p := plan(json.loads(f.read_text())))]


def stored(twin, x, y):
    """Where the pixel shown at (x, y) is stored: imir, irot, then clap undone (ISO/IEC 23008-12:2022 §6.5.10-12,
    where imir's axis 0 exchanges top and bottom)."""
    if twin["mirror"] == 0:
        y = twin["shown"][1] - 1 - y
    if twin["rotation"] == 3:
        x, y = y, twin["shown"][0] - 1 - x
    if twin["clap"]:
        x, y = x + (twin["width"] - twin["clap"][0]) // 2, y + (twin["height"] - twin["clap"][1]) // 2
    return x, y


def probes(twin, colour):
    """[x, y, rgb] where the twin shows one flat colour 9 pixels around, without grain, on a 6 x 6 grid."""
    w, h = twin["shown"]
    found = []
    for gy in range(1, 7):
        for gx in range(1, 7):
            x, y = w * gx // 7, h * gy // 7
            colours = {colour(*stored(twin, x + dx, y + dy)) for dx in (-9, 0, 9) for dy in (-9, 0, 9)}
            if len(colours) == 1:
                found.append([x, y, list(colours.pop())])
    return found


def boxes(data, at, end):
    while at < end:
        size, kind = struct.unpack_from(">I4s", data, at)
        yield kind, at + 8, at + size
        at += size


def coded(heif):
    """The one coded item of a file libheif wrote: its bytes and its properties' boxes but ispe."""
    meta = next((s + 4, e) for k, s, e in boxes(heif, 0, len(heif)) if k == b"meta")
    parts = {k: (s, e) for k, s, e in boxes(heif, *meta)}
    at = parts[b"iloc"][0]
    version, sizes, more = heif[at], heif[at + 4], heif[at + 5]

    def number(size):
        nonlocal at
        at += size
        return int.from_bytes(heif[at - size:at], "big")

    # the first item: its count and id, construction method (versions 1 and 2), data reference index, base offset,
    # extent count and index (versions 1 and 2), then the first extent's offset and length
    at += 6 + (2 if version < 2 else 4) * 2 + (2 if version else 0) + 2
    base = number(more >> 4)
    at += 2 + (more & 15 if version else 0)
    offset = base + number(sizes >> 4)
    length = number(sizes & 15)
    ipco = next((s, e) for k, s, e in boxes(heif, *parts[b"iprp"]) if k == b"ipco")
    return heif[offset:offset + length], [heif[s - 8:e] for k, s, e in boxes(heif, *ipco) if k != b"ispe"]


def encode(image, depth):
    """A PIL image coded alone by x265 through pillow-heif: coded()."""
    import pillow_heif
    if depth == 8:
        heif = pillow_heif.from_pillow(image)
    else:
        heif = pillow_heif.from_bytes("RGB;16", image.size, array("H", (v * 257 for v in image.tobytes())).tobytes())
    out = io.BytesIO()
    heif.save(out, quality=QUALITY, chroma=420, enc_params={"preset": "fast"})
    return coded(out.getvalue())


def grained(picture, cols, rows_):
    """The picture, its last column and row repeated to cols x rows_ tiles, with seeded grain as coarse as a photo's
    texture: the 12 MP twins code to about 2.4 MB, as iPhone photos do."""
    from PIL import Image, ImageChops
    w, h = picture.size
    out = Image.new("RGB", (cols * TILE, rows_ * TILE))
    out.paste(picture)
    if cols * TILE > w:
        out.paste(picture.crop((w - 1, 0, w, h)).resize((cols * TILE - w, h)), (w, 0))
    if rows_ * TILE > h:
        out.paste(out.crop((0, h - 1, cols * TILE, h)).resize((cols * TILE, rows_ * TILE - h)), (0, h))
    side = TILE // 4
    noise = Image.frombytes("RGB", (side, side), random.Random(TILE).randbytes(3 * side * side))
    noise = noise.resize((TILE, TILE), Image.BICUBIC).point(lambda v: v * 2 * GRAIN // 255)
    for y in range(0, out.height, TILE):
        for x in range(0, out.width, TILE):
            region = (x, y, x + TILE, y + TILE)
            out.paste(ImageChops.add(out.crop(region), noise, 1.0, -GRAIN), region)
    return out


def make(twin, out):
    """Writes the twin under out; returns its twins.json entry."""
    from PIL import Image
    w, h = twin["width"], twin["height"]
    lines = rows(twin["path"], w, h)
    picture = Image.frombytes("RGB", (w, h), b"".join(lines))
    table, shared = Heif(), {}

    def prop(data):
        if data not in shared:
            shared[data] = table.prop(data)
        return shared[data]

    def ispe(width, height):
        return prop(full(b"ispe", struct.pack(">II", width, height)))

    def item(image, hidden=False, more=()):
        data, props = encode(image, twin["depth"])
        return table.item(b"hvc1", data, [ispe(*image.size), *map(prop, props), *more], hidden=hidden)

    turns = [prop(box(b"irot", bytes([twin["rotation"]])))] if twin["rotation"] is not None else []
    turns += [prop(box(b"imir", bytes([twin["mirror"]])))] if twin["mirror"] is not None else []
    clap = [prop(box(b"clap", struct.pack(">8I", twin["clap"][0], 1, twin["clap"][1], 1, 0, 1, 0, 1)))] \
        if twin["clap"] else []
    if twin["grid"]:
        cols, rows_ = -(-w // TILE), -(-h // TILE)
        whole = grained(picture, cols, rows_)
        grid = table.item(b"grid", struct.pack(">BBBBHH", 0, 0, rows_ - 1, cols - 1, w, h), [ispe(w, h), *clap, *turns])
        table.ref(b"dimg", grid, [item(whole.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE)), hidden=True)
                                  for r in range(rows_) for c in range(cols)])
        table.ref(b"thmb", item(picture.resize((THUMB, THUMB * h // w)), more=turns), [grid])
    else:
        item(grained(picture, -(-w // TILE), -(-h // TILE)).crop((0, 0, w, h)), more=clap + turns)
    file = out / twin["path"]
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(table.build(b"heic", (b"mif1", b"heic")))
    colour = lambda x, y: tuple(lines[y][3 * x:3 * x + 3])
    return {**twin, "bytes": file.stat().st_size, "probes": probes(twin, colour)}


def venv():
    """Runs this script again in the cached venv of requirements.txt, unless pillow-heif is importable."""
    try:
        import pillow_heif  # noqa: F401
        return
    except ImportError:
        pass
    cache = Path(os.environ.get("PHOTOLIB_CACHE") or f"{os.environ.get('TMPDIR', '/var/tmp')}/photolib-{os.getuid()}")
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Never run code from a cache another user could have written.
    if cache.is_symlink() or cache.stat().st_uid != os.getuid():
        sys.exit(f"twins.py: {cache} is not a private directory of this user; set PHOTOLIB_CACHE")
    env, requirements = cache / "heic-venv", HERE / "requirements.txt"
    pinned = env / "requirements.txt"
    if not pinned.exists() or pinned.read_bytes() != requirements.read_bytes():
        subprocess.run([sys.executable, "-m", "venv", "--clear", env], check=True)
        subprocess.run([env / "bin/python", "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "-r",
                        requirements], check=True)
        pinned.write_bytes(requirements.read_bytes())
    os.execv(env / "bin/python", [env / "bin/python", __file__, *sys.argv[1:]])


if __name__ == "__main__":
    venv()
    target = Path(sys.argv[1])
    with Pool(4) as pool:
        entries = pool.starmap(make, [(twin, target) for twin in plans()])
    (target / "twins.json").write_text(json.dumps(entries, indent=1))
