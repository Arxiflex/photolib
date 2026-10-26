#!/usr/bin/env python3
"""The app icon on every platform (ADR-0312): no Flutter template icon is left under app/, and every platform holds
the mark at each size it asks for, as app/tool/icons.py writes it from photolib-design's docs/brand/icon/."""
import hashlib
import json
import os
import re
import struct
import subprocess
import xml.etree.ElementTree as ET

from checklib import ROOT, check, finish, read

# SHA-256 of every icon of Flutter 3.47.7's app and module templates (flutter_tools and flutter_template_images 5.0.0).
STOCK = {
    "0a91c6c1bf242e54ee179e34629e9ef3e8a6d286c0fce01e302280a8be9277e6",
    "15591f03f31313af6fd644ed0512106cc04365130b8b73244f1cfa6dddfb4400",
    "19be171481dc71a0b2803ebcd01dd8b0c5fd5778dee34c0a3cabc948c225f24e",
    "23c13d463f5dca5c1f14a14934003601c29f1218fd461016d8a22cef579a665f",
    "285442f69a06b45d9d79df80321815b546473548a37b78819b68959c7b8ed237",
    "2ab64af8ac727ea99c6ab9eaff847f46fbf2a9a0a78a0abcbf3180f3851645b4",
    "3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180",
    "3db08cb79e7b01b9e81f956e3a0ae10148d0fafde3ea7aa70048df905aa52cfd",
    "3dce99077602f70421c1c6b2a240bc9b83d64d86681d45f2154143310c980be3",
    "416efd77cde932d42ef34168da24dd428a495b1f4f34bbbd125a18d2add186a2",
    "41c7d42f6e61f8fe7f30b1ffa2256aecbc9682be06d18c4a3062043e1a2e547c",
    "4209a49e44a92ec40a327d3455eb1b1c153ee83d75de1c2be0a12ab18b2ff9de",
    "4d470bf22d5c17d84edc5f82516d1ba8a1c09559cd761cefb792f86d9f52b540",
    "5925dab509451f9ecbb12ce8a625f9d4c104718ee20caff8b1b51032d1cd8946",
    "5d7e5bdf01b93802bc973345b3a78c038907147625035952a08a115a563b7f81",
    "5dee24dc104ac76dc162e42ae0beb163d426bf365562ee28ba7b3ad368559a60",
    "6232e5815af17e25e0268b2fec7aea9e068cc92ec709e9605c2b31df4ff2a313",
    "6a7c8f0d703e3682108f9662f813302236240d3f8f638bb391e32bfb96055fef",
    "6ad229623498e5f1277800db3ab7cb11faf85eb2569e1213f7d8e55003c07b42",
    "6aee06cdcab6b2aef74b1734c4778f4421d2da100b0ff9e52b21b55240202929",
    "6db7726530d71d3f52cb59793eb691313baa04796e129e1e043c0a58a1bffd2f",
    "7770183009e914112de7d8ef1d235a6a30c5834424858e0d2f8253f6b8d31926",
    "7ab2525f4b86b65d3e4c70358a17e5a1aaf6f437f99cbcc046dad73d59bb9015",
    "7c61c42fc7b657d9cf314d32a4ec458f0647c3aaf360be1b9377857266ec2499",
    "809abfe75c440770c13c4e2e46d09603c22053e9d4e0e2275dcb9c1dcfbb2c75",
    "836c918cb613249eba0483a6b02fa3df3c1c0a89a315ee4d3b88509b83c7ab73",
    "9dca09f4e5ed5684d3c4dff41f4e8b7cb864b438172d72be069315fa362930f9",
    "a9b21eb6f4271385655a8771f76e29eef8c1107d7879cbcfc567e6619d1f716a",
    "ae8c4458e41f1e28b1e851ed87d3268d4a0351ceea427fa2a84cc94ddfb6d4c5",
    "b9ad02cf6576a04d1b6806ac02a2431481b448dd0c2e505ce25842d1f7c4730b",
    "baccb205ae45f0b421be1657259b4943ac40c95094ab877f3bcbe12cd544dcbe",
    "bf97f9d3233f33e1389b09f7b8add53741300cb834d6c7a5ca32cbed363a4fb2",
    "c098d3fc85cacff98b8e69811b48e9f0d852fcee278132d794411d978869cbf8",
    "c4d9a284c12301d0f50e248ec53ed51a19a10147b774b23308399250b0d44c55",
    "c6e6d3b215ae744a9c391f4c4d44157eff5e739d6ad6c39f9bfa5df66dddd267",
    "c7c0c0189145e4e32a401c61c9bdc615754b0264e7afae24e834bb81049eaf81",
    "cab10a0d391ec5bc09ef50ce49e8ad401cee7ef03707ec0923a222c5c2b3d212",
    "cc6928b5adfc00dbf526192e2705dd9af641cdf20ab4c6c7ca7cd4936dca59f0",
    "cee565f5e62116569b64980b209fd5ca4b3d3739011f5343250b33a1a2c6eb65",
    "d2c842e22a9f4ec9d996b23373a905c88d9a203b220c5c151885ad621f974b5c",
    "d5ad04de321ef37cacc5a7b960afcce71bdcb96fa020c48249c1545dd1a0f497",
    "e14aa40904929bf313fded22cf7e7ffcbf1d1aac4263b5ef1be8bfce650397aa",
    "e677d701ffe4af7bc2935098d6b3984cc9ab7ace573e6900955a5535b12410cf",
}


