"""Still images: every format and container variant, HDR gain maps, RAW stubs."""
import captime
import containers
import images
import tiffexif
from entries import add
from recipes import shot

CANON = "Canon EOS 5D Mark IV"
APPLE = "iPhone 13 Pro"
PIXEL = "Pixel 7"
SYDNEY = (-33.8688, 151.2093, 58.5, "2019-05-09T05:47:33")
PARIS = (48.8584, 2.2945, 35.0, "2021-07-14T10:15:42")
SMALL = (160, 120)  # the size of rasters whose case is not about their size
XMP_DATE = images.xmp({"xmp": {"CreateDate": "2018-08-20T09:30:15+02:00"}})
XMP_CLAIM = captime.claim("xmp_date_with_offset", "2018-08-20T09:30:15", "s", offset="+02:00")
XMP_RESOLVED = captime.resolve("xmp_date_with_offset", local="2018-08-20T09:30:15", offset="+02:00")


def jpg(path, w, h, make, model, local, offset=None, *, vendor=None, quirks=(), jpeg=None, fmt="jpeg", entry=None,
        more=(), outcome=None, xmp=None, video=None, sef=None, meta_extra=None, **options):
    """A JPEG with an EXIF block (options go to recipes.shot), optional XMP and an optional appended video: raw, or
    inside a Samsung SEF block named sef. entry holds further entries.add arguments, more are extra claims and
    outcome replaces the expected resolution."""
    block, meta, claims, resolved = shot(make, model, local, offset, size=(w, h), **options)
    segments = [images.exif_segment(block)] + ([images.xmp_segment(xmp)] if xmp else [])
    data = images.jpeg(w, h, segments, seed=path, **(jpeg or {}))
    if video:
        start = len(data)
        if sef:
            data += containers.sef_trailer([(sef, video)])
            start += 8 + len(sef)
        else:
            data += video
        meta["motion"] = {"offset": start, "length": len(video)}
    meta.update(meta_extra or {})
    return add(path, data, fmt, vendor=vendor, quirks=quirks, meta=meta, claims=claims + list(more),
               resolved=outcome or resolved, **(entry or {}))


def plain(path, data, fmt, w, h, quirks=(), **options):
    return add(path, data, fmt, quirks=quirks, meta={"width": w, "height": h}, **options)


def preview(path):
    return images.jpeg(*SMALL, seed=f"{path} preview")


def jpegs():
    jpg("stills/baseline.jpg", 640, 480, "Canon", CANON, "2019-05-09T15:47:33", vendor="canon")
    jpg("stills/progressive.jpg", 800, 600, "NIKON CORPORATION", "NIKON D850", "2020-02-29T18:03:11", "+01:00",
        vendor="nikon", quirks=["progressive"], jpeg={"progressive": True})
    plain("stills/cmyk.jpg", images.jpeg(320, 240, [], seed="stills/cmyk.jpg", components=4, adobe_transform=2), "jpeg",
          320, 240,
          ["cmyk"])
    secondary = images.jpeg(160, 120, [], seed="stills/mpf-secondary.jpg secondary")
    plain("stills/mpf-secondary.jpg", images.jpeg(640, 480, [], seed="stills/mpf-secondary.jpg", secondary=[secondary]),
          "jpeg", 640, 480, ["mpf"])
    jpg("stills/exif-big-endian.jpg", 640, 480, "OLYMPUS IMAGING CORP.", "E-M1MarkII", "2017-11-05T07:20:00",
        vendor="olympus", quirks=["exif_big_endian"], e=">")
    jpg("stills/exif-thumbnail.jpg", 640, 480, "SONY", "ILCE-7M3", "2022-09-18T16:45:09", "+09:00", vendor="sony",
        quirks=["embedded_preview"], thumb=images.jpeg(160, 120, [], seed="stills/exif-thumbnail.jpg thumbnail"))
    jpg("stills/gps-sydney.jpg", 640, 480, "samsung", "SM-S911B", "2019-05-09T15:47:33", vendor="samsung", gps=SYDNEY)


def small(path, build, fmt, quirks=(), entry=None, **options):
    """A 160 x 120 raster of the picture: build(160, 120, seed=path, **options); entry goes to entries.add."""
    return plain(path, build(*SMALL, seed=path, **options), fmt, *SMALL, quirks, **(entry or {}))


