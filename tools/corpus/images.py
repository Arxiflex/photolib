"""Byte builders for still images: real container structure, real metadata blocks and decodable pixels showing the
corpus picture (picture.py). The same call returns the same bytes on every platform: the coders are written here in
integer arithmetic, without zlib's compressor or any image library.
"""
import hashlib
import struct
import zlib
from xml.sax.saxutils import escape, quoteattr

import jpegscan
import picture
import tiffexif
import webpcode

NAMESPACES = {
    "xmp": "http://ns.adobe.com/xap/1.0/",
    "exif": "http://ns.adobe.com/exif/1.0/",
    "photoshop": "http://ns.adobe.com/photoshop/1.0/",
    "GPano": "http://ns.google.com/photos/1.0/panorama/",
    "GCamera": "http://ns.google.com/photos/1.0/camera/",
    "Container": "http://ns.google.com/photos/1.0/container/",
    "Item": "http://ns.google.com/photos/1.0/container/item/",
    "hdrgm": "http://ns.adobe.com/hdr-gain-map/1.0/",
    "GDepth": "http://ns.google.com/photos/1.0/depthmap/",
    "Device": "http://ns.google.com/photos/dd/1.0/device/",
}


def filler(seed, size):
    """Deterministic placeholder bytes without 0xFF, so they never fake a JPEG marker."""
    out = bytearray()
    counter = 0
    while len(out) < size:
        out += hashlib.sha256(f"{seed}:{counter}".encode()).digest()
        counter += 1
    return bytes(0xFE if byte == 0xFF else byte for byte in out[:size])


def xmp(groups, inner=""):
    """An XMP packet: groups maps a namespace prefix to its attributes; inner is raw RDF for structured values."""
    declared = "".join(f' xmlns:{prefix}="{NAMESPACES[prefix]}"' for prefix in groups)
    values = "".join(
        f" {prefix}:{name}={quoteattr(str(value))}" for prefix, attrs in groups.items() for name, value in attrs.items()
    )
    return (
        '<?xpacket begin="\ufeff" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        f'<rdf:Description rdf:about=""{declared}{values}>{inner}</rdf:Description></rdf:RDF></x:xmpmeta>\n'
        '<?xpacket end="w"?>'
    ).encode("utf-8")


def container_directory(items):
    """Google container directory; items are (mime, semantic, length) tuples."""
    rows = "".join(
        '<rdf:li rdf:parseType="Resource">'
        f'<Container:Item Item:Mime="{mime}" Item:Semantic="{semantic}" Item:Length="{length}"/></rdf:li>'
        for mime, semantic, length in items
    )
    return f"<Container:Directory><rdf:Seq>{rows}</rdf:Seq></Container:Directory>"


def segment(marker, payload):
    return b"\xff" + bytes([marker]) + struct.pack(">H", len(payload) + 2) + payload


def app(number, payload):
    return segment(0xE0 + number, payload)


def exif_segment(block):
    return app(1, b"Exif\0\0" + block)


def xmp_segment(packet):
    return app(1, b"http://ns.adobe.com/xap/1.0/\0" + packet)


def mpf_payload(sizes_and_offsets):
    entries = b"".join(
        struct.pack("<IIIHH", 0x20030000 if index == 0 else 0, size, offset, 0, 0)
        for index, (size, offset) in enumerate(sizes_and_offsets)
    )
    ifd = tiffexif.Ifd([
        (0xB000, tiffexif.UNDEFINED, b"0100"), (0xB001, tiffexif.LONG, len(sizes_and_offsets)),
        (0xB002, tiffexif.UNDEFINED, entries),
    ])
    return b"MPF\0" + tiffexif.tiff(ifd, "<")


