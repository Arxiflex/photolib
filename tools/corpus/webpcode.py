"""WebP bitstreams of the corpus picture: VP8 (lossy) and VP8L (lossless), in integer arithmetic only.

VP8 codes every macroblock in DC prediction at quantiser index 0 (step 4) without a loop filter, tracking the
decoder's reconstruction exactly. VP8L codes literal pixels with fixed-length prefix codes and
copies runs from the pixel above or to the left.
"""
import picture

# Token update and default token probabilities, [type 4][band 8][context 3][node 11], from RFC 6386 sections 13.4
# and 13.5 (VP8 Data Format and Decoding Guide).
UPDATE = bytes.fromhex(
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0f6ffffffffffffffffffdff1fcfffffffffffffffff9"
    "fdfdfffffffffffffffffff4fcffffffffffffffffeafefefffffffffffffffffdfffffffffffffffffffffff6feffffffffffffffffeffd"
    "fefffffffffffffffffefffefffffffffffffffffff8fefffffffffffffffffbfffefffffffffffffffffffffffffffffffffffffffffdfe"
    "fffffffffffffffffbfefefffffffffffffffffefffefffffffffffffffffffefdfffefffffffffffffafffefffefffffffffffffeffffff"
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd9ffffffffffffffffffffe1fcf1fdff"
    "fffeffffffffeafaf1fafdfffdfefffffffffeffffffffffffffffffdffefeffffffffffffffffeefdfefefffffffffffffffff8feffffff"
    "fffffffffff9fefffffffffffffffffffffffffffffffffffffffffffdfffffffffffffffffff7feffffffffffffffffffffffffffffffff"
    "fffffffffffdfefffffffffffffffffcfffffffffffffffffffffffffffffffffffffffffffffefefffffffffffffffffdffffffffffffff"
    "fffffffffffffffffffffffffffffffefdfffffffffffffffffafffffffffffffffffffffeffffffffffffffffffffffffffffffffffffff"
    "ffffffffffffffffffffffffffffffffffffffffffffffffbafbfaffffffffffffffffeafbf4fefffffffffffffffbfbf3fdfefffeffffff"
    "fffffdfeffffffffffffffffecfdfefffffffffffffffffbfdfdfefefffffffffffffffefefffffffffffffffffefefeffffffffffffffff"
    "fffffffffffffffffffffffffefffffffffffffffffffefefffffffffffffffffffefffffffffffffffffffffffffffffffffffffffffffe"
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    "fffffffffffffffff8fffffffffffffffffffffafefcfefffffffffffffff8fef9fdfffffffffffffffffdfdfffffffffffffffff6fdfdff"
    "fffffffffffffffcfefbfefefffffffffffffffefcfffffffffffffffff8fefdfffffffffffffffffdfffefefffffffffffffffffbfeffff"
    "fffffffffffff5fbfefffffffffffffffffdfdfefffffffffffffffffffbfdfffffffffffffffffcfdfefffffffffffffffffffeffffffff"
    "fffffffffffffcfffffffffffffffffff9fffefffffffffffffffffffffefffffffffffffffffffffdfffffffffffffffffaffffffffffff"
    "fffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffffffffffffffffffffffffffffffffffffff")
