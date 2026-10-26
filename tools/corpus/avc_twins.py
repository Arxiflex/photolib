"""AVC-coded HEIF twins of the corpus' grid, clap, irot and imir HEIC files (M1-43).

Chrome decodes AVC in software on every platform and HEIF allows `avc1` items, so a twin lets the web part prove the
browser's HEIC path (WebCodecs, grid compositing, clap, irot, imir, the `thmb` shortcut) where HEVC is not decodable.
A twin has the layout an iPhone writes (tiles in a `grid` item, a `thmb` item) at a tenth of the size. Its tiles are
I_PCM macroblocks of one flat colour each, written by the encoder below, so the pictures are exact and the build
needs no codec. `twins.json` lists each twin with the colour it must show at probe points.
"""
import json
import struct

from containers import Heif, box, full

TILE = (128, 96)
THUMB = (96, 64)
BLOCK = 16
# name: (grid columns, rows, clap (width, height, x offset, y offset), irot quarter turns, imir axis); no grid: 1 x 1.
TWINS = {
    "grid": (2, 2, None, None, None),
    "clap": (2, 2, (224, 160, -8, 8), None, None),
    "irot": (2, 2, None, 3, None),
    "imir": (2, 2, None, None, 0),
    "all": (2, 2, (224, 160, -8, 8), 1, 1),
    "single": (1, 1, None, 1, None),
}


class Bits:
    def __init__(self):
        self.bits = []

    def u(self, n, value):
        self.bits += [(value >> i) & 1 for i in range(n - 1, -1, -1)]

    def ue(self, value):
        value += 1
        self.u(value.bit_length() - 1, 0)
        self.u(value.bit_length(), value)

    def se(self, value):
        self.ue(2 * value - 1 if value > 0 else -2 * value)

    def align(self):
        self.bits += [0] * (-len(self.bits) % 8)

    def trailing(self):
        self.bits.append(1)
        self.align()

    def bytes(self):
        return bytes(int("".join(map(str, self.bits[i:i + 8])), 2) for i in range(0, len(self.bits), 8))


def nal(kind, ref_idc, rbsp):
    """A NAL unit with emulation prevention bytes."""
    out = bytearray([(ref_idc << 5) | kind])
    zeros = 0
    for byte in rbsp:
        if zeros >= 2 and byte <= 3:
            out.append(3)
            zeros = 0
        out.append(byte)
        zeros = zeros + 1 if byte == 0 else 0
    return bytes(out)


