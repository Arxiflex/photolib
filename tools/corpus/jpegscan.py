"""JPEG scans of the corpus picture: 4:2:0 YCbCr (or Adobe YCCK), one flat quantiser, and Huffman tables that give
a flat block two bits. Baseline restarts every MCU row, so equal rows are coded once; that keeps camera-sized
pictures fast to build and a few hundred kB at most. Integer arithmetic only, so the bytes never vary by platform.
"""
import math

import picture

QUANT = 8  # one step everywhere: a flat block's DC level is exactly its level-shifted value
ZIGZAG = [y * 8 + x for _, _, y, x in sorted((x + y, y if (x + y) % 2 else x, y, x) for y in range(8) for x in range(8))]
COS = [[round((math.sqrt(0.5) if u == 0 else 1) * math.cos((2 * x + 1) * u * math.pi / 16) * 4096) for x in range(8)]
       for u in range(8)]  # C(u) / 2 * cos(...) in units of 2 ** -13


def huffman(symbols, long):
    """Canonical codes: the first symbol gets '0', the others `long` bits. Returns (codes, DHT counts + symbols)."""
    codes = {symbols[0]: "0"}
    codes.update((symbol, format((1 << (long - 1)) + i, f"0{long}b")) for i, symbol in enumerate(symbols[1:]))
    counts = [0] * 16
    counts[0], counts[long - 1] = 1, len(symbols) - 1
    return codes, bytes(counts) + bytes(symbols)


DC, DC_TABLE = huffman(list(range(12)), 5)
AC, AC_TABLE = huffman([0x00, 0xF0] + [r << 4 | s for r in range(16) for s in range(1, 11)]
                       + [r << 4 for r in range(1, 15)], 9)
TABLES = b"\x00" + DC_TABLE + b"\x10" + AC_TABLE  # DHT payload: DC table 0, AC table 0, shared by every component
QUANT_TABLE = b"\x00" + bytes([QUANT]) * 64


def value(v):
    """Category bits of a coefficient: positive as is, negative as its ones' complement."""
    size = abs(v).bit_length()
    return format(v if v >= 0 else v + (1 << size) - 1, f"0{size}b") if size else ""


def ycc(r, g, b):
    return ((19595 * r + 38470 * g + 7471 * b + 32768) >> 16,
            (-11059 * r - 21709 * g + 32768 * b + 8421375) >> 16,
            (32768 * r - 27439 * g - 5329 * b + 8421375) >> 16)


def fdct(samples):
    """Quantised coefficients (natural order) of 64 level-shifted samples, or the level itself for a flat block."""
    if samples.count(samples[0]) == 64:
        return samples[0]
    rows = [[sum(c * s for c, s in zip(COS[u], samples[8 * y:8 * y + 8])) for u in range(8)] for y in range(8)]
    return tuple((sum(COS[v][y] * rows[y][u] for y in range(8)) + (1 << 28)) >> 29 for v in range(8) for u in range(8))


