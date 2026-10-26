#!/usr/bin/env python3
"""Decodability of the media corpus (ADR-0020), run with the Pillow pinned in tools/corpus/decode-requirements.txt.

Every still meant to be decodable opens with its stored size and shows the picture its path names (tools/corpus/
picture.py); so does every JPEG inside a file (EXIF thumbnail, MPF secondary, gain or depth map, RAW preview, MJPEG
frame), whose seed is the path plus its role. Files broken on purpose stay broken; every other image, video or audio
file says in its notes that its payload is a placeholder.
"""
import io
import json
import os
import struct
import sys
import warnings
import xml.etree.ElementTree as ElementTree

from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "corpus"))
import picture  # noqa: E402

ROOT = os.path.join(HERE, "..", "..", "testdata", "corpus")
ROLES = ("", " preview", " thumbnail", " secondary", " gain map", " depth map")
TOLERANCE = 6  # mean absolute error per sample on the grid: lossy coding stays under 3, corrupt data well above 10
RASTER = {"jpeg", "insp", "thm", "png", "apng", "gif", "bmp", "webp", "tiff", "psd", "psb"}
RAW = {"cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "dng"}
SOI = b"\xff\xd8\xff"
PROBLEMS = []
warnings.filterwarnings("ignore", "Corrupt EXIF data", UserWarning)  # the broken-EXIF cases, on purpose


def check(condition, message):
    if not condition:
        PROBLEMS.append(message)
    return condition


def load(data, every_frame=True):
    """Every frame of the image, decoded (only the first for a RAW, whose IFD1 is an EXIF-style JPEG thumbnail)."""
    image = Image.open(io.BytesIO(data))
    image.load()
    frames = [image.copy()]
    for index in range(1, getattr(image, "n_frames", 1) if every_frame else 1):
        image.seek(index)
        image.load()
        frames.append(image.copy())
    return frames


def psb(data):
    """Pillow reads PSD only: an uncompressed RGB PSB (large document) decoded with struct."""
    height, width = struct.unpack_from(">II", data, 14)
    pos = 26
    for size in (4, 4, 8):
        pos += size + int.from_bytes(data[pos:pos + size], "big")
    assert data[pos:pos + 2] == b"\0\0", "PSB image data is not raw"
    planes = [data[pos + 2 + i * width * height:][:width * height] for i in range(3)]
    return [Image.merge("RGB", [Image.frombytes("L", (width, height), plane) for plane in planes])]


def eight_bit(image):
    """L or RGB; 16-bit and float samples scaled to 8 bits (floats run from 0 to 1)."""
    if image.mode in ("I", "I;16", "I;16B", "F"):
        return image.convert("F").point(lambda v: v * (255 if image.mode == "F" else 1 / 257)).convert("L")
    return image if image.mode == "L" else image.convert("RGB")


def thumbnail(image):
    return list(eight_bit(image).convert("RGB").resize((32, 24)).get_flattened_data())


def error(image, seed, frame=0):
    """Mean absolute difference per sample between the decoded image and the picture seed names, on a 32 x 24 grid
    of pixel centres (greyscale images against the picture's grey)."""
    image = eight_bit(image)
    width, height = image.size
    rows, pixels, total = picture.rows(seed, width, height, frame), image.load(), 0
    for y in ((2 * j + 1) * height // 48 for j in range(24)):
        for x in ((2 * i + 1) * width // 64 for i in range(32)):
            want = tuple(rows[y][3 * x:3 * x + 3])
            got = pixels[x, y]
            if image.mode == "L":
                want, got = (picture.grey(want),), (got,)
            total += sum(abs(a - b) for a, b in zip(want, got)) / len(want)
    return total / (32 * 24)


def shows(image, seeds, label, frame=0):
    """The image is the picture of one of the seeds."""
    best = min(error(image, seed, frame) for seed in seeds)
    return check(best <= TOLERANCE, f"{label}: differs from its picture (mean error {best:.1f})")


def embedded_jpegs(data, label, path):
    """Decodes every JPEG that starts in data and compares it with its picture: the path's own at byte 0, else the
    path's with a role; returns them."""
    found, pos = [], data.find(SOI)
    while pos >= 0:
        try:
            found.append(load(data[pos:])[0])
            shows(found[-1], [path + role for role in (ROLES[:1] if pos == 0 else ROLES)], f"{label} @ {pos}")
        except OSError as error:
            check(False, f"{label}: the JPEG at byte {pos} does not decode ({error})")
        pos = data.find(SOI, pos + 1)
    return found


def mjpeg_frames(data, container):
    """The frame payloads of an MJPEG AVI (00dc chunks) or QuickTime file (stsz sizes from the stco offset)."""
    if container == "avi":
        pos, frames = data.index(b"movi") + 4, []
        while pos + 8 <= len(data) and data[pos:pos + 4] == b"00dc":
            (size,) = struct.unpack_from("<I", data, pos + 4)
            frames.append(data[pos + 8:pos + 8 + size])
            pos += 8 + size + size % 2
        return frames
    stsz, stco = data.index(b"stsz") + 4, data.index(b"stco") + 4
    _, count = struct.unpack_from(">II", data, stsz + 4)
    sizes = struct.unpack_from(f">{count}I", data, stsz + 12)
    (offset,) = struct.unpack_from(">I", data, stco + 8)
    frames = []
    for size in sizes:
        frames.append(data[offset:offset + size])
        offset += size
    return frames


def asymmetric(image, label):
    for name, turned in (("mirror", ImageOps.mirror), ("flip", ImageOps.flip), ("rotation", lambda i: i.rotate(180))):
        check(thumbnail(turned(image)) != thumbnail(image), f"{label}: looks the same after a {name}")


def still(record, data, label):
    meta, fmt = record["metadata"], record["format"]
    size = (meta.get("width"), meta.get("height"))
    if "truncated_file" in record["quirks"]:
        try:
            load(data)
            check(False, f"{label}: a truncated file decodes")
        except OSError:
            pass
        return
    try:
        frames = psb(data) if fmt == "psb" else load(data, fmt not in RAW)
    except (OSError, AssertionError) as error:
        check(False, f"{label}: does not decode ({error})")
        return
    check(frames[0].size == size, f"{label}: decodes as {frames[0].size}, the record says {size}")
    exif = frames[0].getexif().get_ifd(0x8769)
    if 0xA002 in exif:
        check((exif[0xA002], exif[0xA003]) == size, f"{label}: EXIF says {exif[0xA002]}x{exif[0xA003]}, not {size}")
    animated = "animated" in record["quirks"]
    for number, frame in enumerate(frames):
        if number == 0 or animated or "multipage" in record["quirks"]:  # other frames: MPF secondaries, see below
            shows(frame, [label], f"{label} frame {number}", number if animated else 0)
    if record["media"]["container"] == "jpeg":
        embedded_jpegs(data, label, label)
    if "exif_orientation" in record["quirks"]:
        asymmetric(frames[0], label)


def main():
    counts = {"decoded": 0, "placeholder": 0}
    for folder, _, names in os.walk(os.path.join(ROOT, "golden")):
        for name in sorted(names):
            with open(os.path.join(folder, name), encoding="utf-8") as handle:
                record = json.load(handle)
            label = record["path"]
            with open(os.path.join(ROOT, "files", label), "rb") as handle:
                data = handle.read()
            fmt, meta, media = record["format"], record["metadata"], record["media"]
            if fmt in RASTER:
                still(record, data, label)
            elif fmt == "svg":
                root = ElementTree.fromstring(data)
                check((root.get("width"), root.get("height")) == (str(meta["width"]), str(meta["height"])),
                      f"{label}: the SVG size differs from the record")
                text = "".join(root.itertext())
                check(label.rsplit("/", 1)[-1] in text and len(root) >= 4, f"{label}: the SVG draws no picture")
            elif fmt in RAW:
                check(embedded_jpegs(data, label, label), f"{label}: no decodable JPEG preview")
                if fmt == "dng" and not {"dng_jxl", "proraw"} & set(record["quirks"]):
                    still(record, data, label)
            elif meta.get("codec") == "mjpeg":
                frames = mjpeg_frames(data, media["container"])
                check(frames, f"{label}: no MJPEG frames")
                for number, frame in enumerate(frames):
                    image = embedded_jpegs(frame, f"{label} frame {number}", label)[:1]
                    check(image and image[0].size == (meta["width"], meta["height"]), f"{label}: frame {number} size")
            elif media["kind"] in ("image", "video", "audio"):
                counts["placeholder"] += 1
                check("placeholder" in record.get("notes", "").lower(), f"{label}: not decodable, but its notes do"
                      " not say that the payload is a placeholder")
                continue
            else:
                continue
            counts["decoded"] += 1
    for problem in PROBLEMS:
        print(f"FAIL: {problem}", file=sys.stderr)
    print(f"corpus decode: {counts['decoded']} files decoded, {counts['placeholder']} placeholders,"
          f" {len(PROBLEMS)} problem(s)")
    return 1 if PROBLEMS else 0


if __name__ == "__main__":
    sys.exit(main())
