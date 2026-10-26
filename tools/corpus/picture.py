"""The picture every decodable corpus image shows, and the lossless coders shared by its formats.

The picture is eight colour bars under a black band that carries the case name in white. Bar and band edges sit on
a 16-pixel grid, so block codecs code nearly all of it as flat blocks, and it compresses to almost nothing. The
name sits top left, so a flip or a rotation is visible. The bar order depends on the seed, so cases differ at a
glance.
"""
import hashlib
import zlib

BARS = [(192, 192, 192), (192, 192, 0), (0, 192, 192), (0, 192, 0), (192, 0, 192), (192, 0, 0), (0, 0, 192),
        (96, 96, 96)]
# 3 x 5 glyphs, one octal digit per row, left pixel = 4
FONT = dict(zip(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.()~@?/ ",
    ("25755 65656 34443 65556 74647 74644 34553 55755 72227 11152 55655 44447 57755 65555 25552 65644 25563 65655 "
     "34216 72222 55557 55552 55775 55255 55222 71247 75557 26227 61247 61216 55711 74616 34757 71222 75757 75716 "
     "00700 00007 00002 12221 42224 03600 25743 61202 11244 00000").split()))


def layout(label, width, height):
    """(scale, lines): the largest font scale at which the label, wrapped, fits the width and half the height;
    scales of 8 and more are multiples of 8, so the glyphs fill whole 8 x 8 blocks."""
    text = "".join(c if c in FONT else "?" for c in label.upper())
    for scale in range(max(1, width // 16), 0, -1):
        if scale >= 8 and scale % 8:
            continue
        per_line = (width - 2 * scale) // (4 * scale)
        if per_line >= 1:
            lines = [text[i:i + per_line] for i in range(0, len(text), per_line)]
            if (6 * len(lines) + 1) * scale <= height // 2:
                return scale, lines
    return 1, [text[:max(1, (width - 2) // 4)]]


def rows(seed, width, height, frame=0):
    """The picture as height rows of RGB bytes, equal rows being the same object. seed names the case: the name
    drawn is its last path part; frame shifts the bars, for animations."""
    scale, lines = layout(seed.rsplit("/", 1)[-1], width, height)
    shift = hashlib.sha256(seed.encode()).digest()[0] + frame
    edges = [i * width // 128 * 16 for i in range(8)] + [width]
    bars = b"".join(bytes(BARS[(shift + i) % 8]) * (edges[i + 1] - edges[i]) for i in range(8))
    band = min(height, -(-(6 * len(lines) + 1) * scale // 16) * 16)
    blank = bytes(3 * width)
    cache, out = {}, []
    for y in range(height):
        line, glyph_row = divmod((y - scale) // scale, 6)
        if y >= band:
            out.append(bars)
        elif y < scale or line >= len(lines) or glyph_row == 5:
            out.append(blank)
        else:
            if (line, glyph_row) not in cache:
                row = bytearray(blank)
                for index, char in enumerate(lines[line]):
                    bits = int(FONT[char][glyph_row])
                    for column in range(3):
                        if bits >> (2 - column) & 1:
                            x = (1 + 4 * index + column) * scale
                            row[3 * x:3 * (x + scale)] = b"\xff" * (3 * scale)
                cache[line, glyph_row] = bytes(row[:3 * width])
            out.append(cache[line, glyph_row])
    return out


def pixels(seed, width, height, frame=0):
    """The picture as one list of (r, g, b) tuples per row."""
    return [[tuple(row[i:i + 3]) for i in range(0, len(row), 3)] for row in rows(seed, width, height, frame)]


def grey(rgb):
    r, g, b = rgb
    return (19595 * r + 38470 * g + 7471 * b + 32768) >> 16


class Bits:
    """A bit writer that fills each byte from its least significant bit (deflate, GIF, VP8L)."""

    def __init__(self):
        self.out, self.acc, self.count = bytearray(), 0, 0

    def put(self, value, count):
        self.acc |= value << self.count
        self.count += count
        while self.count >= 8:
            self.out.append(self.acc & 255)
            self.acc >>= 8
            self.count -= 8

    def code(self, value, length):
        """A prefix code, which these formats store from its most significant bit."""
        self.put(int(f"{value:0{length}b}"[::-1], 2), length)

    def bytes(self):
        return bytes(self.out) + (bytes([self.acc]) if self.count else b"")


LENGTHS = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227,
           258]


def deflate(raw):
    """A zlib stream with fixed codes whose only matches repeat the previous byte: byte for byte reproducible on
    every platform (zlib's own output differs between builds), and runs of filtered pixels shrink to a few bits."""
    bits = Bits()
    bits.put(0b011, 3)

    def symbol(value):
        for top, base, length in ((143, 0x30, 8), (255, 0x190 - 144, 9), (279, -256, 7), (287, 0xC0 - 280, 8)):
            if value <= top:
                return bits.code(value + base, length)

    at = 0
    while at < len(raw):
        run = 0
        while at and run < 258 and at + run < len(raw) and raw[at + run] == raw[at - 1]:
            run += 1
        if run < 3:
            symbol(raw[at])
            at += 1
            continue
        index = max(i for i, base in enumerate(LENGTHS) if base <= run)
        symbol(257 + index)
        bits.put(run - LENGTHS[index], 0 if index == 28 else max(0, (index - 4) // 4))
        bits.code(0, 5)  # distance 1
        at += run
    symbol(256)
    return b"\x78\x01" + bits.bytes() + zlib.adler32(raw).to_bytes(4, "big")


def lzw(indices, minimum):
    """GIF LZW data for palette indices of minimum bits, with the code-width rules of a standard encoder."""
    clear, bits = 1 << minimum, Bits()
    width, hi, table = minimum + 1, clear + 1, {}

    def emit(code):
        """Writes a code and claims the next one; False when the table was full and has been cleared."""
        nonlocal width, hi, table
        bits.put(code, width)
        hi += 1
        if hi == 1 << width:
            width += 1
        if hi == 4095:
            bits.put(clear, width)
            width, hi, table = minimum + 1, clear + 1, {}
            return False
        return True

    bits.put(clear, width)
    code = indices[0]
    for index in indices[1:]:
        key = code << 8 | index
        if key in table:
            code = table[key]
            continue
        if emit(code):
            table[key] = hi
        code = index
    emit(code)
    bits.put(clear + 1, width)
    return bits.bytes()
