#!/usr/bin/env python3
"""Tests for the corpus byte builders, read back by small independent parsers written here with struct only."""
import os
import re
import struct
import sys
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "corpus"))
import containers  # noqa: E402
import images  # noqa: E402
import picture  # noqa: E402
import tiffexif  # noqa: E402

SIZES = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8}


def read_ifd(data, offset, e, seen=None):
    """{tag: value} for one IFD, plus 'next' (offset)."""
    (count,) = struct.unpack_from(e + "H", data, offset)
    out = {}
    for index in range(count):
        tag, kind, n, field = struct.unpack_from(e + "HHI4s", data, offset + 2 + 12 * index)
        size = SIZES[kind] * n
        raw = field[:size] if size <= 4 else data[struct.unpack(e + "I", field)[0]:][:size]
        if kind == 2:
            out[tag] = raw.rstrip(b"\0").decode("latin-1")
        elif kind in (3, 4):
            values = struct.unpack(e + ("H" if kind == 3 else "I") * n, raw)
            out[tag] = values[0] if n == 1 else list(values)
        elif kind == 5:
            out[tag] = [struct.unpack_from(e + "II", raw, 8 * i) for i in range(n)]
        else:
            out[tag] = raw
    (out["next"],) = struct.unpack_from(e + "I", data, offset + 2 + 12 * count)
    return out


def read_tiff(data):
    e = "<" if data[:2] == b"II" else ">"
    (first,) = struct.unpack_from(e + "I", data, 4)
    return e, read_ifd(data, first, e)


class TiffWriter(unittest.TestCase):
    def test_ascii_values_inline_and_overflowing_round_trip_in_both_byte_orders(self):
        for order in ("<", ">"):
            data = tiffexif.exif_block(e=order, make="Hi", model="A model name over four bytes", orientation=6)
            e, zero = read_tiff(data)
            self.assertEqual((e, zero[0x010F], zero[0x0110], zero[0x0112]), (order, "Hi", "A model name over four bytes", 6))

    def test_exif_ifd_carries_times_and_offsets(self):
        data = tiffexif.exif_block(original="2019:05:09 15:47:33", offsets=(None, "+02:00", None), subsec="123")
        e, zero = read_tiff(data)
        exif = read_ifd(data, zero[0x8769], e)
        self.assertEqual((exif[0x9003], exif[0x9011], exif[0x9291]), ("2019:05:09 15:47:33", "+02:00", "123"))

    def test_gps_coordinates_and_utc_time(self):
        gps = tiffexif.gps_ifd(-33.8688, 151.2093, 58.5, "2019-05-09T05:47:33")
        data = tiffexif.exif_block(gps=gps)
        e, zero = read_tiff(data)
        block = read_ifd(data, zero[0x8825], e)
        degrees = sum(n / d / 60 ** i for i, (n, d) in enumerate(block[2]))
        self.assertEqual((block[1], block[3], round(degrees, 3)), ("S", "E", 33.869))
        self.assertEqual(block[0x1D], "2019:05:09")
        self.assertEqual([n for n, _ in block[7]], [5, 47, 33])

    def test_the_thumbnail_offset_points_at_the_thumbnail(self):
        thumb = b"\xff\xd8\xff\xd9"
        data = tiffexif.exif_block(thumb=thumb, make="Cam")
        e, zero = read_tiff(data)
        ifd1 = read_ifd(data, zero["next"], e)
        self.assertEqual(data[ifd1[0x0201]:ifd1[0x0201] + ifd1[0x0202]], thumb)

    def test_a_dangling_exif_pointer_points_past_the_end(self):
        data = tiffexif.exif_block(original="2019:05:09 15:47:33", bad_exif_pointer=True)
        _, zero = read_tiff(data)
        self.assertGreater(zero[0x8769], len(data))

    def test_extra_header_and_magic_variants(self):
        data = tiffexif.exif_block(head4=b"IIRO", make="Olympus")
        self.assertEqual(data[:4], b"IIRO")
        self.assertEqual(read_tiff(data)[1][0x010F], "Olympus")
        cr2 = tiffexif.exif_block(extra=b"CR\x02\x00" + bytes(4), make="Canon")
        self.assertEqual(cr2[8:10], b"CR")
        self.assertEqual(read_tiff(cr2)[1][0x010F], "Canon")

    def test_the_apple_maker_note_holds_the_content_identifier(self):
        note = tiffexif.apple_maker_note("0123ABCD-0000-4000-8000-000000000001")
        self.assertTrue(note.startswith(b"Apple iOS\0"))
        self.assertEqual(read_ifd(note, 14, ">")[0x11], "0123ABCD-0000-4000-8000-000000000001")