class Encoder:
    def __init__(self, seed, width, height, components):
        self.width, self.height, self.components = width, height, components
        self.mcux, self.mcuy = -(-width // 16), -(-height // 16)
        self.colours, self.blocks, self.rows = {}, {}, {}
        self.layout = [0, 0, 0, 0] + list(range(1, components))  # component of each block in an MCU
        self.header = bytes([components]) + b"".join(bytes([c + 1, 0]) for c in range(components))
        rows = picture.rows(seed, width, height)
        padded = {}
        for row in rows:
            padded.setdefault(id(row), row + row[-3:] * (16 * self.mcux - width))
        self.bands = [tuple(padded[id(rows[min(y, height - 1)])] for y in range(16 * my, 16 * my + 16))
                      for my in range(self.mcuy)]

    def levels(self, rgb):
        """Level-shifted component values of one pixel; YCCK codes inverted RGB and a constant K."""
        if self.components == 4:
            return [v - 128 for v in ycc(*(255 - c for c in rgb))] + [127]
        return [v - 128 for v in ycc(*rgb)]

    def mcu(self, band, at):
        first = band[0][at:at + 48]
        if first == first[:3] * 16 and all(row is band[0] or row[at:at + 48] == first for row in band):
            if first[:3] not in self.colours:
                level = self.levels(first[:3])
                self.colours[first[:3]] = tuple(level[:1] * 4 + level[1:])
            return self.colours[first[:3]]
        planes = [[self.levels(row[at + 3 * x:at + 3 * x + 3]) for x in range(16)] for row in band]
        out = []
        for top, left in ((0, 0), (0, 8), (8, 0), (8, 8)):
            out.append([planes[top + y][left + x][0] for y in range(8) for x in range(8)])
        for c in range(1, self.components):
            out.append([(sum(planes[2 * y + i][2 * x + j][c] for i in (0, 1) for j in (0, 1)) + 2) >> 2
                        for y in range(8) for x in range(8)])
        for index, samples in enumerate(out):
            key = tuple(samples)
            if key not in self.blocks:
                self.blocks[key] = fdct(samples)
            out[index] = self.blocks[key]
        return tuple(out)

    def mcu_row(self, band):
        key = tuple(map(id, band))
        if key not in self.rows:
            self.rows[key] = [self.mcu(band, 48 * mx) for mx in range(self.mcux)]
        return self.rows[key]

    def baseline(self):
        """One scan, a restart marker after every MCU row."""
        coded, out = {}, []
        for my, band in enumerate(self.bands):
            key = tuple(map(id, band))
            if key not in coded:
                bits, last = [], [0] * self.components
                for mcu in self.mcu_row(band):
                    for component, block in zip(self.layout, mcu):
                        bits.append(dc(block, last, component) + ac(block))
                coded[key] = pack("".join(bits))
            out.append(coded[key] + (b"\xff" + bytes([0xD0 + my % 8]) if my < self.mcuy - 1 else b""))
        return [(self.header + b"\x00\x3f\x00", b"".join(out))]

    def progressive(self):
        """Spectral selection: every DC coefficient in one interleaved scan, then each component's AC band."""
        mcus = [mcu for band in self.bands for mcu in self.mcu_row(band)]
        last, bits = [0] * self.components, []
        for mcu in mcus:
            bits += [dc(block, last, component) for component, block in zip(self.layout, mcu)]
        scans = [(self.header + b"\x00\x00\x00", pack("".join(bits)))]
        for component in range(self.components):
            if component == 0:
                columns, lines = -(-self.width // 8), -(-self.height // 8)
                blocks = (mcus[by // 2 * self.mcux + bx // 2][by % 2 * 2 + bx % 2]
                          for by in range(lines) for bx in range(columns))
            else:
                columns, lines = -(-self.width // 16), -(-self.height // 16)
                blocks = (mcus[by * self.mcux + bx][3 + component] for by in range(lines) for bx in range(columns))
            scans.append((bytes([1, component + 1, 0, 1, 63, 0]), pack(ac_band(blocks))))
        return scans


def dc(block, last, component):
    """A DC difference against the component's last DC level, which it updates."""
    level = block if isinstance(block, int) else block[0]
    diff, last[component] = level - last[component], level
    return DC[abs(diff).bit_length()] + value(diff)


def run_lengths(block):
    """The (zero run, value) pairs of a block's AC coefficients, and whether zeros follow the last pair."""
    if isinstance(block, int):
        return [], True
    pairs, run = [], 0
    for k in range(1, 64):
        v = block[ZIGZAG[k]]
        if v:
            pairs.append((run, v))
            run = 0
        else:
            run += 1
    return pairs, run > 0


def coded(pairs):
    out = []
    for run, v in pairs:
        out += [AC[0xF0]] * (run // 16) + [AC[run % 16 << 4 | abs(v).bit_length()] + value(v)]
    return "".join(out)


def ac(block):
    pairs, tail = run_lengths(block)
    return coded(pairs) + (AC[0] if tail else "")


def ac_band(blocks):
    """A progressive first AC scan (Ss 1, Se 63, no approximation): block tails of zeros merge into EOB runs."""
    out, eob = [], 0
    for block in blocks:
        pairs, tail = run_lengths(block)
        if pairs or eob == 0x7FFF:
            if eob:
                size = eob.bit_length() - 1
                out.append(AC[size << 4] + (format(eob - (1 << size), f"0{size}b") if size else ""))
            out.append(coded(pairs))
            eob = 0
        eob += 1 if tail else 0
    if eob:
        size = eob.bit_length() - 1
        out.append(AC[size << 4] + (format(eob - (1 << size), f"0{size}b") if size else ""))
    return "".join(out)


def pack(bits):
    """Entropy-coded bytes: padded with ones, every 0xFF stuffed with a zero byte."""
    bits += "1" * (-len(bits) % 8)
    return int(bits, 2).to_bytes(len(bits) // 8, "big").replace(b"\xff", b"\xff\x00") if bits else b""


def scans(seed, width, height, *, components=3, progressive=False):
    """[(SOS header, entropy-coded data)] and the restart interval (0 for none)."""
    encoder = Encoder(seed, width, height, components)
    return (encoder.progressive(), 0) if progressive else (encoder.baseline(), encoder.mcux)
