"""Byte builders for video, HEIF and other container formats: real box and chunk structure. Payloads are
placeholders, except Motion JPEG video and the JPEG previews of RAW files, which show the corpus picture."""
import struct
from datetime import datetime, timezone

from images import filler, jpeg, riff_chunk
import tiffexif

QT_EPOCH = datetime(1904, 1, 1, tzinfo=timezone.utc)
SPHERICAL_V1 = (
    '<?xml version="1.0"?><rdf:SphericalVideo xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" '
    'xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/"><GSpherical:Spherical>true</GSpherical:Spherical>'
    "<GSpherical:Stitched>true</GSpherical:Stitched><GSpherical:StitchingSoftware>photolib corpus</GSpherical:StitchingSoftware>"
    "<GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType></rdf:SphericalVideo>"
)
CODEC_ENTRIES = {
    "h264": (b"avc1", b"avcC"), "hevc": (b"hvc1", b"hvcC"), "av1": (b"av01", b"av1C"), "vp9": (b"vp09", b"vpcC"),
    "h263": (b"s263", b"d263"), "mjpeg": (b"jpeg", None), "prores": (b"apch", None), "xvid": (b"mp4v", b"esds"),
}
ROTATIONS = {
    0: (0x10000, 0, 0, 0x10000), 90: (0, 0x10000, -0x10000, 0), 180: (-0x10000, 0, 0, -0x10000), 270: (0, -0x10000, 0x10000, 0),
}


def qt_seconds(year, month, day, hour=0, minute=0, second=0):
    """Seconds since 1904-01-01 UTC, the QuickTime clock."""
    return int((datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc) - QT_EPOCH).total_seconds())


def qt_clock(stamp):
    """QuickTime clock value for 'YYYY-MM-DDTHH:MM:SS' read as UTC."""
    return qt_seconds(int(stamp[:4]), int(stamp[5:7]), int(stamp[8:10]), int(stamp[11:13]), int(stamp[14:16]),
                      int(stamp[17:19]))


def box(kind, payload=b""):
    return struct.pack(">I", 8 + len(payload)) + kind + payload


def full(kind, payload=b"", version=0, flags=0):
    return box(kind, bytes([version]) + flags.to_bytes(3, "big") + payload)


def ftyp(major, compat=(), minor=0):
    return box(b"ftyp", major + struct.pack(">I", minor) + b"".join(compat))


class Heif:
    """Item table of a HEIF/AVIF file: items, shared properties and references; build() lays out meta and mdat."""

    extra_meta = b""

    def __init__(self):
        self.props, self.items, self.refs, self.primary = [], [], [], 1

    def prop(self, data):
        self.props.append(data)
        return len(self.props)

    def item(self, kind, data, props=(), mime=None, hidden=False):
        self.items.append((kind, data, list(props), mime, hidden))
        return len(self.items)

    def ref(self, kind, source, targets):
        self.refs.append((kind, source, list(targets)))

    def meta(self, offsets):
        infe = b"".join(
            full(b"infe", struct.pack(">HH", number, 0) + kind + b"\0" + (mime + b"\0" if mime else b""),
                 version=2, flags=1 if hidden else 0)
            for number, (kind, _, _, mime, hidden) in enumerate(self.items, 1)
        )
        iloc = full(b"iloc", bytes([0x44, 0x00]) + struct.pack(">H", len(self.items)) + b"".join(
            struct.pack(">HHHII", number, 0, 1, offsets[number - 1], len(item[1]))
            for number, item in enumerate(self.items, 1)))
        refs = b"".join(
            box(kind, struct.pack(">HH", source, len(targets)) + b"".join(struct.pack(">H", t) for t in targets))
            for kind, source, targets in self.refs)
        ipma = full(b"ipma", struct.pack(">I", sum(1 for item in self.items if item[2])) + b"".join(
            struct.pack(">HB", number, len(item[2])) + bytes(item[2])
            for number, item in enumerate(self.items, 1) if item[2]))
        return full(b"meta", (
            full(b"hdlr", bytes(4) + b"pict" + bytes(12) + b"\0") + full(b"pitm", struct.pack(">H", self.primary))
            + iloc + full(b"iinf", struct.pack(">H", len(self.items)) + infe) + (full(b"iref", refs) if refs else b"")
            + box(b"iprp", box(b"ipco", b"".join(self.props)) + ipma) + self.extra_meta
        ))

    def build(self, brand, compat, trailer=b""):
        head = ftyp(brand, compat)
        cursor = len(head) + len(self.meta([0] * len(self.items))) + 8
        offsets = []
        for item in self.items:
            offsets.append(cursor)
            cursor += len(item[1])
        return head + self.meta(offsets) + box(b"mdat", b"".join(item[1] for item in self.items)) + trailer