def jpeg_segments(data):
    """[(marker, payload)] up to and including SOS; asserts that every length is consistent."""
    assert data[:2] == b"\xff\xd8", "no SOI"
    out, pos = [], 2
    while True:
        assert data[pos] == 0xFF, f"no marker at {pos}"
        marker = data[pos + 1]
        (length,) = struct.unpack_from(">H", data, pos + 2)
        out.append((marker, data[pos + 4:pos + 2 + length]))
        pos += 2 + length
        if marker == 0xDA:
            return out, pos


def sof(segments):
    for marker, payload in segments:
        if marker in (0xC0, 0xC2):
            height, width = struct.unpack_from(">HH", payload, 1)
            return marker, width, height, payload[5]


class JpegBuilder(unittest.TestCase):
    def build(self, **kwargs):
        return images.jpeg(640, 480, seed="t", **kwargs)

    def test_markers_chain_and_frame_header_carries_the_size(self):
        data = self.build()
        segments, scan = jpeg_segments(data)
        self.assertEqual(sof(segments), (0xC0, 640, 480, 3))
        self.assertTrue(data.endswith(b"\xff\xd9"))
        restarts = re.findall(rb"\xff[\xd0-\xd7]", data[scan:-2])
        self.assertEqual(len(restarts), 480 // 16 - 1)
        self.assertEqual(struct.unpack(">H", dict(segments)[0xDD])[0], 640 // 16)
        self.assertNotIn(b"\xff", re.sub(rb"\xff[\x00\xd0-\xd7]", b"", data[scan:-2]))

    def test_equal_pictures_give_equal_bytes_and_seeds_differ(self):
        self.assertEqual(self.build(), self.build())
        self.assertNotEqual(self.build(), images.jpeg(640, 480, seed="u"))

    def test_progressive_cmyk_and_adobe_marker(self):
        segments, _ = jpeg_segments(self.build(progressive=True, components=4, adobe_transform=2))
        self.assertEqual(sof(segments), (0xC2, 640, 480, 4))
        adobe = [payload for marker, payload in segments if marker == 0xEE][0]
        self.assertEqual((adobe[:5], adobe[-1]), (b"Adobe", 2))

    def test_exif_and_xmp_segments_are_found_by_their_signatures(self):
        block = tiffexif.exif_block(make="Cam")
        packet = images.xmp({"xmp": {"CreateDate": "2019-05-09T15:47:33+02:00"}})
        segments, _ = jpeg_segments(self.build(segments=[images.exif_segment(block), images.xmp_segment(packet)]))
        payloads = [payload for marker, payload in segments if marker == 0xE1]
        self.assertEqual(payloads[0], b"Exif\0\0" + block)
        self.assertTrue(payloads[1].startswith(b"http://ns.adobe.com/xap/1.0/\0<?xpacket"))
        self.assertIn(b'xmp:CreateDate="2019-05-09T15:47:33+02:00"', payloads[1])

    def test_mpf_offsets_point_at_the_secondary_images(self):
        gain = self.build()
        data = images.jpeg(640, 480, seed="p", secondary=[gain])
        segments, _ = jpeg_segments(data)
        mpf = [payload for marker, payload in segments if marker == 0xE2][0]
        base = data.index(b"MPF\0") + 4
        _, zero = read_tiff(mpf[4:])
        entries = zero[0xB002]
        self.assertEqual(zero[0xB001], 2)
        size, offset = struct.unpack_from("<II", entries, 16 + 4)
        self.assertEqual((size, data[base + offset:base + offset + 2]), (len(gain), b"\xff\xd8"))
        self.assertEqual(data[base + offset:base + offset + size], gain)
        self.assertEqual(struct.unpack_from("<I", entries, 4)[0], len(data) - len(gain))

    def test_truncate_and_tail(self):
        self.assertEqual(len(self.build(truncate=100)), 100)
        self.assertTrue(self.build(tail=b"TRAILER").endswith(b"TRAILER"))


def png_chunks(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    out, pos = [], 8
    while pos < len(data):
        (length,) = struct.unpack_from(">I", data, pos)
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        (crc,) = struct.unpack_from(">I", data, pos + 8 + length)
        assert crc == zlib.crc32(kind + body), f"bad crc on {kind}"
        out.append((kind, body))
        pos += 12 + length
    return out


class RasterBuilders(unittest.TestCase):
    def test_png_chunks_have_valid_crcs_and_decodable_pixel_data(self):
        chunks = png_chunks(images.png(6, 4, seed="t", color=6, exif=b"II*\0"))
        kinds = [kind for kind, _ in chunks]
        self.assertEqual((kinds[0], kinds[-1], b"eXIf" in kinds), (b"IHDR", b"IEND", True))
        width, height, depth, color = struct.unpack(">IIBB", chunks[0][1][:10])
        idat = [body for kind, body in chunks if kind == b"IDAT"][0]
        self.assertEqual((width, height, depth, color, len(zlib.decompress(idat))), (6, 4, 8, 6, 4 * (1 + 6 * 4)))

    def test_interlaced_png_has_adam7_sized_data(self):
        chunks = png_chunks(images.png(9, 9, seed="t", interlace=1))
        raw = zlib.decompress([body for kind, body in chunks if kind == b"IDAT"][0])
        expected = sum(rows * (1 + cols * 3) for cols, rows in ((2, 2), (1, 2), (3, 1), (2, 3), (5, 2), (4, 5), (9, 4)))
        self.assertEqual(len(raw), expected)

    def test_apng_declares_its_frames_with_sequence_numbers(self):
        chunks = png_chunks(images.png(4, 4, seed="t", frames=3))
        kinds = [kind for kind, _ in chunks]
        self.assertEqual((struct.unpack(">II", chunks[kinds.index(b"acTL")][1])[0], kinds.count(b"fcTL"), kinds.count(b"fdAT")), (3, 3, 2))
        sequence = [struct.unpack_from(">I", body)[0] for kind, body in chunks if kind in (b"fcTL", b"fdAT")]
        self.assertEqual(sequence, list(range(5)))

    def test_gif_has_header_frames_and_trailer(self):
        descriptor = b"\x2c" + struct.pack("<HHHH", 0, 0, 16, 12)
        data = images.gif(16, 12, seed="t", frames=3)
        self.assertEqual((data[:6], data[-1], data.count(descriptor)), (b"GIF89a", 0x3B, 3))
        self.assertEqual(struct.unpack_from("<HH", data, 6), (16, 12))
        self.assertIn(b"NETSCAPE2.0", data)
        interlaced = images.gif(16, 12, seed="t", interlaced=True)
        self.assertEqual(interlaced[interlaced.index(descriptor) + 9], 0x40)

    def test_bmp_header_sizes_agree_with_the_file(self):
        data = images.bmp(5, 3, seed="t")
        size, _, _, offset = struct.unpack_from("<IHHI", data, 2)
        width, height = struct.unpack_from("<ii", data, 18)
        self.assertEqual((size, offset, width, height), (len(data), 54, 5, 3))
        self.assertEqual(len(data) - offset, 3 * 16)

    def test_webp_riff_sizes_and_chunk_walk(self):
        for mode in ("lossy", "lossless", "alpha", "animated"):
            data = images.webp(32, 16, seed="t", mode=mode, exif=b"II*\0", xmp_packet=b"<x/>")
            self.assertEqual((data[:4], data[8:12], struct.unpack_from("<I", data, 4)[0]), (b"RIFF", b"WEBP", len(data) - 8))
            pos, tags = 12, []
            while pos < len(data):
                tag, size = struct.unpack_from("<4sI", data, pos)
                tags.append(tag)
                pos += 8 + size + size % 2
            self.assertEqual(pos, len(data), mode)
            self.assertEqual(tags[0], b"VP8X")
            self.assertTrue({b"EXIF", b"XMP "} <= set(tags))
        self.assertEqual(images.webp(32, 16, seed="t")[12:16], b"VP8 ")
        self.assertEqual(images.webp(32, 16, seed="t", mode="lossless")[12:16], b"VP8L")


class TiffImages(unittest.TestCase):
    def test_strip_offset_points_at_the_pixels(self):
        for order in ("<", ">"):
            data = images.tiff_image(8, 4, seed="t", e=order, make="Cam", bits=16, samples=3)
            _, zero = read_tiff(data)
            self.assertEqual((zero[0x0100], zero[0x0101], zero[0x0117], zero[0x010F]), (8, 4, 8 * 4 * 3 * 2, "Cam"))
            self.assertEqual(zero[0x0111] + zero[0x0117], len(data))

    def test_pages_chain(self):
        data = images.tiff_image(4, 4, seed="t", pages=3)
        e, ifd = read_tiff(data)
        count = 1
        while ifd["next"]:
            ifd = read_ifd(data, ifd["next"], e)
            count += 1
        self.assertEqual(count, 3)

    def test_raw_stub_with_embedded_preview(self):
        preview = images.jpeg(160, 120, seed="p")
        data = images.tiff_image(8, 4, seed="t", head4=b"IIRO", thumb=preview, make="OLYMPUS")
        e, zero = read_tiff(data)
        ifd1 = read_ifd(data, zero["next"], e)
        self.assertEqual(data[ifd1[0x0201]:][:ifd1[0x0202]], preview)
        self.assertEqual(data[zero[0x0111]:][:zero[0x0117]], images.raster("t", 8, 4))

    def test_bigtiff_entries_point_at_the_strip(self):
        data = images.bigtiff(4, 4, seed="t")
        (first,) = struct.unpack_from("<Q", data, 8)
        (count,) = struct.unpack_from("<Q", data, first)
        entries = {struct.unpack_from("<H", data, first + 8 + 20 * i)[0]: struct.unpack_from("<Q", data, first + 8 + 20 * i + 12)[0] for i in range(count)}
        self.assertEqual(data[entries[0x0111]:][:entries[0x0117]], images.raster("t", 4, 4))


class MiscStills(unittest.TestCase):
    def test_psd_header_and_psb_version(self):
        data = images.psd(4, 3, seed="t", xmp_packet=b"<x/>")
        self.assertEqual((data[:4], struct.unpack_from(">H", data, 4)[0], struct.unpack_from(">II", data, 14)), (b"8BPS", 1, (3, 4)))
        self.assertEqual(struct.unpack_from(">H", images.psd(4, 3, seed="t", large=True), 4)[0], 2)
        self.assertIn(b"8BIM\x04\x24", data)

    def test_jxl_container_and_bare_codestream(self):
        self.assertTrue(images.jxl(seed="t").startswith(bytes.fromhex("0000000c4a584c200d0a870a")))
        self.assertTrue(images.jxl(seed="t", bare=True).startswith(b"\xff\x0a"))
        self.assertIn(b"jbrd", images.jxl(seed="t", recompressed_jpeg=True))

    def test_pdf_xref_offsets_point_at_objects(self):
        data = images.pdf("Title")
        table = data[data.index(b"xref\n"):].split(b"\n")
        for number, line in enumerate(table[3:8], 1):
            offset = int(line.split()[0])
            self.assertTrue(data[offset:].startswith(f"{number} 0 obj".encode()), line)
        self.assertEqual(int(data.rsplit(b"startxref\n", 1)[1].split()[0]), data.index(b"xref\n"))

    def test_text_formats_are_clean_text(self):
        for blob in (images.svg(10, 10, "t"), images.eps(10, 10)):
            self.assertTrue(blob.endswith(b"\n") and b"\r" not in blob and b"\t" not in blob)
            self.assertNotIn(b" \n", blob)

    def test_filler_is_deterministic_and_marker_free(self):
        self.assertEqual(images.filler("a", 100), images.filler("a", 100))
        self.assertNotEqual(images.filler("a", 100), images.filler("b", 100))
        self.assertNotIn(0xFF, images.filler("a", 5000))


def boxes(data, start=0, end=None):
    """[(type, payload_start, payload_end)] for sibling ISO boxes; fails if sizes do not tile the range."""
    end = len(data) if end is None else end
    out, at = [], start
    while at < end:
        size, kind = struct.unpack_from(">I4s", data, at)
        assert size >= 8 and at + size <= end, (kind, size, at)
        out.append((kind, at + 8, at + size))
        at += size
    assert at == end
    return out


def find_box(data, path, start=0, end=None):
    """(payload_start, payload_end) of the box at path; meta and stsd children start after their header fields."""
    for kind, begin, finish in boxes(data, start, end):
        if kind == path[0]:
            if len(path) == 1:
                return begin, finish
            return find_box(data, path[1:], begin + {b"meta": 4, b"stsd": 8}.get(kind, 0), finish)
    raise AssertionError(f"no {path[0]!r}")


class IsoBoxes(unittest.TestCase):
    def test_mp4_tiles_with_boxes_and_carries_the_clock(self):
        stamp = containers.qt_seconds(2019, 5, 9, 15, 47, 33)
        self.assertEqual(stamp, 1557416853 + 2082844800)
        data = containers.mp4(seed="a", created=stamp, duration_ms=2500, width=640, height=360, rotation=90)
        self.assertEqual([b[0] for b in boxes(data)], [b"ftyp", b"moov", b"mdat"])
        begin, _ = find_box(data, [b"moov", b"mvhd"])
        self.assertEqual(struct.unpack_from(">IIII", data, begin + 4), (stamp, stamp, 1000, 2500))
        begin, _ = find_box(data, [b"moov", b"trak", b"tkhd"])
        self.assertEqual(struct.unpack_from(">II", data, begin + 4), (stamp, stamp))
        self.assertEqual(struct.unpack_from(">4i", data, begin + 40)[:2], (0, 0x10000))
        self.assertEqual(struct.unpack_from(">II", data, begin + 76), (640 << 16, 360 << 16))

    def test_zero_clock_when_not_created(self):
        data = containers.mp4(seed="a")
        begin, _ = find_box(data, [b"moov", b"mvhd"])
        self.assertEqual(struct.unpack_from(">II", data, begin + 4), (0, 0))

    def test_sample_entry_dimensions_and_codec(self):
        for codec, fourcc in (("h264", b"avc1"), ("hevc", b"hvc1"), ("av1", b"av01"), ("vp9", b"vp09")):
            data = containers.mp4(seed="a", codec=codec, width=1280, height=720)
            begin, end = find_box(data, [b"moov", b"trak", b"mdia", b"minf", b"stbl", b"stsd"])
            begin += 8
            (kind, entry, _), = boxes(data, begin, end)
            self.assertEqual(kind, fourcc)
            self.assertEqual(struct.unpack_from(">HH", data, entry + 24), (1280, 720))

    def test_metadata_keys_and_xyz(self):
        data = containers.mp4(seed="a", keys=[("com.apple.quicktime.creationdate", "2019-05-09T15:47:33+0200")],
                              xyz="+48.8584+002.2945/")
        self.assertIn(b"com.apple.quicktime.creationdate", data)
        self.assertIn(b"\xa9xyz", data)
        self.assertIn(b"+48.8584+002.2945/", data)

    def test_truncate_cuts_the_file(self):
        self.assertEqual(len(containers.mp4(seed="a", truncate=100)), 100)

    def test_heif_item_offsets_point_at_item_data(self):
        exif = tiffexif.exif_block(make="Apple", model="iPhone", original="2019:05:09 15:47:33")
        data = containers.heif(seed="a", codec="hevc", width=64, height=48, brand=b"heic", compat=(b"mif1", b"heic"),
                               exif=exif, xmp_packet=b"<x/>", rotation=1)
        self.assertEqual(data[4:12], b"ftypheic")
        top = [b[0] for b in boxes(data)]
        self.assertEqual(top, [b"ftyp", b"meta", b"mdat"])
        meta_begin, meta_end = find_box(data, [b"meta"])
        meta_begin += 4
        kids = {kind: (b, e) for kind, b, e in boxes(data, meta_begin, meta_end)}
        self.assertEqual(set(kids), {b"hdlr", b"pitm", b"iloc", b"iinf", b"iprp"} | {b"iref"})
        begin, _ = kids[b"iloc"]
        (count,) = struct.unpack_from(">H", data, begin + 6)
        self.assertEqual(count, 3)
        located = []
        for index in range(count):
            number, _, _, offset, length = struct.unpack_from(">HHHII", data, begin + 8 + 14 * index)
            located.append((number, offset, length))
        self.assertEqual(data[located[1][1]:][:10], struct.pack(">I", 6) + b"Exif\0\0")
        self.assertEqual(data[located[1][1] + 10:][:2], b"II")
        self.assertEqual(data[located[2][1]:][:located[2][2]], b"<x/>")
        self.assertEqual(located[0][1], find_box(data, [b"mdat"])[0])

    def test_heif_grid_av1_and_aux(self):
        data = containers.heif(seed="a", codec="av1", width=128, height=96, brand=b"avif", compat=(b"avif", b"mif1"),
                               grid=(2, 2), aux=[("urn:com:apple:photo:2020:aux:hdrgainmap", 64, 48)])
        self.assertIn(b"grid", data)
        self.assertIn(b"av1C", data)
        self.assertIn(b"auxC", data)
        self.assertIn(b"auxl", data)
        self.assertEqual(data.count(b"dimg"), 1)

    def test_heif_tone_map_and_stereo(self):
        data = containers.heif(seed="a", codec="hevc", width=64, height=48, brand=b"heic", compat=(b"mif1",), tmap=True)
        self.assertIn(b"tmap", data)
        self.assertIn(b"ster", containers.heif(seed="a", codec="hevc", width=64, height=48, brand=b"mif1",
                                               compat=(b"mif1",), stereo=True))

    def test_cr3_has_canon_uuid_exif_blocks_and_preview(self):
        preview = images.jpeg(160, 120, seed="p")
        data = containers.cr3(seed="a", make="Canon", model="Canon EOS R5", width=8192, height=5464,
                              original="2020:01:02 03:04:05", preview=preview)
        self.assertEqual(data[4:12], b"ftypcrx ")
        begin, end = find_box(data, [b"moov", b"uuid"])
        self.assertEqual(data[begin:begin + 16].hex(), "85c0b687820f11e08111f4ce462b6a48")
        names = [b[0] for b in boxes(data, begin + 16, end)]
        self.assertEqual(names, [b"CNCV", b"CMT1", b"CMT2", b"THMB"])
        thmb = boxes(data, begin + 16, end)[3]
        self.assertEqual(data[thmb[1] + 16:thmb[2]], preview)
        cmt1 = boxes(data, begin + 16, end)[1]
        self.assertEqual(read_tiff(data[cmt1[1]:cmt1[2]])[1][0x0110], "Canon EOS R5")

    def test_sef_trailer_ends_with_directory_length_and_magic(self):
        trailer = containers.sef_trailer([("MotionPhoto_Data", b"x" * 10)])
        self.assertEqual(trailer[-4:], b"SEFT")
        directory = struct.unpack_from("<I", trailer, len(trailer) - 8)[0]
        self.assertEqual(trailer[len(trailer) - 8 - directory:][:4], b"SEFH")


class Picture(unittest.TestCase):
    def test_rows_have_the_size_and_share_equal_rows(self):
        rows = picture.rows("folder/case.jpg", 100, 60)
        self.assertEqual((len(rows), {len(row) for row in rows}), (60, {300}))
        self.assertIs(rows[-1], rows[-2])

    def test_the_name_sits_top_left_on_black_above_the_bars(self):
        rows = picture.rows("folder/case.jpg", 160, 120)
        scale, lines = picture.layout("case.jpg", 160, 120)
        self.assertEqual(lines, ["CASE.JPG"])
        self.assertEqual(rows[0], bytes(480))
        self.assertIn(b"\xff", rows[scale])
        self.assertIn(tuple(rows[-1][:3]), picture.BARS)

    def test_the_bars_follow_the_seed_and_the_frame(self):
        self.assertNotEqual(picture.rows("a/x.jpg", 160, 120)[-1], picture.rows("b/x.jpg", 160, 120)[-1])
        self.assertNotEqual(picture.rows("a/x.jpg", 160, 120)[-1], picture.rows("a/x.jpg", 160, 120, frame=1)[-1])

    def test_large_scales_fill_whole_blocks_and_long_names_wrap(self):
        self.assertEqual(picture.layout("IMG_20190509_154733.jpg", 6000, 4000)[0] % 8, 0)
        scale, lines = picture.layout("a" * 40, 160, 120)
        self.assertEqual(("".join(lines), max(map(len, lines)) <= (160 - 2 * scale) // (4 * scale)), ("A" * 40, True))
        self.assertEqual(picture.layout("ü", 160, 120)[1], ["?"])

    def test_deflate_round_trips_through_zlib(self):
        for raw in (b"", b"a", bytes(1000), b"abc" * 300 + bytes(70000), bytes(range(256)) * 3):
            self.assertEqual(zlib.decompress(picture.deflate(raw)), raw)
        self.assertLess(len(picture.deflate(bytes(10000))), 100)


class OtherContainers(unittest.TestCase):
    def test_mkv_and_webm_start_with_ebml_header_and_doctype(self):
        for doctype in ("matroska", "webm"):
            data = containers.mkv(seed="a", doctype=doctype)
            self.assertEqual(data[:4], bytes.fromhex("1A45DFA3"))
            self.assertIn(b"\x42\x82" + bytes([0x80 | len(doctype)]) + doctype.encode(), data)
            size = data[4] & 0x7F
            self.assertEqual(data[5 + size:][:4], bytes.fromhex("18538067"))

    def test_vint_round_trips_sizes(self):
        self.assertEqual(containers.vint(5), b"\x85")
        self.assertEqual(containers.vint(200), b"\x40\xc8")
        self.assertEqual(containers.vint(127), b"\x40\x7f")

    def test_mpeg_crc_matches_the_standard_check_value(self):
        self.assertEqual(containers.mpeg_crc(b"123456789"), bytes.fromhex("0376e6e7"))

    def test_transport_stream_sync_bytes_and_psi_crc(self):
        data = containers.mpegts(seed="a", packets=6)
        self.assertEqual(len(data), 6 * 188)
        self.assertTrue(all(data[i * 188] == 0x47 for i in range(6)))
        pat = data[5:5 + 12]
        self.assertEqual(data[5 + 12:][:4], containers.mpeg_crc(pat))

    def test_m2ts_has_timestamp_prefix(self):
        data = containers.mpegts(seed="a", packets=4, m2ts=True)
        self.assertEqual(len(data), 4 * 192)
        self.assertTrue(all(data[i * 192 + 4] == 0x47 for i in range(4)))

    def test_avi_riff_size_stream_header_and_index(self):
        data = containers.avi(seed="a", width=32, height=16, compression=b"MJPG", frames=3)
        self.assertEqual((data[:4], data[8:12]), (b"RIFF", b"AVI "))
        self.assertEqual(struct.unpack_from("<I", data, 4)[0], len(data) - 8)
        self.assertIn(b"vidsMJPG", data)
        movi, index = data.index(b"movi"), data.index(b"idx1") + 8
        frames = [struct.unpack_from("<4sIII", data, index + 16 * i) for i in range(3)]
        for kind, _, offset, size in frames:
            self.assertEqual((kind, data[movi + offset:][:4]), (b"00dc", b"00dc"))
            self.assertEqual(data[movi + offset + 8:][:size], images.jpeg(32, 16, seed="a"))

    def test_mjpeg_quicktime_sample_table_finds_the_frames(self):
        data = containers.mp4(seed="a", codec="mjpeg", width=32, height=16, duration_ms=300, brand=b"qt  ")
        stbl = find_box(data, [b"moov", b"trak", b"mdia", b"minf", b"stbl"])
        stsz, stco = find_box(data, [b"stsz"], *stbl), find_box(data, [b"stco"], *stbl)
        _, count = struct.unpack_from(">II", data, stsz[0] + 4)
        sizes = struct.unpack_from(f">{count}I", data, stsz[0] + 12)
        (offset,) = struct.unpack_from(">I", data, stco[0] + 8)
        frame = images.jpeg(32, 16, seed="a")
        self.assertEqual((count, offset), (3, find_box(data, [b"mdat"])[0]))
        self.assertEqual(data[offset:offset + sum(sizes)], frame * 3)

    def test_asf_header_object_sizes(self):
        data = containers.asf(seed="a")
        self.assertEqual(data[:16].hex(), "3026b2758e66cf11a6d900aa0062ce6c")
        header_size = struct.unpack_from("<Q", data, 16)[0]
        self.assertEqual(data[header_size:][:16].hex(), "3626b2758e66cf11a6d900aa0062ce6c")
        self.assertEqual(struct.unpack_from("<Q", data, header_size + 16)[0], len(data) - header_size)

    def test_flv_header_and_first_tags(self):
        data = containers.flv(seed="a")
        self.assertEqual(data[:5], b"FLV\x01\x01")
        self.assertEqual(struct.unpack_from(">I", data, 5)[0], 9)
        size = int.from_bytes(data[14:17], "big")
        self.assertEqual((data[13], struct.unpack_from(">I", data, 13 + 11 + size)[0]), (18, 11 + size))
        self.assertEqual(data[13 + 11 + size + 4], 9)

    def test_mpeg_program_stream_start_codes(self):
        data = containers.mpeg_ps(seed="a")
        self.assertTrue(data.startswith(b"\x00\x00\x01\xba"))
        self.assertIn(b"\x00\x00\x01\xbb", data)
        self.assertIn(b"\x00\x00\x01\xb3", data)

    def test_raf_offsets_point_at_the_embedded_jpeg(self):
        jpeg = images.jpeg(32, 24, [], seed="a")
        data = containers.raf(seed="a", model="X100V", jpeg_bytes=jpeg)
        self.assertTrue(data.startswith(b"FUJIFILMCCD-RAW "))
        offset, length = struct.unpack_from(">II", data, 84)
        self.assertEqual(data[offset:offset + length], jpeg)
        self.assertEqual(data[offset:offset + 2], b"\xff\xd8")

    def test_ogg_page_and_unknown_blob(self):
        self.assertTrue(containers.ogg(seed="a").startswith(b"OggS"))
        self.assertNotIn(b"\xff\xd8", containers.unknown(seed="a")[:4])

    def test_builders_are_deterministic(self):
        self.assertEqual(containers.mp4(seed="a"), containers.mp4(seed="a"))
        self.assertNotEqual(containers.mp4(seed="a"), containers.mp4(seed="b"))


if __name__ == "__main__":
    unittest.main()