DEFAULT = bytes.fromhex(
    "808080808080808080808080808080808080808080808080808080808080808080fd88feffe4db8080808080bd81f2ffe3d5ffdb8080806a"
    "7ee3fcd6d1ffff8080800162f8ffece2ffff808080b585eefeddeaff9a8080804e86caf7c6b4ffdb80808001b9f9fff3ff8080808080b896"
    "f7ffece080808080804d6ed8ffece680808080800165fbfff1ff8080808080aa8bf1fcecd1ffff8080802574c4f3e4ffffff80808001ccfe"
    "fff5ff8080808080cfa0faffee8080808080806667e7ffd3ab80808080800198fcfff0ff8080808080b187f3ffeae180808080805081d3ff"
    "c2e080808080800101ff8080808080808080f601ff8080808080808080ff80808080808080808080c623eddfc1bba2a0919b3e832dc6ddac"
    "b0dc9dfcdd01442f92d095a7dda2ffdf800195f1ffdde0ffff808080b88deafddedcffc78080805163b5f2b0bef9caffff800181e8fdd6c5"
    "f2c4ffff806379d2fac9c6ffca808080175ba3f2aabbf7d2ffff8001c8f6ffeaff80808080806db2f1ffe7f5ffff8080802c82c9fdcdc0ff"
    "ff8080800184effbdbd1ffa58080805e88e1fbdabeffff8080801664aef5baa1ffc780808001b6f9ffe8eb80808080807c8ff1ffe3ea8080"
    "808080234db5fbc1d3ffcd808080019df7ffece7ffff808080798debffe1e3ffff8080802d63bcfbc3d9ffe08080800101fbffd5ff808080"
    "8080cb01f8ffff8080808080808901b1ffe0ff8080808080fd09f8fbcfd0ffc0808080af0de0f3c1b9f9c6ffff804911abdda1b3eca7ffea"
    "80015ff7fdd4b7ffff808080ef5af4fad3d1ffff8080809b4dc3f8bcc3ffff8080800118effbdadbffcd808080c933dbffc4ba8080808080"
    "452ebeefc9daffe480808001bffbffff808080808080dfa5f9ffd5ff80808080808d7cf8ffff8080808080800110f8ffff808080808080be"
    "24e6ffecff80808080809501ff808080808080808001e2ff8080808080808080f7c0ff8080808080808080f080ff80808080808080800186"
    "fcffff808080808080d53efaffff808080808080375dff808080808080808080808080808080808080808080808080808080808080808080"
    "8080808080808080ca18d5ebbabfdca0f0afff7e26b6e8a9b8e4aeffbb803d2e8adb97b2f0aaffd8800170e6fac7bff79fffff80a66de4fc"
    "d3d7ffae808080274da2e8acb4f5b2ffff800134dcf6c6c7f9dcffff807c4abff3b7c1faddffff80184782db9aaaf3b6ffff8001b6e1f9db"
    "f0ffe08080809596e2fcd8cdffab8080801c6caaf2b7c2fedfffff800151e6fccccbffc08080807b66d1f7bcc4ffe9808080145f99f3a4ad"
    "ffcb80808001def8ffd8d58080808080a8aff6fcebcdffff8080802f74d7ffd3d4ffff8080800179ecfdd4d6ffff8080808d54d5fcc9caff"
    "db8080802a50a0f0a2b9ffcd8080800101ff8080808080808080f401ff8080808080808080ee01ff8080808080808080")
BANDS = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7]
ZIGZAG = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15]
CATEGORIES = ((11, (173, 148, 140)), (19, (176, 155, 140, 135)), (35, (180, 157, 141, 134, 130)),
              (67, (254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129)))
Y2, CHROMA, Y_AFTER_Y2 = 1, 2, 0
SIGNS = [[1, 1, 1, 1], [1, 1, -1, -1], [1, -1, -1, 1], [1, -1, 1, -1]]  # the Walsh-Hadamard butterfly, symmetric
DCT = [[2048, 2048, 2048, 2048], [2676, 1108, -1108, -2676], [2048, -2048, -2048, 2048], [1108, -2676, 2676, -1108]]


class BoolEncoder:
    """The boolean entropy encoder of RFC 6386 section 7.3."""

    def __init__(self):
        self.out, self.range, self.bottom, self.bit_count = bytearray(), 255, 0, 24

    def carry(self):
        at = len(self.out) - 1
        while self.out[at] == 255:
            self.out[at] = 0
            at -= 1
        self.out[at] += 1

    def put(self, probability, bit):
        split = 1 + (((self.range - 1) * probability) >> 8)
        if bit:
            self.bottom += split
            self.range -= split
        else:
            self.range = split
        while self.range < 128:
            self.range <<= 1
            if self.bottom & (1 << 31):
                self.carry()
            self.bottom = (self.bottom << 1) & 0xFFFFFFFF
            self.bit_count -= 1
            if not self.bit_count:
                self.out.append(self.bottom >> 24)
                self.bottom &= (1 << 24) - 1
                self.bit_count = 8

    def literal(self, value, count):
        for shift in reversed(range(count)):
            self.put(128, value >> shift & 1)

    def bytes(self):
        if self.bottom & (1 << (32 - self.bit_count)):
            self.carry()
        value = (self.bottom << (self.bit_count & 7)) << 8 * (self.bit_count >> 3) & 0xFFFFFFFF
        return bytes(self.out) + value.to_bytes(4, "big")