def raw(path):
    """The bytes of app/<path>, empty when it is missing."""
    try:
        with open(os.path.join(ROOT, "app", path), "rb") as handle:
            return handle.read()
    except OSError:
        return b""


def png(path):
    """(width, height, opaque) of the PNG at app/<path>, or None when it is missing or no PNG."""
    data = raw(path)
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height, _, colour = struct.unpack(">IIBB", data[16:26])
    chunks, at = set(), 8
    while at < len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        chunks.add(kind)
        at += length + 12
    return width, height, colour in (0, 2, 3) and b"tRNS" not in chunks


def ico(path):
    """The sizes an ICO at app/<path> holds."""
    data = raw(path)
    return sorted(data[6 + 16 * i] or 256 for i in range(struct.unpack("<3H", data[:6])[2])) if data else []


def sized(path, px, opaque=False):
    got = png(path)
    check(got is not None and got[:2] == (px, px) and (got[2] or not opaque),
          f"app/{path}: {px}x{px}{' and opaque' if opaque else ''}", f"app/{path}: {got}, not {px}x{px}")


listed = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=os.path.join(ROOT, "app"), check=True,
                        capture_output=True, text=True).stdout.split()
icons = [p for p in listed if p.endswith((".png", ".ico"))]
stock = [p for p in icons if hashlib.sha256(raw(p)).hexdigest() in STOCK]
check(not stock, f"none of the app's {len(icons)} PNG and ICO files is a Flutter template icon",
      f"Flutter's template icons: {stock}")

res = "android/app/src/main/res"
NS = "{http://schemas.android.com/apk/res/android}"
try:
    adaptive = ET.parse(os.path.join(ROOT, "app", res, "mipmap-anydpi-v26/ic_launcher.xml")).getroot()
    layers = {e.tag: e.get(f"{NS}drawable") for e in adaptive}
except (OSError, ET.ParseError):
    layers = {}
check(layers == {layer: f"@mipmap/ic_launcher_{layer}" for layer in ("background", "foreground", "monochrome")},
      "Android: an adaptive icon of background, foreground and monochrome layers", f"Android's layers: {layers}")
for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    sized(f"{res}/mipmap-{density}/ic_launcher.png", int(48 * scale))
    for layer in layers:
        sized(f"{res}/mipmap-{density}/ic_launcher_{layer}.png", int(108 * scale), opaque=layer == "background")

for catalogue, opaque in (("ios", True), ("macos", False)):
    folder = f"{catalogue}/Runner/Assets.xcassets/AppIcon.appiconset"
    images = json.loads(read(f"app/{folder}/Contents.json"))["images"]
    for name, px in sorted({(i["filename"], float(i["size"].split("x")[0]) * int(i["scale"][0])) for i in images}):
        sized(f"{folder}/{name}", int(px), opaque)

manifest = json.loads(read("app/web/manifest.json"))
purposes = set()
for icon in manifest["icons"]:
    px = int(icon["sizes"].split("x")[0])
    sized(f"web/{icon['src']}", px)
    purposes.add((icon.get("purpose", "any"), px))
check(purposes >= {(p, px) for p in ("any", "maskable") for px in (192, 512)},
      "the web manifest has the icon and a maskable icon at 192 and 512 px", f"the manifest's icons: {purposes}")
check(manifest["background_color"] == "#EEF3FF", "the installed web app's splash is the tile's colour, not Flutter's")
check('<link rel="icon" href="favicon.ico"' in read("app/web/index.html") and ico("web/favicon.ico") == [16, 32, 48],
      "the web app's favicon is favicon.ico at 16, 32 and 48 px")
check(ico("windows/runner/resources/app_icon.ico") == [16, 32, 48, 256], "Windows: app_icon.ico at 16, 32, 48, 256 px")

hicolor, LINUX = "linux/packaging/icons/hicolor", "org.photolib.photolib.png"
for px in (48, 128, 256, 512):
    sized(f"{hicolor}/{px}x{px}/apps/{LINUX}", px)
check(raw(f"{hicolor}/scalable/apps/org.photolib.photolib.svg").startswith(b"<svg"), "Linux: a scalable icon")
check(f'install(FILES "packaging/icons/hicolor/256x256/apps/{LINUX}"' in read("app/linux/CMakeLists.txt")
      and f'"{LINUX}", nullptr' in read("app/linux/runner/my_application.cc"),
      "Linux: the bundle holds the icon, which the window shows (checked as text)")
sized("android/app/src/main/play/listings/en-US/graphics/icon/icon.png", 512)
check(re.search(r"docs/brand/icon/.*tool/icons\.py", read("app/README.md").replace("\n", " ")),
      "app/README.md says where the icon comes from and how to regenerate it")
finish()