def jpeg(width, height, segments=(), *, seed, progressive=False, components=3, adobe_transform=None, comment=None,
         jfif=False, secondary=(), tail=b"", truncate=None):
    """A JPEG of the picture named by seed. Secondary images (Ultra HDR gain map) follow the primary and are listed
    in an MPF segment; tail is appended after everything; truncate cuts the file to that many bytes."""
    coded, interval = jpegscan.scans(seed, width, height, components=components, progressive=progressive)

    def assemble(mpf):
        out = b"\xff\xd8"
        if jfif:
            out += app(0, b"JFIF\0\1\1\0\0\1\0\1\0\0")
        out += b"".join(segments)
        if mpf is not None:
            out += app(2, mpf)
        if adobe_transform is not None:
            out += app(14, b"Adobe\0\x64\0\0\0\0" + bytes([adobe_transform]))
        if comment:
            out += segment(0xFE, comment.encode())
        out += segment(0xDB, jpegscan.QUANT_TABLE)
        frame = bytes([8]) + struct.pack(">HH", height, width) + bytes([components])
        for index in range(components):
            frame += bytes([index + 1, 0x22 if index == 0 else 0x11, 0])
        out += segment(0xC2 if progressive else 0xC0, frame) + segment(0xC4, jpegscan.TABLES)
        if interval:
            out += segment(0xDD, struct.pack(">H", interval))
        return out + b"".join(segment(0xDA, header) + data for header, data in coded) + b"\xff\xd9"

    if not secondary:
        data = assemble(None) + tail
    else:
        primary = assemble(mpf_payload([(0, 0)] * (len(secondary) + 1)))
        base = primary.index(b"MPF\0") + 4
        placed, cursor = [(len(primary), 0)], len(primary)
        for blob in secondary:
            placed.append((len(blob), cursor - base))
            cursor += len(blob)
        data = assemble(mpf_payload(placed)) + b"".join(secondary) + tail
    return data[:truncate] if truncate else data


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def filtered(lines, step):
    """PNG scanlines: Up (all zeros) when a line repeats the one before, else Sub, which zeroes flat runs."""
    out, previous = [], None
    for line in lines:
        if line == previous:
            out.append(b"\x02" + bytes(len(line)))
        else:
            out.append(b"\x01" + bytes((line[i] - (line[i - step] if i >= step else 0)) & 255 for i in range(len(line))))
        previous = line
    return b"".join(out)


ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def png(width, height, *, seed, color=2, depth=8, interlace=0, exif=None, itxt_xmp=None, text=None, frames=1):
    """A PNG; frames > 1 makes an APNG. color: 0 grey, 2 RGB, 3 palette, 6 RGBA (the bars half transparent)."""
    images = [picture.pixels(seed, width, height, frame) for frame in range(frames)]
    palette = list(dict.fromkeys(rgb for image in images for line in image for rgb in line))
    sample = {
        0: lambda rgb: (picture.grey(rgb) * 257).to_bytes(2, "big") if depth == 16 else bytes([picture.grey(rgb)]),
        2: bytes, 3: lambda rgb: bytes([palette.index(rgb)]),
        6: lambda rgb: bytes(rgb) + bytes([160 if rgb in picture.BARS else 255]),
    }[color]
    step = {0: depth // 8, 2: 3, 3: 1, 6: 4}[color]

    def idat(image):
        passes = ADAM7 if interlace else ((0, 0, 1, 1),)
        lines = [[b"".join(sample(rgb) for rgb in line[x0::dx]) for line in image[y0::dy]] for x0, y0, dx, dy in passes]
        return picture.deflate(b"".join(filtered(group, step) for group in lines if group and group[0]))

    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, color, 0, 0, interlace))
    if color == 3:
        out += chunk(b"PLTE", b"".join(bytes(rgb) for rgb in palette))
    if exif:
        out += chunk(b"eXIf", exif)
    for key, value in (text or {}).items():
        out += chunk(b"tEXt", key.encode() + b"\0" + value.encode())
    if itxt_xmp:
        out += chunk(b"iTXt", b"XML:com.adobe.xmp\0\0\0\0\0" + itxt_xmp)
    if frames > 1:
        out += chunk(b"acTL", struct.pack(">II", frames, 0))
    sequence = 0
    for index, image in enumerate(images):
        if frames > 1:
            out += chunk(b"fcTL", struct.pack(">IIIIIHHBB", sequence, width, height, 0, 0, 1, 10, 0, 0))
            sequence += 1
        if index == 0:
            out += chunk(b"IDAT", idat(image))
        else:
            out += chunk(b"fdAT", struct.pack(">I", sequence) + idat(image))
            sequence += 1
    return out + chunk(b"IEND", b"")


def gif(width, height, *, seed, frames=1, interlaced=False, comment=None):
    """A GIF with a 16-colour global palette; frames > 1 loops an animation whose bars move."""
    images = [picture.pixels(seed, width, height, frame) for frame in range(frames)]
    palette = list(dict.fromkeys(rgb for image in images for line in image for rgb in line))
    out = b"GIF89a" + struct.pack("<HHBBB", width, height, 0x83, 0, 0)
    out += b"".join(bytes(rgb) for rgb in palette).ljust(48, b"\0")
    if frames > 1:
        out += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\0\0\0"
    if comment:
        out += b"\x21\xfe" + bytes([len(comment)]) + comment.encode() + b"\0"
    order = [y for start, step in ((0, 8), (4, 8), (2, 4), (1, 2)) for y in range(start, height, step)] \
        if interlaced else range(height)
    for image in images:
        data = picture.lzw([palette.index(rgb) for y in order for rgb in image[y]], 4)
        out += b"\x21\xf9\x04\x00" + struct.pack("<H", 10) + b"\0\0"
        out += b"\x2c" + struct.pack("<HHHH", 0, 0, width, height) + bytes([0x40 if interlaced else 0]) + b"\x04"
        out += b"".join(bytes([len(data[i:i + 255])]) + data[i:i + 255] for i in range(0, len(data), 255)) + b"\0"
    return out + b"\x3b"