def parameter_sets(width, height):
    """SPS and PPS NAL units of a constrained baseline stream of this size (multiples of 16): BT.709 primaries and
    matrix, sRGB transfer, limited range."""
    sps = Bits()
    sps.u(8, 66), sps.u(8, 0xC0), sps.u(8, 30)
    sps.ue(0), sps.ue(0), sps.ue(2), sps.ue(1), sps.u(1, 0)
    sps.ue(width // 16 - 1), sps.ue(height // 16 - 1)
    sps.u(1, 1), sps.u(1, 1), sps.u(1, 0)
    sps.u(1, 1)  # vui_parameters_present
    sps.u(1, 0), sps.u(1, 0)  # aspect ratio, overscan
    sps.u(1, 1), sps.u(3, 5), sps.u(1, 0), sps.u(1, 1), sps.u(8, 1), sps.u(8, 13), sps.u(8, 1)
    sps.u(1, 0), sps.u(1, 0), sps.u(1, 0), sps.u(1, 0), sps.u(1, 0), sps.u(1, 0), sps.u(1, 0)
    sps.trailing()
    pps = Bits()
    pps.ue(0), pps.ue(0), pps.u(1, 0), pps.u(1, 0), pps.ue(0), pps.ue(0), pps.ue(0), pps.u(1, 0), pps.u(2, 0)
    pps.se(0), pps.se(0), pps.se(0), pps.u(1, 1), pps.u(1, 0), pps.u(1, 0)
    pps.trailing()
    return nal(7, 3, sps.bytes()), nal(8, 3, pps.bytes())


def yuv(rgb):
    r, g, b = (c / 255 for c in rgb)
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    clamp = lambda v: max(1, min(254, round(v)))
    return clamp(16 + 219 * y), clamp(128 + 224 * (b - y) / 1.8556), clamp(128 + 224 * (r - y) / 1.5748)


def idr(width, height, colour):
    """The IDR slice of a picture whose macroblock (x, y) is I_PCM of colour(x, y), length-prefixed."""
    slice_ = Bits()
    slice_.ue(0), slice_.ue(7), slice_.ue(0), slice_.u(4, 0), slice_.ue(0), slice_.u(1, 0), slice_.u(1, 0)
    slice_.se(0), slice_.ue(1)
    for y in range(height // BLOCK):
        for x in range(width // BLOCK):
            slice_.ue(25)
            slice_.align()
            luma, cb, cr = yuv(colour(x, y))
            for sample in [luma] * 256 + [cb] * 64 + [cr] * 64:
                slice_.u(8, sample)
    slice_.trailing()
    data = nal(5, 3, slice_.bytes())
    return struct.pack(">I", len(data)) + data


def avcc(width, height):
    sps, pps = parameter_sets(width, height)
    head = bytes([1, 66, 0xC0, 30, 0xFF, 0xE1])
    return head + struct.pack(">H", len(sps)) + sps + b"\x01" + struct.pack(">H", len(pps)) + pps


def block_colour(columns, rows):
    """A colour for every block of a columns x rows picture, none like its neighbour's."""
    def colour(x, y):
        red, green = 40 + round(175 * x / max(1, columns - 1)), 40 + round(175 * y / max(1, rows - 1))
        # Blue between them: libyuv, which Chrome converts with, scales BT.709's blue difference by 2.0, not 2.112.
        return red, green, (red + green) // 2
    return colour


def shown(canvas, clap, rotation, mirror):
    """The size of the picture after clap, then irot and imir."""
    w, h = (clap[0], clap[1]) if clap else canvas
    return (h, w) if rotation and rotation % 2 else (w, h)


def source(canvas, clap, rotation, mirror, x, y):
    """Where the pixel shown at (x, y) is in the canvas: imir, irot, then clap undone (ISO/IEC 23008-12:2022
    6.5.10-12)."""
    cw, ch = (clap[0], clap[1]) if clap else canvas
    sw, sh = shown(canvas, clap, rotation, mirror)
    if mirror == 0:
        y = sh - 1 - y
    elif mirror == 1:
        x = sw - 1 - x
    k = rotation or 0
    if k == 1:
        x, y = cw - 1 - y, x
    elif k == 2:
        x, y = cw - 1 - x, ch - 1 - y
    elif k == 3:
        x, y = y, ch - 1 - x
    left = round(canvas[0] / 2 + (clap[2] if clap else 0) - cw / 2)
    top = round(canvas[1] / 2 + (clap[3] if clap else 0) - ch / 2)
    return left + x, top + y


def probes(canvas, clap, rotation, mirror, colour):
    """[x, y, rgb] on a 12 x 12 grid of cell centres of the shown picture where it is one flat colour 4 pixels
    around."""
    w, h = shown(canvas, clap, rotation, mirror)
    found = []
    for gy in range(1, 13):
        for gx in range(1, 13):
            x, y = w * (2 * gx - 1) // 24, h * (2 * gy - 1) // 24
            colours = set()
            for dx in (-4, 0, 4):
                for dy in (-4, 0, 4):
                    sx, sy = source(canvas, clap, rotation, mirror, x + dx, y + dy)
                    colours.add(colour(sx // BLOCK, sy // BLOCK))
            if len(colours) == 1:
                found.append([x, y, list(colours.pop())])
    return found


def twin(columns, rows, clap, rotation, mirror):
    """The file and its twins.json entry."""
    canvas = (columns * TILE[0], rows * TILE[1]) if columns * rows > 1 else (256, 192)
    table = Heif()
    transforms = []
    if rotation is not None:
        transforms.append(table.prop(box(b"irot", bytes([rotation]))))
    if mirror is not None:
        transforms.append(table.prop(box(b"imir", bytes([mirror]))))
    crop = []
    if clap:
        crop = [table.prop(box(b"clap", struct.pack(">IIIIiIiI", clap[0], 1, clap[1], 1, clap[2], 1, clap[3], 1)))]

    def coded(size, colour, props, hidden=True):
        config = table.prop(box(b"avcC", avcc(*size)))
        ispe = table.prop(full(b"ispe", struct.pack(">II", *size)))
        return table.item(b"avc1", idr(*size, colour), [ispe, config, *props], hidden=hidden)

    blocks = (canvas[0] // BLOCK, canvas[1] // BLOCK)
    colour = block_colour(*blocks)
    if columns * rows > 1:
        tiles = []
        for r in range(rows):
            for c in range(columns):
                bx, by = c * TILE[0] // BLOCK, r * TILE[1] // BLOCK
                tiles.append(coded(TILE, lambda x, y, bx=bx, by=by: colour(bx + x, by + y), []))
        ispe = table.prop(full(b"ispe", struct.pack(">II", *canvas)))
        descriptor = struct.pack(">BBBBHH", 0, 0, rows - 1, columns - 1, *canvas)
        first = table.item(b"grid", descriptor, [ispe, *crop, *transforms])
        table.ref(b"dimg", first, tiles)
    else:
        first = coded(canvas, colour, [*crop, *transforms], hidden=False)
    thumb_blocks = (THUMB[0] // BLOCK, THUMB[1] // BLOCK)
    thumb_colour = block_colour(*thumb_blocks)
    thumb = coded(THUMB, thumb_colour, transforms)
    table.ref(b"thmb", thumb, [first])
    table.primary = first
    thumb_shown = shown(THUMB, None, rotation, mirror)
    entry = {
        "canvas": list(canvas), "tile": list(TILE) if columns * rows > 1 else None, "grid": [columns, rows],
        "clap": list(clap) if clap else None, "rotation": rotation, "mirror": mirror,
        "shown": list(shown(canvas, clap, rotation, mirror)),
        "probes": probes(canvas, clap, rotation, mirror, colour),
        "thumb": {"size": list(THUMB), "shown": list(thumb_shown),
                  "probes": probes(THUMB, None, rotation, mirror, thumb_colour)},
    }
    return table.build(b"heic", (b"mif1", b"heic")), entry


def render():
    """{path relative to testdata/corpus: bytes} of every twin and twins.json."""
    out, listing = {}, {}
    for name, spec in TWINS.items():
        data, entry = twin(*spec)
        out[f"twins/heif-avc/{name}.heic"] = data
        listing[f"{name}.heic"] = {**entry, "bytes": len(data)}
    out["twins/heif-avc/twins.json"] = (json.dumps(listing, indent=1) + "\n").encode()
    return out