def heif(*, seed, codec, width, height, brand, compat, depth=8, exif=None, xmp_packet=None, grid=None, rotation=None,
         mirror=None, clap=None, colr=None, aux=(), tmap=False, stereo=False, trailer=b""):
    """HEIC (codec 'hevc') or AVIF (codec 'av1'). rotation is the irot quarter turns; mirror is the imir axis."""
    table = Heif()
    kind = b"hvc1" if codec == "hevc" else b"av01"
    config = box(b"hvcC", bytes([1]) + filler(seed + "c", 22)) if codec == "hevc" else box(b"av1C", bytes([0x81, 0, 0x0C, 0]))

    def ispe(w, h):
        return table.prop(full(b"ispe", struct.pack(">II", w, h)))

    shared = [table.prop(config), table.prop(full(b"pixi", bytes([3]) + bytes([depth]) * 3))]
    if colr:
        shared.append(table.prop(box(b"colr", b"nclx" + struct.pack(">HHHB", *colr, 0x80))))
    transforms = []
    if clap:
        transforms.append(table.prop(box(b"clap", struct.pack(">8I", *clap))))
    if rotation is not None:
        transforms.append(table.prop(box(b"irot", bytes([rotation]))))
    if mirror is not None:
        transforms.append(table.prop(box(b"imir", bytes([mirror]))))
    if grid:
        rows, cols = grid
        descriptor = struct.pack(">BBBBHH", 0, 0, rows - 1, cols - 1, width, height)
        first = table.item(b"grid", descriptor, [ispe(width, height)] + transforms)
        tile = ispe(width // cols, height // rows)
        tiles = [table.item(kind, filler(f"{seed}t{i}", 48), [tile, *shared], hidden=True) for i in range(rows * cols)]
        table.ref(b"dimg", first, tiles)
    else:
        first = table.item(kind, filler(seed, 96), [ispe(width, height), *shared, *transforms])
    if exif:
        table.ref(b"cdsc", table.item(b"Exif", struct.pack(">I", 6) + b"Exif\0\0" + exif), [first])
    if xmp_packet:
        table.ref(b"cdsc", table.item(b"mime", xmp_packet, mime=b"application/rdf+xml"), [first])
    for urn, aux_width, aux_height in aux:
        props = [ispe(aux_width, aux_height), shared[0], table.prop(full(b"pixi", bytes([1, depth]))),
                 table.prop(full(b"auxC", urn.encode() + b"\0"))]
        table.ref(b"auxl", table.item(kind, filler(seed + urn, 32), props, hidden=True), [first])
    if tmap:
        gain = table.item(kind, filler(seed + "gain", 32), [ispe(width // 2, height // 2), *shared], hidden=True)
        table.primary = table.item(b"tmap", filler(seed + "tmap", 24))
        table.ref(b"dimg", table.primary, [first, gain])
    if stereo:
        second = table.item(kind, filler(seed + "right", 96), [ispe(width, height), *shared])
        table.extra_meta = box(b"grpl", full(b"ster", struct.pack(">IIII", 100, 2, first, second)))
    return table.build(brand, compat, trailer)


def mpvd(video):
    return box(b"mpvd", video)


def matrix(angle):
    a, b, c, d = ROTATIONS[angle]
    return struct.pack(">9i", a, b, 0, c, d, 0, 0, 0, 0x40000000)


def video_entry(codec, width, height, *, hdr=None, stereo=None, sphere=None, bounds=(0, 0, 0, 0), extra=b""):
    """A sample description. hdr: pq, hlg or dv; stereo: 1 top-bottom, 2 left-right; sphere: equi or cube; bounds:
    equi's projection bounds top, bottom, left and right, the full panorama's 0.32 fixed-point fractions cut off."""
    fourcc, config = CODEC_ENTRIES[codec]
    children = box(config, bytes([1]) + filler(f"cfg{codec}", 11)) if config else b""
    if hdr in ("pq", "hlg"):
        children += box(b"colr", b"nclx" + struct.pack(">HHHB", 9, 16 if hdr == "pq" else 18, 9, 0x80))
    if hdr == "dv":
        children += box(b"dvcC", struct.pack(">BBHI", 1, 0, (8 << 9) | (6 << 3) | 1, 0) + bytes(16))
    if stereo:
        children += full(b"st3d", bytes([stereo]))
    if sphere:
        projection = (full(b"equi", struct.pack(">4I", *bounds)) if sphere == "equi"
                      else full(b"cbmp", struct.pack(">II", 0, 0)))
        children += box(b"sv3d", full(b"svhd", b"photolib corpus\0")
                        + box(b"proj", full(b"prhd", struct.pack(">3i", 0, 0, 0)) + projection))
    body = bytes(6) + struct.pack(">H", 1) + bytes(16) + struct.pack(">HH", width, height)
    body += struct.pack(">IIIH", 0x480000, 0x480000, 0, 1) + bytes(32) + struct.pack(">Hh", 0x18, -1)
    return box(fourcc, body + children + extra)


def mdta_meta(pairs):
    keys = b"".join(box(b"mdta", key.encode()) for key, _ in pairs)
    items = b"".join(box(struct.pack(">I", index), box(b"data", struct.pack(">II", 1, 0) + value.encode()))
                     for index, (_, value) in enumerate(pairs, 1))
    return full(b"meta", full(b"hdlr", bytes(4) + b"mdta" + bytes(12) + b"\0")
                + full(b"keys", struct.pack(">I", len(pairs)) + keys) + box(b"ilst", items))


def mp4(*, seed, brand=b"isom", compat=(b"isom", b"mp42"), codec="h264", width=1920, height=1080, duration_ms=3000,
        created=None, rotation=0, keys=(), xyz=None, payload=192, hdr=None, stereo=None, sphere=None,
        bounds=(0, 0, 0, 0), extra_entry=b"", spherical_v1=False, marker=b"", trailer=b"", truncate=None,
        timescale=1000):
    """MP4, MOV or 3GP. created is a QuickTime clock value (None writes zero); keys are mdta (key, value) pairs.
    An mjpeg track holds real JPEG frames at 10 per second with a sample table that finds them; other codecs get
    an empty sample table and placeholder bytes."""
    frames = [jpeg(width, height, seed=seed)] * max(1, duration_ms // 100) if codec == "mjpeg" else []
    stamp = struct.pack(">II", created or 0, created or 0)
    length = struct.pack(">I", duration_ms * timescale // 1000)
    mvhd = full(b"mvhd", stamp + struct.pack(">I", timescale) + length + struct.pack(">IH", 0x10000, 0x100)
                + bytes(10) + matrix(0) + bytes(24) + struct.pack(">I", 2))
    tkhd = full(b"tkhd", stamp + struct.pack(">II", 1, 0) + length + bytes(8) + bytes(4) + struct.pack(">HH", 0, 0)
                + matrix(rotation) + struct.pack(">II", width << 16, height << 16), flags=7)
    entry = video_entry(codec, width, height, hdr=hdr, stereo=stereo, sphere=sphere, bounds=bounds, extra=extra_entry)
    mdhd = full(b"mdhd", stamp + struct.pack(">I", timescale) + length + struct.pack(">HH", 0x55C4, 0))
    hdlr = full(b"hdlr", bytes(4) + b"vide" + bytes(12) + b"VideoHandler\0")
    sphere_v1 = box(b"uuid", bytes.fromhex("ffcc8263f8554a938814587a02521fdd") + SPHERICAL_V1.encode()) if spherical_v1 else b""
    udta = box(b"udta", box(b"\xa9xyz", struct.pack(">HH", len(xyz), 0x15C7) + xyz.encode())) if xyz else b""
    head = ftyp(brand, compat)

    def moov(offset):
        count = len(frames)
        table = full(b"stts", struct.pack(">III", 1, count, timescale // 10) if count else struct.pack(">I", 0))
        table += full(b"stsc", struct.pack(">IIII", 1, 1, count, 1) if count else struct.pack(">I", 0))
        table += full(b"stsz", struct.pack(f">II{count}I", 0, count, *map(len, frames)))
        table += full(b"stco", struct.pack(">II", 1, offset) if count else struct.pack(">I", 0))
        minf = box(b"minf", full(b"vmhd", bytes(8), flags=1) + box(b"stbl", full(b"stsd", struct.pack(">I", 1) + entry)
                                                                   + table))
        trak = box(b"trak", tkhd + box(b"mdia", mdhd + hdlr + minf) + sphere_v1)
        return box(b"moov", mvhd + trak + (mdta_meta(keys) if keys else b"") + udta)

    start = len(head) + len(moov(0)) + 8
    data = head + moov(start) + box(b"mdat", b"".join(frames) or marker + filler(seed, payload)) + trailer
    return data[:truncate] if truncate else data


def cr3(*, seed, make, model, width, height, original=None, offsets=(None, None, None), orientation=None, gps=None,
        preview=None):
    """A CR3 stub: Canon's metadata boxes, a THMB box with the JPEG preview, placeholder sensor data."""
    zero = tiffexif.tiff(tiffexif.exif_ifd0(make=make, model=model, orientation=orientation))
    exif_entries = [(0x9000, tiffexif.UNDEFINED, b"0231")]
    for tag, value in ((0x9003, original), (0x9011, offsets[1])):
        if value is not None:
            exif_entries.append((tag, tiffexif.ASCII, value))
    metadata = bytes.fromhex("85c0b687820f11e08111f4ce462b6a48") + box(b"CNCV", b"CanonCR3_001/00.09.00/00.00.00")
    metadata += box(b"CMT1", zero) + box(b"CMT2", tiffexif.tiff(tiffexif.Ifd(exif_entries)))
    if gps is not None:
        metadata += box(b"CMT4", tiffexif.tiff(gps))
    if preview:
        metadata += box(b"THMB", bytes(4) + struct.pack(">HHIHH", 160, 120, len(preview), 0, 0) + preview)
    entry = box(b"CRAW", bytes(6) + struct.pack(">H", 1) + bytes(16) + struct.pack(">HH", width, height) + bytes(50))
    stbl = box(b"stbl", full(b"stsd", struct.pack(">I", 1) + entry))
    trak = box(b"trak", box(b"mdia", full(b"hdlr", bytes(4) + b"vide" + bytes(12) + b"\0") + box(b"minf", stbl)))
    return ftyp(b"crx ", (b"isom",), 1) + box(b"moov", box(b"uuid", metadata) + trak) + box(b"mdat", filler(seed, 128))


def sef_trailer(entries):
    """Approximation of Samsung's SEF trailer: named data blocks, a SEFH directory, then its length and SEFT."""
    body, rows = b"", []
    for index, (name, payload) in enumerate(entries):
        block = struct.pack("<HHI", 0, 0x0A01 + index, len(name)) + name.encode() + payload
        body += block
        rows.append((0x0A01 + index, len(block)))
    directory = b"SEFH" + struct.pack("<II", 107, len(rows))
    for index, (kind, length) in enumerate(rows):
        directory += struct.pack("<HHII", 0, kind, sum(row[1] for row in rows[index:]), length)
    return body + directory + struct.pack("<I", len(directory)) + b"SEFT"


def vint(number):
    for size in range(1, 9):
        if number < (1 << (7 * size)) - 1:
            return (number | (1 << (7 * size))).to_bytes(size, "big")
    raise ValueError(number)


def element(ident, payload):
    return bytes.fromhex(ident) + vint(len(payload)) + payload


def mkv(*, seed, doctype="matroska", codec_id="V_MPEG4/ISO/AVC", width=1280, height=720, duration_ms=5000):
    header = element("1A45DFA3", b"".join((
        element("4286", b"\1"), element("42F7", b"\1"), element("42F2", b"\4"), element("42F3", b"\x08"),
        element("4282", doctype.encode()), element("4287", b"\4"), element("4285", b"\2"))))
    info = element("1549A966", element("2AD7B1", struct.pack(">I", 1000000))
                   + element("4489", struct.pack(">d", float(duration_ms)))
                   + element("4D80", b"photolib corpus") + element("5741", b"photolib corpus"))
    video = element("E0", element("B0", struct.pack(">H", width)) + element("BA", struct.pack(">H", height)))
    track = element("AE", element("D7", b"\1") + element("73C5", b"\1") + element("83", b"\1")
                    + element("86", codec_id.encode()) + video)
    cluster = element("1F43B675", element("E7", b"\0") + element("A3", b"\x81\0\0\x80" + filler(seed, 64)))
    return header + element("18538067", info + element("1654AE6B", track) + cluster)


def mpeg_crc(data):
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
    return struct.pack(">I", crc)


def ts_packet(pid, payload, counter):
    return b"\x47" + struct.pack(">H", 0x4000 | pid) + bytes([0x10 | counter & 15]) + payload.ljust(184, b"\xff")


def mpegts(*, seed, packets=6, stream_type=0x1B, m2ts=False):
    """MPEG transport stream: PAT, PMT, then video packets. m2ts adds the 4-byte Blu-ray timestamp per packet."""
    pat = bytes.fromhex("00b00d0001c100000001f000")
    pmt = bytes.fromhex("02b0120001c10000e100f000") + bytes([stream_type]) + struct.pack(">HH", 0xE100, 0xF000)
    payloads = [b"\0" + pat + mpeg_crc(pat), b"\0" + pmt + mpeg_crc(pmt)]
    payloads += [filler(f"{seed}{n}", 184) for n in range(packets - 2)]
    pids = [0, 0x1000] + [0x100] * (packets - 2)
    out = b""
    for number, (pid, payload) in enumerate(zip(pids, payloads)):
        out += (struct.pack(">I", number * 1000) if m2ts else b"") + ts_packet(pid, payload, number)
    return out


def avi(*, seed, width=640, height=480, compression=b"MJPG", frames=10):
    """An AVI at 10 frames per second with an idx1 index; MJPG frames are JPEGs of the picture, other codecs get
    one placeholder chunk."""
    chunks = [jpeg(width, height, seed=seed)] * frames if compression == b"MJPG" else [filler(seed, 64)]
    avih = struct.pack("<14I", 100000, 0, 0, 0x10, frames, 0, 1, 0, width, height, 0, 0, 0, 0)
    strh = struct.pack("<4s4sIHHIIIIIIIIhhhh", b"vids", compression, 0, 0, 0, 0, 1, 10, 0, frames, 0, 0xFFFFFFFF, 0,
                       0, 0, width, height)
    strf = struct.pack("<IiiHH4sIiiII", 40, width, height, 1, 24, compression, width * height * 3, 0, 0, 0, 0)
    hdrl = b"hdrl" + riff_chunk(b"avih", avih) + riff_chunk(b"LIST", b"strl" + riff_chunk(b"strh", strh) + riff_chunk(b"strf", strf))
    movi, index = b"movi", b""
    for chunk in chunks:
        index += b"00dc" + struct.pack("<III", 0x10, len(movi), len(chunk))
        movi += riff_chunk(b"00dc", chunk)
    body = b"AVI " + riff_chunk(b"LIST", hdrl) + riff_chunk(b"LIST", movi) + riff_chunk(b"idx1", index)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def asf(*, seed):
    guid_header = bytes.fromhex("3026b2758e66cf11a6d900aa0062ce6c")
    guid_props = bytes.fromhex("a1dcab8c47a9cf118ee400c00c205365")
    guid_data = bytes.fromhex("3626b2758e66cf11a6d900aa0062ce6c")
    file_id = filler(seed, 16)
    props = guid_props + struct.pack("<Q", 104) + file_id
    props += struct.pack("<QQQQQQIIII", 0, 0, 1, 30000, 30000, 3000, 2, 1000, 1000, 0)
    header = guid_header + struct.pack("<QIBB", 30 + len(props), 1, 1, 2) + props
    packets = filler(seed + "d", 96)
    return header + guid_data + struct.pack("<Q", 50 + len(packets)) + file_id + struct.pack("<QH", 1, 0x0101) + packets


def flv(*, seed, width=320, height=240, duration_s=3.0):
    def pair(name, value):
        return struct.pack(">H", len(name)) + name.encode() + b"\0" + struct.pack(">d", value)

    def tag(kind, data):
        return bytes([kind]) + len(data).to_bytes(3, "big") + bytes(7) + data + struct.pack(">I", 11 + len(data))

    meta = b"\x02" + struct.pack(">H", 10) + b"onMetaData" + b"\x08" + struct.pack(">I", 3)
    meta += pair("duration", duration_s) + pair("width", float(width)) + pair("height", float(height)) + b"\0\0\x09"
    return b"FLV\x01\x01" + struct.pack(">II", 9, 0) + tag(18, meta) + tag(9, bytes([0x12]) + filler(seed, 24))


def mpeg_ps(*, seed, width=720, height=576):
    pack = b"\x00\x00\x01\xba" + bytes.fromhex("4400040004010189c3f8")
    system = b"\x00\x00\x01\xbb" + struct.pack(">H", 12) + bytes.fromhex("80c4e104e17fe0e0e8c0c020")
    sequence = b"\x00\x00\x01\xb3" + ((((width << 12) | height) << 8) | 0x13).to_bytes(4, "big") + bytes([0xFF, 0xFF, 0xE0, 0x18])
    payload = sequence + filler(seed, 48)
    return pack + system + b"\x00\x00\x01\xe0" + struct.pack(">H", len(payload) + 3) + b"\x80\x00\x00" + payload


def raf(*, seed, model, jpeg_bytes):
    head = b"FUJIFILMCCD-RAW 0201FF129504" + model.encode().ljust(32, b"\0") + b"0100" + bytes(20)
    cfa_header, cfa = bytes(4) + filler(seed + "h", 28), filler(seed + "c", 96)
    jpeg_at = 160
    head += struct.pack(">6I", jpeg_at, len(jpeg_bytes), jpeg_at + len(jpeg_bytes), len(cfa_header),
                        jpeg_at + len(jpeg_bytes) + len(cfa_header), len(cfa))
    return head.ljust(jpeg_at, b"\0") + jpeg_bytes + cfa_header + cfa


def ogg(*, seed):
    return b"OggS\0\x02" + bytes(8) + struct.pack("<III", 1, 0, 0) + b"\x01\x1e" + b"\x01vorbis" + filler(seed, 23)


def unknown(*, seed, size=96):
    return b"PHOTOLIB-CORPUS-UNKNOWN\0" + filler(seed, size)