def bmp(width, height, *, seed):
    """A 24-bit BMP: rows bottom up, BGR, padded to four bytes."""
    pad = b"\0" * (-3 * width % 4)
    pixels = b"".join(bytes(c for rgb in zip(row[2::3], row[1::3], row[0::3]) for c in rgb) + pad
                      for row in reversed(picture.rows(seed, width, height)))
    dib = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    return b"BM" + struct.pack("<IHHI", 54 + len(pixels), 0, 0, 54) + dib + pixels


def riff_chunk(tag, data):
    return tag + struct.pack("<I", len(data)) + data + b"\0" * (len(data) % 2)


def webp(width, height, *, seed, mode="lossy", exif=None, xmp_packet=None, frames=3):
    """mode: lossy (VP8), lossless (VP8L), alpha (VP8X, ALPH and VP8, the bars half transparent), animated (lossy
    frames whose bars move)."""
    plain = {"lossy": lambda: riff_chunk(b"VP8 ", webpcode.vp8(picture.pixels(seed, width, height))),
             "lossless": lambda: riff_chunk(b"VP8L", webpcode.vp8l(picture.pixels(seed, width, height)))}
    if mode in plain and not exif and not xmp_packet:
        chunks = plain[mode]()
    else:
        flags = (0x10 if mode == "alpha" else 0) | (0x08 if exif else 0)
        flags |= (0x04 if xmp_packet else 0) | (0x02 if mode == "animated" else 0)
        size = struct.pack("<I", width - 1)[:3] + struct.pack("<I", height - 1)[:3]
        chunks = riff_chunk(b"VP8X", bytes([flags]) + bytes(3) + size)
        if mode == "animated":
            chunks += riff_chunk(b"ANIM", bytes(4) + struct.pack("<H", 0))
            for index in range(frames):
                frame = bytes(6) + size + struct.pack("<I", 100)[:3] + b"\0"
                frame += riff_chunk(b"VP8 ", webpcode.vp8(picture.pixels(seed, width, height, index)))
                chunks += riff_chunk(b"ANMF", frame)
        elif mode == "alpha":
            image = picture.pixels(seed, width, height)
            alpha = bytes(160 if rgb in picture.BARS else 255 for line in image for rgb in line)
            chunks += riff_chunk(b"ALPH", b"\0" + alpha) + riff_chunk(b"VP8 ", webpcode.vp8(image))
        else:
            chunks += plain[mode]()
        if exif:
            chunks += riff_chunk(b"EXIF", exif)
        if xmp_packet:
            chunks += riff_chunk(b"XMP ", xmp_packet)
    body = b"WEBP" + chunks
    return b"RIFF" + struct.pack("<I", len(body)) + body


def raster(seed, width, height, bits=8, channels=1, sample_format=1, e="<"):
    """Raw interleaved samples of the picture: grey or RGB, 8 or 16-bit integers or 32-bit floats."""
    values = [c for line in picture.pixels(seed, width, height)
              for rgb in line for c in (rgb if channels == 3 else (picture.grey(rgb),))]
    if bits == 8:
        return bytes(values)
    if sample_format == 3:
        return struct.pack(f"{e}{len(values)}f", *(v / 255 for v in values))
    return struct.pack(f"{e}{len(values)}H", *(v * 257 for v in values))


