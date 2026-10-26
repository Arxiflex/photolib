"""TIFF and EXIF writer: enough real structure for a parser to find tags where a camera puts them."""
import struct

BYTE, ASCII, SHORT, LONG, RATIONAL, UNDEFINED, SLONG, SRATIONAL = 1, 2, 3, 4, 5, 7, 9, 10
PACK = {BYTE: "B", SHORT: "H", LONG: "I", SLONG: "i"}


class Ifd:
    """entries: (tag, type, value); subs: tag -> Ifd stored behind a pointer; dangling: tag -> bogus pointer value."""

    def __init__(self, entries=(), subs=None, next_ifd=None, dangling=None):
        self.entries = list(entries)
        self.subs = subs or {}
        self.next_ifd = next_ifd
        self.dangling = dangling or {}


def encode_value(kind, value, e):
    if kind == ASCII:
        raw = value.encode("latin-1") + b"\0"
        return len(raw), raw
    if kind == UNDEFINED:
        return len(value), value
    values = value if isinstance(value, list) else [value]
    if kind in (RATIONAL, SRATIONAL):
        letter = "I" if kind == RATIONAL else "i"
        return len(values), b"".join(struct.pack(e + letter * 2, *pair) for pair in values)
    return len(values), b"".join(struct.pack(e + PACK[kind], item) for item in values)


def encode(ifd, at, e):
    items = [[tag, kind, *encode_value(kind, value, e)] for tag, kind, value in ifd.entries]
    items += [[tag, LONG, 1, None] for tag in list(ifd.subs) + list(ifd.dangling)]
    items.sort(key=lambda item: item[0])
    table = 2 + 12 * len(items) + 4
    overflow = sum(len(raw) + len(raw) % 2 for _, _, _, raw in items if raw is not None and len(raw) > 4)
    cursor = at + table + overflow
    pointers = dict(ifd.dangling)
    blocks = []
    for tag in sorted(ifd.subs):
        block = encode(ifd.subs[tag], cursor, e)
        pointers[tag] = cursor
        cursor += len(block)
        blocks.append(block)
    next_at = 0
    if ifd.next_ifd:
        blocks.append(encode(ifd.next_ifd, cursor, e))
        next_at = cursor
    out = struct.pack(e + "H", len(items))
    over = b""
    for tag, kind, count, raw in items:
        if raw is None:
            raw = struct.pack(e + "I", pointers[tag])
        if len(raw) <= 4:
            field = raw.ljust(4, b"\0")
        else:
            field = struct.pack(e + "I", at + table + len(over))
            over += raw + b"\0" * (len(raw) % 2)
        out += struct.pack(e + "HHI", tag, kind, count) + field
    return out + struct.pack(e + "I", next_at) + over + b"".join(blocks)


def tiff(ifd, e="<", head4=None, extra=b"", tail=b""):
    """A TIFF block: header, optional extra header bytes (CR2), the IFD chain, then tail data."""
    head4 = head4 or (b"II*\0" if e == "<" else b"MM\0*")
    start = 8 + len(extra)
    return head4 + struct.pack(e + "I", start) + extra + encode(ifd, start, e) + tail


def dms(value):
    value = abs(value)
    degrees = int(value)
    minutes = int((value - degrees) * 60)
    seconds = round(((value - degrees) * 60 - minutes) * 60 * 10000)
    return [(degrees, 1), (minutes, 1), (seconds, 10000)]


def gps_ifd(lat, lon, alt=None, utc=None):
    """utc is 'YYYY-MM-DDTHH:MM:SS'."""
    entries = [
        (0x0001, ASCII, "N" if lat >= 0 else "S"), (0x0002, RATIONAL, dms(lat)),
        (0x0003, ASCII, "E" if lon >= 0 else "W"), (0x0004, RATIONAL, dms(lon)),
    ]
    if alt is not None:
        entries += [(0x0005, BYTE, 0 if alt >= 0 else 1), (0x0006, RATIONAL, (round(abs(alt) * 100), 100))]
    if utc:
        entries += [
            (0x0007, RATIONAL, [(int(utc[11:13]), 1), (int(utc[14:16]), 1), (int(utc[17:19]), 1)]),
            (0x001D, ASCII, utc[:10].replace("-", ":")),
        ]
    return Ifd(entries)


def exif_text(stamp):
    """'2019-05-09T15:47:33' -> '2019:05:09 15:47:33'."""
    return stamp[:10].replace("-", ":") + " " + stamp[11:19]


def apple_maker_note(content_id):
    ifd = encode(Ifd([(0x0011, ASCII, content_id)]), 14, ">")
    return b"Apple iOS\0\0\1MM" + ifd


def exif_ifd0(make=None, model=None, software=None, orientation=None, size=None, modified=None, original=None,
              digitized=None, offsets=(None, None, None), subsec=None, gps=None, maker_note=None,
              extra0=(), extra_exif=(), thumb=None, bad_exif_pointer=False):
    """offsets are the OffsetTime, OffsetTimeOriginal and OffsetTimeDigitized strings; times are raw EXIF text."""
    zero = [(0x0112, SHORT, orientation)] if orientation else []
    for tag, value in ((0x010F, make), (0x0110, model), (0x0131, software), (0x0132, modified)):
        if value is not None:
            zero.append((tag, ASCII, value))
    exif = [(0x9000, UNDEFINED, b"0231")]
    for tag, value in ((0x9003, original), (0x9004, digitized), (0x9010, offsets[0]), (0x9011, offsets[1]),
                       (0x9012, offsets[2]), (0x9291, subsec)):
        if value is not None:
            exif.append((tag, ASCII, value))
    if size:
        exif += [(0xA002, LONG, size[0]), (0xA003, LONG, size[1])]
    if maker_note:
        exif.append((0x927C, UNDEFINED, maker_note))
    subs, dangling = {}, {}
    if len(exif) > 1 or extra_exif:
        if bad_exif_pointer:
            dangling[0x8769] = 0x00FFFFF0
        else:
            subs[0x8769] = Ifd(exif + list(extra_exif))
    if gps is not None:
        subs[0x8825] = gps
    ifd1 = None
    if thumb is not None:
        ifd1 = Ifd([(0x0103, SHORT, 6), (0x0201, LONG, 0), (0x0202, LONG, len(thumb))])
    return Ifd(zero + list(extra0), subs, ifd1, dangling)


def exif_block(thumb=None, e="<", head4=None, extra=b"", **fields):
    """A complete EXIF TIFF block; a thumbnail JPEG is appended and referenced from IFD1."""
    first = tiff(exif_ifd0(thumb=thumb, **fields), e, head4, extra)
    if thumb is None:
        return first
    offset = len(first)
    ifd = exif_ifd0(thumb=thumb, **fields)
    ifd.next_ifd.entries[1] = (0x0201, LONG, offset)
    return tiff(ifd, e, head4, extra, thumb)