def tokens(coder, kind, levels, context):
    """One block's coefficients (natural order) as tokens; returns whether any is non-zero."""
    first = 1 if kind == Y_AFTER_Y2 else 0
    last = max((i for i in range(first, 16) if levels[ZIGZAG[i]]), default=-1)
    after_zero = False
    for i in range(first, 16):
        p = DEFAULT[((kind * 8 + BANDS[i]) * 3 + context) * 11:][:11]
        if not after_zero:
            coder.put(p[0], i <= last)
            if i > last:
                return last >= 0
        v = levels[ZIGZAG[i]]
        coder.put(p[1], v != 0)
        after_zero, context = v == 0, min(abs(v), 2)
        if not v:
            continue
        size = abs(v)
        coder.put(p[2], size > 1)
        if size == 1:
            pass
        elif size <= 4:
            coder.put(p[3], 0)
            coder.put(p[4], size > 2)
            if size > 2:
                coder.put(p[5], size == 4)
        elif size <= 10:
            coder.put(p[3], 1)
            coder.put(p[6], 0)
            coder.put(p[7], size > 6)
            if size <= 6:
                coder.put(159, size - 5)
            else:
                coder.put(165, (size - 7) >> 1)
                coder.put(145, (size - 7) & 1)
        else:
            category = sum(size >= base for base, _ in CATEGORIES) - 1
            base, probabilities = CATEGORIES[category]
            for probability, bit in ((p[3], 1), (p[6], 1), (p[8], category >> 1), (p[9 + (category >> 1)], category & 1)):
                coder.put(probability, bit)
            for index, probability in enumerate(probabilities):
                coder.put(probability, (size - base) >> (len(probabilities) - 1 - index) & 1)
        coder.put(128, v < 0)
    return True


def iwht(levels):
    """The decoder's inverse Walsh-Hadamard transform of dequantised Y2 coefficients (RFC 6386 section 14.3)."""
    tmp = [0] * 16
    for i in range(4):
        a, b = levels[i] + levels[12 + i], levels[4 + i] + levels[8 + i]
        c, d = levels[4 + i] - levels[8 + i], levels[i] - levels[12 + i]
        tmp[i], tmp[4 + i], tmp[8 + i], tmp[12 + i] = a + b, c + d, a - b, d - c
    out = []
    for i in range(0, 16, 4):
        a, b = tmp[i] + tmp[i + 3], tmp[i + 1] + tmp[i + 2]
        c, d = tmp[i + 1] - tmp[i + 2], tmp[i] - tmp[i + 3]
        out += [(a + b + 3) >> 3, (c + d + 3) >> 3, (a - b + 3) >> 3, (d - c + 3) >> 3]
    return out


def idct(coefficients):
    """The decoder's inverse DCT of 16 dequantised coefficients (RFC 6386 section 14.4)."""

    def butterfly(a, b, c, d):
        return a + c, a - c, (b * 35468 >> 16) - (d + (d * 20091 >> 16)), b + (b * 20091 >> 16) + (d * 35468 >> 16)

    tmp = [0] * 16
    for i in range(4):
        a1, b1, c1, d1 = butterfly(*(coefficients[i + 4 * k] for k in range(4)))
        tmp[i], tmp[4 + i], tmp[8 + i], tmp[12 + i] = a1 + d1, b1 + c1, b1 - c1, a1 - d1
    out = []
    for i in range(0, 16, 4):
        a1, b1, c1, d1 = butterfly(*tmp[i:i + 4])
        out += [(a1 + d1 + 4) >> 3, (b1 + c1 + 4) >> 3, (b1 - c1 + 4) >> 3, (a1 - d1 + 4) >> 3]
    return out


def fdct(residual):
    """Twice the unitary 4 x 4 DCT, the scale the decoder's inverse expects, in fixed point."""
    rows = [[sum(c * v for c, v in zip(DCT[u], residual[4 * y:4 * y + 4])) for u in range(4)] for y in range(4)]
    return [(sum(DCT[v][y] * rows[y][u] for y in range(4)) + (1 << 22)) >> 23 for v in range(4) for u in range(4)]


