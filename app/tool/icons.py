#!/usr/bin/env python3
"""Writes the app icon of every platform from photolib-design's docs/brand/icon/ (its README §7):

    python3 app/tool/icons.py <photolib-design>/docs/brand/icon

Each size is ImageMagick's downscale of the design's largest export for that platform, never an upscale, without
metadata, so a rerun with the same ImageMagick writes the same bytes. The Android adaptive icon's XML is not written
here."""
import json
import os
import shutil
import subprocess
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IM = shutil.which("magick") or shutil.which("convert") or sys.exit("icons.py: ImageMagick is missing")
SRC = os.path.abspath(sys.argv[1]) if len(sys.argv) == 2 else sys.exit(__doc__)
RES = "android/app/src/main/res"
HICOLOR = "linux/packaging/icons/hicolor"


def target(path):
    path = os.path.join(APP, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def put(master, px, path, *options, kind=""):
    """The design's <master> as <px> square at app/<path>; kind PNG24 drops the alpha, PNG32 keeps one."""
    subprocess.run([IM, os.path.join(SRC, master), "-strip", "-resize", f"{px}x{px}", *options,
                    f"{kind}{':' if kind else ''}{target(path)}"], check=True)


for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    put("android/ic_launcher_legacy_192.png", int(48 * scale), f"{RES}/mipmap-{density}/ic_launcher.png")
    for layer in ("background", "foreground", "monochrome"):
        put(f"android/ic_launcher_{layer}.png", int(108 * scale), f"{RES}/mipmap-{density}/ic_launcher_{layer}.png")
# Google Play asks for a 32-bit PNG.
put("android/play_store_512.png", 512, "android/app/src/main/play/listings/en-US/graphics/icon/icon.png", kind="PNG32")

for catalogue, master, kind in (("ios", "ios/AppIcon-1024.png", "PNG24"), ("macos", "desktop/macos-1024.png", "")):
    folder = f"{catalogue}/Runner/Assets.xcassets/AppIcon.appiconset"
    with open(os.path.join(APP, folder, "Contents.json"), encoding="utf-8") as handle:
        for image in json.load(handle)["images"]:
            px = int(float(image["size"].split("x")[0]) * int(image["scale"][0]))
            put(master, px, f"{folder}/{image['filename']}", kind=kind)

put("web/icon-192.png", 192, "web/icons/Icon-192.png")
put("web/icon-512.png", 512, "web/icons/Icon-512.png")
# Not the design's favicon.ico, whose 32 and 48 px are its 16 px upscaled.
put("web/icon-512.png", 512, "web/favicon.ico", "-define", "icon:auto-resize=48,32,16")
shutil.copyfile(os.path.join(SRC, "web/icon.svg"), target("web/icons/icon.svg"))
put("web/icon-512.png", 512, "windows/runner/resources/app_icon.ico", "-define", "icon:auto-resize=256,48,32,16")
for px in (48, 128, 256, 512):
    put("web/icon-512.png", px, f"{HICOLOR}/{px}x{px}/apps/org.photolib.photolib.png")
shutil.copyfile(os.path.join(SRC, "web/icon.svg"), target(f"{HICOLOR}/scalable/apps/org.photolib.photolib.svg"))