def tiff_image(width, height, *, seed, bits=8, samples=1, sample_format=1, pages=1, e="<", head4=None, extra=b"",
               thumb=None, entries0=(), compression=1, photometric=None, **fields):
    """An uncompressed TIFF of the picture plus EXIF fields; also the base of the TIFF-based RAW stubs, where thumb
    is the JPEG preview that IFD1 points at."""
    data = raster(seed, width, height, bits, samples, sample_format, e)

    def build(offset):
        ifd = tiffexif.exif_ifd0(thumb=thumb, **fields)
        base = [
            (0x0100, tiffexif.LONG, width), (0x0101, tiffexif.LONG, height),
            (0x0102, tiffexif.SHORT, [bits] * samples), (0x0103, tiffexif.SHORT, compression),
            (0x0106, tiffexif.SHORT, photometric or (2 if samples == 3 else 1)), (0x0111, tiffexif.LONG, offset),
            (0x0115, tiffexif.SHORT, samples), (0x0116, tiffexif.LONG, height),
            (0x0117, tiffexif.LONG, len(data)),
        ]
        if sample_format != 1:
            base.append((0x0153, tiffexif.SHORT, [sample_format] * samples))
        ifd.entries += base + list(entries0)
        if thumb is not None:
            ifd.next_ifd.entries[1] = (0x0201, tiffexif.LONG, offset + len(data))
        tail = ifd
        for _ in range(pages - 1):
            tail.next_ifd = tiffexif.Ifd(list(base))
            tail = tail.next_ifd
        return tiffexif.tiff(ifd, e, head4, extra, data + (thumb or b""))

    offset = len(build(0)) - len(data) - len(thumb or b"")
    return build(offset)


def bigtiff(width, height, *, seed):
    data = raster(seed, width, height)
    rows = [
        (0x0100, 4, width), (0x0101, 4, height), (0x0102, 3, 8), (0x0103, 3, 1), (0x0106, 3, 1),
        (0x0111, 16, 16 + 8 + 20 * 8 + 8), (0x0116, 4, height), (0x0117, 16, len(data)),
    ]
    out = b"II+\0" + struct.pack("<HHQ", 8, 0, 16) + struct.pack("<Q", len(rows))
    for tag, kind, value in rows:
        out += struct.pack("<HHQQ", tag, kind, 1, value)
    return out + struct.pack("<Q", 0) + data


def psd(width, height, *, seed, large=False, xmp_packet=None, exif=None):
    """An RGB PSD, or PSB when large, without layers: the merged image as raw planes."""
    blocks = b""
    for resource, payload in ((1058, exif), (1060, xmp_packet)):
        if payload:
            blocks += b"8BIM" + struct.pack(">HBBI", resource, 0, 0, len(payload)) + payload + b"\0" * (len(payload) % 2)
    out = b"8BPS" + struct.pack(">H", 2 if large else 1) + bytes(6) + struct.pack(">HIIHH", 3, height, width, 8, 3)
    out += struct.pack(">I", 0) + struct.pack(">I", len(blocks)) + blocks + struct.pack(">Q" if large else ">I", 0)
    rgb = raster(seed, width, height, channels=3)
    return out + struct.pack(">H", 0) + rgb[0::3] + rgb[1::3] + rgb[2::3]


def jxl(*, seed, exif=None, xmp_packet=None, recompressed_jpeg=False, bare=False):
    code = b"\xff\x0a" + filler(seed, 12) + bytes(2)
    if bare:
        return code

    def box(kind, payload):
        return struct.pack(">I", 8 + len(payload)) + kind + payload

    out = bytes.fromhex("0000000c4a584c200d0a870a") + box(b"ftyp", b"jxl \0\0\0\0jxl ")
    if exif:
        out += box(b"Exif", bytes(4) + exif)
    if xmp_packet:
        out += box(b"xml ", xmp_packet)
    if recompressed_jpeg:
        out += box(b"jbrd", filler(seed + "jbrd", 24))
    return out + box(b"jxlc", code)


def svg(width, height, seed):
    """The picture as vector shapes: the bars, the band and the case name as text."""
    edges = [i * width // 8 for i in range(9)]
    bars = "".join(f'  <rect x="{edges[i]}" y="0" width="{edges[i + 1] - edges[i]}" height="{height}" '
                   f'fill="#{bytes(picture.BARS[i]).hex()}"/>\n' for i in range(8))
    name = escape(seed.rsplit("/", 1)[-1])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n'
            f'  <title>{name}</title>\n{bars}  <rect width="{width}" height="{height // 3}" fill="#000000"/>\n'
            f'  <text x="4" y="{height // 4}" font-family="monospace" font-size="{height // 6}" fill="#ffffff">{name}'
            '</text>\n</svg>\n').encode()


def pdf(title):
    """The empty content stream holds NUL bytes, which marks the file as binary (xref lines end in a space)."""
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 5 0 R >>",
        b"<< /Title (" + title.encode() + b") >>", b"<< /Length 4 >>\nstream\n\0\0\0\0\nendstream",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    out += "".join(f"{offset:010d} 00000 n \n" for offset in offsets).encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R /Info 4 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return out


def eps(width, height):
    return (f"%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 {width} {height}\n%%Pages: 1\n%%EndComments\n"
            f"0.5 setgray 0 0 {width} {height} rectfill\nshowpage\n%%EOF\n").encode()