def rasters():
    small("stills/rgb.png", images.png, "png")
    small("stills/rgba.png", images.png, "png", ["alpha"], color=6)
    small("stills/palette.png", images.png, "png", color=3)
    small("stills/grey16.png", images.png, "png", ["bit_depth_16"], color=0, depth=16)
    small("stills/interlaced.png", images.png, "png", ["interlaced"], interlace=1)
    block, meta, claims, resolved = shot("Google", PIXEL, "2023-03-30T18:41:38", "-04:00", size=SMALL)
    add("stills/exif-chunk.png", images.png(*SMALL, seed="stills/exif-chunk.png", exif=block), "png", vendor="google",
        meta=meta, claims=claims, resolved=resolved)
    small("stills/xmp-itxt.png", images.png, "png", entry={"claims": [XMP_CLAIM], "resolved": XMP_RESOLVED},
          itxt_xmp=XMP_DATE)
    small("stills/animated.apng", images.png, "apng", ["animated"], frames=3)
    small("stills/static.gif", images.gif, "gif")
    small("stills/animated.gif", images.gif, "gif", ["animated"], frames=3)
    small("stills/interlaced.gif", images.gif, "gif", ["interlaced"], interlaced=True)
    small("stills/24bit.bmp", images.bmp, "bmp")
    small("stills/lossy.webp", images.webp, "webp")
    for mode in ("lossless", "alpha", "animated"):
        small(f"stills/{mode}.webp", images.webp, "webp", [mode], mode=mode)
    block, meta, claims, resolved = shot("Apple", APPLE, "2021-07-14T12:15:42", "+02:00", size=SMALL)
    add("stills/exif-chunk.webp", images.webp(*SMALL, seed="stills/exif-chunk.webp", exif=block), "webp",
        vendor="apple", meta=meta, claims=claims, resolved=resolved)


def heic(path, vendor="apple", model=APPLE, quirks=(), codec="hevc", brand=b"heic", w=4032, h=3024, depth=8,
         local="2021-07-14T12:15:42", offset="+02:00", orientation=None, gps=PARIS, entry=None, maker_note=None,
         motion=None, more=(), outcome=None, **options):
    """A HEIC (hevc) or AVIF (av1) still; options go to containers.heif, entry to entries.add."""
    block, meta, claims, resolved = shot("Apple" if vendor == "apple" else "Google", model, local, offset,
                                         size=(w, h), gps=gps, orientation=orientation, maker_note=maker_note)
    meta.pop("orientation", None)
    if "heif_irot" in quirks:
        meta["orientation"] = 6
    if "heif_imir" in quirks:
        meta["orientation"] = 4
    compat = (b"mif1", brand) if codec == "hevc" else (b"avif", b"mif1")
    data = containers.heif(seed=path, codec=codec, width=w, height=h, brand=brand, compat=compat, depth=depth,
                           exif=block, trailer=containers.mpvd(motion) if motion else b"", **options)
    if motion:
        meta["motion"] = {"offset": len(data) - len(motion), "length": len(motion)}
    fmt = "heic" if codec == "hevc" else "avif"
    return add(path, data, fmt, vendor=vendor, quirks=quirks, meta=meta, claims=claims + list(more),
               resolved=outcome or resolved, **(entry or {}))


def heifs():
    heic("stills/iphone.heic")
    heic("stills/grid.heic", quirks=["heif_grid"], grid=(2, 2))
    heic("stills/irot.heic", quirks=["heif_irot"], rotation=3)
    heic("stills/imir.heic", quirks=["heif_imir"], mirror=0)
    heic("stills/clap.heic", quirks=["heif_clap"], clap=(4000, 1, 3000, 1, 0, 1, 0, 1))
    heic("stills/alpha-aux.heic", quirks=["heif_aux_image"], aux=[("urn:mpeg:hevc:2015:auxid:1", 4032, 3024)])
    heic("stills/10bit.heic", quirks=["bit_depth_10"], depth=10)
    heic("stills/8bit.avif", vendor="google", model=PIXEL, codec="av1", brand=b"avif", local="2023-10-26T21:06:42",
         offset="-07:00", gps=None)
    heic("stills/10bit.avif", vendor="google", model=PIXEL, codec="av1", brand=b"avif", quirks=["bit_depth_10"],
         depth=10, local="2023-10-26T21:06:43", offset="-07:00", gps=None)
    heic("stills/12bit.avif", vendor="google", model=PIXEL, codec="av1", brand=b"avif", quirks=["bit_depth_12"],
         depth=12, local="2023-10-26T21:06:44", offset="-07:00", gps=None)