def divide(value, step):
    """value / step rounded half away from zero."""
    return (abs(value) + step // 2) // step * (1 if value >= 0 else -1)


def padded(plane, height, width):
    return [[plane[min(y, len(plane) - 1)][min(x, len(plane[0]) - 1)] for x in range(width)] for y in range(height)]


def predict(rec, top, left, size):
    """16 x 16 or 8 x 8 DC prediction from the reconstructed row above and column to the left."""
    above = sum(rec[top - 1][left:left + size]) if top else None
    beside = sum(rec[y][left - 1] for y in range(top, top + size)) if left else None
    shift = size.bit_length() - 1
    if above is None and beside is None:
        return 128
    if above is None or beside is None:
        return ((above if beside is None else beside) + (size >> 1)) >> shift
    return (above + beside + size) >> shift + 1


def vp8(image):
    """A VP8 key frame of rows of (r, g, b) pixels: 16 x 16 and chroma DC prediction for every macroblock."""
    height, width = len(image), len(image[0])
    mbw, mbh = -(-width // 16), -(-height // 16)
    luma = [[(16839 * r + 33059 * g + 6420 * b + 1081344) >> 16 for r, g, b in line] for line in image]
    chroma = [[[(sum(image[min(y + i, height - 1)][min(x + j, width - 1)][k] * m for i in (0, 1) for j in (0, 1)
                     for k, m in enumerate(weights)) + (128 << 18) + (1 << 17)) >> 18
                for x in range(0, width, 2)] for y in range(0, height, 2)]
              for weights in ((-9719, -19081, 28800), (28800, -24116, -4684))]
    target = [padded(luma, 16 * mbh, 16 * mbw)] + [padded(plane, 8 * mbh, 8 * mbw) for plane in chroma]
    rec = [[[0] * len(plane[0]) for _ in plane] for plane in target]
    header, residue = BoolEncoder(), BoolEncoder()
    for value, count in ((0, 2), (0, 1), (0, 1), (0, 6), (0, 3), (0, 1), (0, 2), (0, 7), (0, 5), (0, 1)):
        header.literal(value, count)  # colour space, clamping, segmentation, filter type, level, sharpness, filter
        # deltas, partitions, quantiser index 0 (DC 4, AC 4, Y2 8, chroma DC 4), no quantiser deltas, refresh probs
    for probability in UPDATE:
        header.put(probability, 0)
    header.literal(0, 1)  # every macroblock codes its tokens: no skip flag
    above = [[0] * mbw, [0] * (4 * mbw), [0] * (2 * mbw), [0] * (2 * mbw)]  # Y2, Y, U, V non-zero flags

    def block(plane, top, left, base):
        return fdct([target[plane][top + i // 4][left + i % 4] - base for i in range(16)])

    def put(plane, top, left, base, coefficients):
        for i, value in enumerate(idct(coefficients)):
            rec[plane][top + i // 4][left + i % 4] = max(0, min(255, base + value))

    for my in range(mbh):
        left = [[0], [0] * 4, [0] * 2, [0] * 2]
        for mx in range(mbw):
            for probability, bit in ((145, 1), (156, 0), (163, 0), (142, 0)):  # 16 x 16 DC_PRED, chroma DC_PRED
                header.put(probability, bit)
            base = predict(rec[0], 16 * my, 16 * mx, 16)
            blocks = [block(0, 16 * my + 4 * (b // 4), 16 * mx + 4 * (b % 4), base) for b in range(16)]
            # Y2 levels S D S / 16 for the block DCs D, so that the decoder's (S (8 levels) S + 3) >> 3 gives D
            sd = [[sum(SIGNS[u][k] * blocks[4 * k + c][0] for k in range(4)) for c in range(4)] for u in range(4)]
            y2 = [divide(sum(sd[u][c] * SIGNS[v][c] for c in range(4)), 16) for u in range(4) for v in range(4)]
            left[0][0] = above[0][mx] = tokens(residue, Y2, y2, left[0][0] + above[0][mx])
            for b, dc in enumerate(iwht([8 * level for level in y2])):
                levels = [0] + [divide(value, 4) for value in blocks[b][1:]]
                row, column = b // 4, 4 * mx + b % 4
                left[1][row] = above[1][column] = tokens(residue, Y_AFTER_Y2, levels, left[1][row] + above[1][column])
                put(0, 16 * my + 4 * row, 16 * mx + 4 * (b % 4), base, [dc] + [4 * level for level in levels[1:]])
            for plane in (1, 2):
                base = predict(rec[plane], 8 * my, 8 * mx, 8)
                for b in range(4):
                    top, start = 8 * my + 4 * (b // 2), 8 * mx + 4 * (b % 2)
                    levels = [divide(value, 4) for value in block(plane, top, start, base)]
                    row, column = b // 2, 2 * mx + b % 2
                    nz = tokens(residue, CHROMA, levels, left[plane + 1][row] + above[plane + 1][column])
                    left[plane + 1][row] = above[plane + 1][column] = nz
                    put(plane, top, start, base, [4 * level for level in levels])
    first = header.bytes()
    tag = (1 << 4 | len(first) << 5).to_bytes(3, "little")
    return tag + b"\x9d\x01\x2a" + width.to_bytes(2, "little") + height.to_bytes(2, "little") + first + residue.bytes()


def prefix(value):
    """VP8L prefix code of a length or distance value: (symbol, extra bit count, extra bits)."""
    if value <= 4:
        return value - 1, 0, 0
    high = (value - 1).bit_length() - 1
    second = (value - 1) >> (high - 1) & 1
    return 2 * high + second, high - 1, (value - 1) & ((1 << (high - 1)) - 1)


def normal_code(bits, lengths):
    """A normal prefix code whose lengths take only one or two values, each given a 1-bit code length code."""
    used = sorted(set(lengths))
    order = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    count = max(order.index(length) for length in used) + 1
    bits.put(0, 1)
    bits.put(count - 4, 4)
    for symbol in order[:count]:
        bits.put(1 if symbol in used else 0, 3)
    bits.put(0, 1)
    if len(used) == 2:
        for length in lengths:
            bits.put(used.index(length), 1)
    codes, code = [], 0
    for length in range(1, 16):
        for symbol, size in enumerate(lengths):
            if size == length:
                codes.append((symbol, code, length))
                code += 1
        code <<= 1
    return {symbol: (code, length) for symbol, code, length in codes}


def vp8l(image):
    """A VP8L image without transforms: literal green 8 or 9 bits, red and blue 8, opaque alpha 0; runs copy the
    pixel above (distance code 1) or to the left (distance code 2)."""
    height, width = len(image), len(image[0])
    bits = picture.Bits()
    for value, count in ((0x2F, 8), (width - 1, 14), (height - 1, 14), (0, 1), (0, 3), (0, 1), (0, 1), (0, 1)):
        bits.put(value, count)  # signature, size, no alpha, version, no transform, no colour cache, one code group
    green = normal_code(bits, [8] * 232 + [9] * 48)
    red = normal_code(bits, [8] * 256)
    blue = normal_code(bits, [8] * 256)
    for value, count in ((1, 1), (0, 1), (1, 1), (255, 8), (1, 1), (1, 1), (0, 1), (0, 1), (1, 8)):
        bits.put(value, count)  # alpha: one symbol, 255; distance: two symbols, 0 (code 1) and 1 (code 2)
    pixels = [rgb for line in image for rgb in line]
    at = 0
    while at < len(pixels):
        best = (0, 0)
        for distance, code in ((width, 0), (1, 1)):
            if at >= distance:
                run = 0
                while run < 4096 and at + run < len(pixels) and pixels[at + run] == pixels[at + run - distance]:
                    run += 1
                best = max(best, (run, code))
        if best[0] >= 2:
            symbol, extra, value = prefix(best[0])
            bits.code(*green[256 + symbol])
            bits.put(value, extra)
            bits.code(best[1], 1)
            at += best[0]
        else:
            r, g, b = pixels[at]
            bits.code(*green[g])
            bits.code(*red[r])
            bits.code(*blue[b])
            at += 1
    return bits.bytes()