def modern_formats():
    block, meta, claims, resolved = shot("Canon", CANON, "2019-05-09T15:47:33", size=(64, 48))
    add("stills/container.jxl", images.jxl(seed="jxl", exif=block, xmp_packet=images.xmp({"xmp": {"Rating": "3"}})),
        "jxl", vendor="canon", meta=meta, claims=claims, resolved=resolved)
    plain("stills/codestream.jxl", images.jxl(seed="bare", bare=True), "jxl", 64, 48)
    plain("stills/recompressed.jxl", images.jxl(seed="jbrd", recompressed_jpeg=True), "jxl", 64, 48,
          ["jxl_recompressed_jpeg"])
    small("stills/rgb.tif", images.tiff_image, "tiff", samples=3)
    small("stills/16bit.tif", images.tiff_image, "tiff", ["bit_depth_16"], bits=16, samples=3)
    small("stills/float.tif", images.tiff_image, "tiff", ["float"], bits=32, sample_format=3)
    small("stills/multipage.tif", images.tiff_image, "tiff", ["multipage"], pages=3)
    small("stills/bigtiff.tif", images.bigtiff, "tiff", ["bigtiff"])
    fields, claims, resolved = captime.exif_time("2019-05-09T15:47:33")
    add("stills/big-endian.tif", images.tiff_image(*SMALL, seed="stills/big-endian.tif", e=">", make="Canon",
                                                   model=CANON, **fields),
        "tiff", vendor="canon", quirks=["exif_big_endian"],
        meta={"width": SMALL[0], "height": SMALL[1], "make": "Canon", "model": CANON}, claims=claims, resolved=resolved)
    small("stills/layered.psd", images.psd, "psd", xmp_packet=images.xmp({"xmp": {"Rating": "1"}}))
    small("stills/large.psb", images.psd, "psb", large=True)
    plain("stills/vector.svg", images.svg(100, 80, "stills/vector.svg"), "svg", 100, 80)
    add("stills/document.pdf", images.pdf("Document"), "pdf")
    plain("stills/artwork.eps", images.eps(100, 80), "eps", 100, 80)


# What tells a TIFF-based RAW's format besides its maker (NEF, ARW and PEF have only that): a signature or DNGVersion.
SIGNATURES = {"cr2": {"extra": b"CR\x02\x00" + bytes(4)}, "orf": {"head4": b"IIRO"}, "rw2": {"head4": b"IIU\0"},
              "dng": {"entries0": [(0xC612, tiffexif.BYTE, [1, 4, 0, 0])]}}


def raw_tiff(path, fmt, **tiff):
    """A TIFF-based RAW stub's bytes: real IFDs and EXIF, a greyscale picture for sensor data, a JPEG preview, and the
    signature of its format."""
    return images.tiff_image(*SMALL, seed=path, thumb=preview(path), **{**SIGNATURES.get(fmt, {}), **tiff})


def raw(path, fmt, vendor, make, model, local, offset=None, quirks=(), entry=None, more=(), subsec=None,
        orientation=None, **tiff):
    """A TIFF-based RAW stub with its camera and time. As in a camera's, the preview is stored as the sensor saw it
    and IFD0's orientation says how to turn both."""
    fields, claims, resolved = captime.exif_time(local, offset, subsec)
    data = raw_tiff(path, fmt, make=make, model=model, orientation=orientation, **fields, **tiff)
    meta = {"width": SMALL[0], "height": SMALL[1], "make": make, "model": model}
    if orientation:
        meta["orientation"] = orientation
    return add(path, data, fmt, vendor=vendor, quirks=quirks, meta=meta, claims=claims + list(more), resolved=resolved,
               **(entry or {}))


def raws():
    """Every RAW format, shot turned (6 and 8 with the camera on its side, 3 upside down) but the DNG whose sensor
    data decodes, as Pillow would turn it too."""
    raw("raw/canon.cr2", "cr2", "canon", "Canon", CANON, "2018-06-02T10:20:30", quirks=["embedded_preview"],
        orientation=8)
    raw("raw/nikon.nef", "nef", "nikon", "NIKON CORPORATION", "NIKON D850", "2019-10-03T06:30:00", orientation=6)
    raw("raw/sony.arw", "arw", "sony", "SONY", "ILCE-7RM4", "2021-03-14T14:15:16", "+01:00", orientation=8)
    raw("raw/olympus.orf", "orf", "olympus", "OLYMPUS CORPORATION", "E-M5", "2016-08-08T08:08:08", orientation=6)
    raw("raw/panasonic.rw2", "rw2", "panasonic", "Panasonic", "DC-GH5", "2017-01-21T11:22:33", orientation=3)
    raw("raw/pentax.pef", "pef", "pentax", "PENTAX Corporation", "PENTAX K-1", "2015-12-24T17:00:01", orientation=8)
    raw("raw/generic.dng", "dng", None, "Leica Camera AG", "LEICA M10", "2018-04-12T19:24:49")
    raw("raw/jpegxl.dng", "dng", None, "Leica Camera AG", "LEICA SL3", "2024-05-05T12:00:00", "+02:00",
        quirks=["dng_jxl"], compression=52546, entries0=[(0xC612, tiffexif.BYTE, [1, 7, 1, 0])], orientation=8)
    raw("raw/proraw.dng", "dng", "apple", "Apple", "iPhone 15 Pro", "2024-01-10T09:00:00", "-05:00", quirks=["proraw"],
        photometric=34892, entries0=[(0xC612, tiffexif.BYTE, [1, 6, 0, 0])], orientation=6)
    fields, claims, resolved = captime.exif_time("2020-01-02T03:04:05", "+01:00")
    meta = {"width": 8192, "height": 5464, "orientation": 6, "make": "Canon", "model": "Canon EOS R5"}
    add("raw/canon.cr3", containers.cr3(seed="cr3", make="Canon", model="Canon EOS R5", width=8192, height=5464,
                                        original=fields["original"], offsets=fields["offsets"], orientation=6,
                                        preview=preview("raw/canon.cr3")),
        "cr3", vendor="canon", meta=meta, claims=claims, resolved=resolved)
    # The orientation of a RAF is its JPEG's.
    block, meta, claims, resolved = shot("FUJIFILM", "X-T4", "2022-05-01T10:11:12", size=(160, 120), orientation=8)
    embedded = images.jpeg(160, 120, [images.exif_segment(block)], seed="raw/fuji.raf")
    add("raw/fuji.raf", containers.raf(seed="raf", model="X-T4", jpeg_bytes=embedded), "raf", vendor="fujifilm",
        quirks=["embedded_preview"], meta=meta, claims=claims, resolved=resolved)


def hdr():
    gain_xmp = images.xmp({"hdrgm": {"Version": "1.0", "GainMapMin": "0", "GainMapMax": "2.5", "Gamma": "1",
                                     "HDRCapacityMin": "0", "HDRCapacityMax": "2.5", "BaseRenditionIsHDR": "False"}})
    gain = images.jpeg(1008, 756, [images.xmp_segment(gain_xmp)], seed="hdr/ultra-hdr.jpg gain map")
    directory = images.container_directory([("image/jpeg", "Primary", 0), ("image/jpeg", "GainMap", len(gain))])
    block, meta, claims, resolved = shot("Google", "Pixel 8 Pro", "2023-10-12T08:11:20", "-07:00", size=(4032, 3024))
    primary = images.xmp({"hdrgm": {"Version": "1.0"}, "Container": {}, "Item": {}}, directory)
    data = images.jpeg(4032, 3024, [images.exif_segment(block), images.xmp_segment(primary)], seed="hdr/ultra-hdr.jpg",
                       secondary=[gain])
    add("hdr/ultra-hdr.jpg", data, "jpeg", vendor="google", quirks=["ultra_hdr", "mpf"], meta=meta, claims=claims,
        resolved=resolved)
    block, meta, claims, resolved = shot("samsung", "SM-S918B", "2023-05-20T13:14:15", "+09:00", size=(4000, 3000))
    path = "hdr/samsung-gain-map.jpg"
    trailer = containers.sef_trailer([("Gain_Map_Image", images.jpeg(1000, 750, seed=f"{path} gain map"))])
    add(path, images.jpeg(4000, 3000, [images.exif_segment(block)], seed=path, tail=trailer),
        "jpeg", vendor="samsung", quirks=["gain_map_samsung", "trailing_data"], meta=meta, claims=claims,
        resolved=resolved)

    def heif(path, quirks, **options):
        block, meta, claims, resolved = shot("Apple", "iPhone 15 Pro", "2024-02-03T16:30:45", "+01:00",
                                             size=(4032, 3024))
        data = containers.heif(seed=path, codec="hevc", width=4032, height=3024, brand=b"heic",
                               compat=(b"mif1", b"heic"), exif=block, **options)
        add(path, data, "heic", vendor="apple", quirks=quirks, meta=meta, claims=claims, resolved=resolved)

    heif("hdr/apple-gain-map.heic", ["gain_map_apple", "heif_aux_image"],
         aux=[("urn:com:apple:photo:2020:aux:hdrgainmap", 2016, 1512)])
    heif("hdr/iso-gain-map.heic", ["gain_map_iso"], tmap=True)
    heif("hdr/pq-10bit.heic", ["hdr_pq", "bit_depth_10"], depth=10, colr=(9, 16, 9))
    for path, quirk, transfer in (("hdr/pq.avif", "hdr_pq", 16), ("hdr/hlg.avif", "hdr_hlg", 18)):
        data = containers.heif(seed=path, codec="av1", width=3840, height=2160, brand=b"avif",
                               compat=(b"avif", b"mif1"), depth=10, colr=(9, transfer, 9))
        add(path, data, "avif", quirks=[quirk, "bit_depth_10"], meta={"width": 3840, "height": 2160})


def register():
    jpegs()
    rasters()
    heifs()
    modern_formats()
    raws()
    hdr()
