"""Files whose name is the only (or the decisive) clue: one or more samples for each filename rule F01 to F56,
messenger and screenshot copies, and Google Takeout exports with their JSON sidecars."""
import json
from datetime import UTC, datetime

import captime
import containers
import images
import tiffexif
from catalog_stills import APPLE, PIXEL, SMALL, heic, jpg, raw_tiff
from catalog_video import clip
from entries import ENTRIES, add

VIDEO = {"mp4", "mov", "3gp", "webm"}
RAW = {"cr2": "canon", "nef": "nikon", "arw": "sony", "raf": "fujifilm", "orf": "olympus", "rw2": None, "pef": "pentax",
       "dng": None}
# The maker, which alone tells these formats from a plain TIFF.
MAKES = {"nef": "NIKON CORPORATION", "arw": "SONY", "pef": "PENTAX Corporation"}
CHAT = {"event": "receive", "bound": "upper", "band": "low", "quirks": ("messenger_copy", "upper_bound_name")}
SAVED = dict(CHAT, event="save")
EPOCH = {"kind": "epoch", "band": "low", "quirks": ("epoch_name",)}
EPOCH_SAVED = dict(SAVED, kind="epoch", quirks=("epoch_name", *SAVED["quirks"]))


def epoch(digits):
    """'1703999999999' -> ('2023-12-31T05:19:59.999', 'ms'); ten digits give seconds."""
    stamp = datetime.fromtimestamp(int(digits[:10]), UTC).strftime("%Y-%m-%dT%H:%M:%S")
    return (f"{stamp}.{digits[10:]}", "ms") if len(digits) > 10 else (stamp, "s")


def stub(path):
    """A file of the type the extension says: (data, format, metadata, quirks)."""
    ext = path.rsplit(".", 1)[-1].lower() if "." in path.rsplit("/", 1)[-1] else ""
    if ext in ("jpg", "jpeg"):
        return images.jpeg(640, 480, [], seed=path), "jpeg", {"width": 640, "height": 480}, ()
    if ext in ("png", "webp", "gif"):
        return getattr(images, ext)(*SMALL, seed=path), ext, {"width": SMALL[0], "height": SMALL[1]}, ()
    if ext == "heic":
        data = containers.heif(seed=path, codec="hevc", width=4032, height=3024, brand=b"heic",
                               compat=(b"mif1", b"heic"))
        return data, "heic", {"width": 4032, "height": 3024}, ()
    if ext in ("mp4", "mov"):
        qt = ext == "mov"
        data = containers.mp4(seed=path, brand=b"qt  " if qt else b"isom", compat=(b"qt  ",) if qt else (b"isom",))
        meta = {"width": 1920, "height": 1080, "duration_ms": 3000, "codec": "h264"}
        return data, ext, meta, ("mvhd_zero",)
    if ext == "webm":
        meta = {"width": 1280, "height": 720, "duration_ms": 5000, "codec": "vp9"}
        return containers.mkv(seed=path, doctype="webm", codec_id="V_VP9"), "webm", meta, ()
    if ext == "pdf":
        return images.pdf("Document"), "pdf", {}, ()
    if ext == "raf":
        return containers.raf(seed=path, model="X-T4", jpeg_bytes=images.jpeg(*SMALL, seed=path)), "raf", \
            {"width": SMALL[0], "height": SMALL[1]}, ()
    if ext in RAW:
        make = MAKES.get(ext)
        meta = {"width": SMALL[0], "height": SMALL[1], **({"make": make} if make else {})}
        return raw_tiff(path, ext, make=make), ext, meta, ()
    raise ValueError(f"no stub for {path}")


def precision_of(value):
    return {4: "year", 7: "month", 10: "day", 16: "min", 19: "s"}.get(len(value), "ms")


def named(name, rule=None, value=None, *, folder="names/", kind="local", event="capture", band="medium", bound="exact",
          vendor=None, quirks=(), burst=None, stored=None, rules=(), notes=None, sidecars=(), rejected=None,
          before=(), also=(), outcome=None, entry=None, data=None, meta_extra=None):
    """One name-only file. value is the time the rule yields ('YYYY-MM-DDTHH:MM:SS', shorter for coarser rules, or
    epoch digits when kind is 'epoch'); None means the name carries no time. kind 'utc' marks a UTC reading, before
    and also are claims to put before and after the name's own, outcome replaces the resolution, stored is the on-disk
    name when the original has characters that are not portable; meta_extra is merged into the metadata."""
    shown = stored or name
    path = folder + shown
    blob, fmt, meta, extra = stub(path) if data is None else data
    ext = shown.rsplit(".", 1)[-1].lower() if "." in shown else ""
    if event == "capture" and ext in VIDEO:
        event = "record_start"
    claims, resolved = [], None
    if rule and (value or rejected):
        utc = kind != "local"
        text, precision = (epoch(value) if kind == "epoch" else (value, precision_of(value))) if value else (None, None)
        if rejected:
            claims = [captime.name_claim(rule, text, precision, event, utc=utc, rejected=rejected)]
        else:
            claims, resolved = captime.from_name(rule, text, precision=precision, event=event, band=band, bound=bound,
                                                 utc=True if utc else None, tz="device_default" if utc else "floating")
    options = {"notes": notes, "rules": rules, "sidecars": sidecars}
    if stored:
        options["name"] = name
    if burst:
        options["group"] = {"kind": "burst", "key": burst[0], "role": burst[1]}
    options.update(entry or {})
    return add(path, blob, fmt, vendor=vendor or RAW.get(fmt), quirks=[*quirks, *extra],
               meta={**meta, **(meta_extra or {})}, claims=[*before, *claims, *also], resolved=outcome or resolved,
               **options)


def android_and_oems():
    n = named
    n("IMG_20190509_154733.jpg", "F01", "2019-05-09T15:47:33")
    n("VID_20220107_113306.mp4", "F01", "2022-01-07T11:33:06")
    n("IMG_20190509_154734-edited.jpg", "F01", "2019-05-09T15:47:34")
    n("IMG_20190509_154735~2.jpg", "F01", "2019-05-09T15:47:35")
    n("IMG_20190509_154736_HDR.jpg", "F01", "2019-05-09T15:47:36")
    n("IMG_20190509_154737(1).jpg", "F01", "2019-05-09T15:47:37")
    n("MVIMG_20190215_193501.jpg", "F02", "2019-02-15T19:35:01")
    n("IMG_20190221_112112042.jpg", "F02", "2019-02-21T11:21:12.042")
    n("IMG_20190221_112113042_BURST000_COVER_TOP.MP4", "F02", "2019-02-21T11:21:13.042",
      burst=("20190221_112113042", "burst_cover"), quirks=["burst"])
    n("IMG_20190221_112113042_BURST001.jpg", "F02", "2019-02-21T11:21:13.042",
      burst=("20190221_112113042", "burst_member"), quirks=["burst"])
    pixel = {"kind": "utc", "vendor": "google", "quirks": ("pixel_utc_name",)}
    n("PXL_20231026_210642603.jpg", "F03", "2023-10-26T21:06:42.603", **pixel)
    n("PXL_20230330_184138390.MOTION-01.COVER.jpg", "F03", "2023-03-30T18:41:38.390", **pixel)
    n("PXL_20210101_120000123.NIGHT.jpg", "F03", "2021-01-01T12:00:00.123", **pixel)
    n("PXL_20210101_120500456.PORTRAIT.jpg", "F03", "2021-01-01T12:05:00.456", **pixel)
    n("PXL_20210101_121500000.MP.jpg", "F03", "2021-01-01T12:15:00.000", **pixel)
    n("PXL_20231026_210700001.mp4", "F03", "2023-10-26T21:07:00.001", **pixel)
    jpg("names/PXL_20240612_093015603.jpg", 4080, 3072, "Google", PIXEL, "2024-06-12T12:30:15", "+03:00",
        vendor="google", subsec="603", quirks=["pixel_utc_name"],
        more=[captime.name_claim("F03", "2024-06-12T09:30:15.603", "ms", utc=True)])
    cover = ("BURST20171111030039", "burst_cover")
    member = ("BURST20171111030039", "burst_member")
    n("00001IMG_00001_BURST20171111030039_COVER.jpg", "F04", "2017-11-11T03:00:39", burst=cover, quirks=["burst"])
    n("00002IMG_00002_BURST20171111030039.jpg", "F04", "2017-11-11T03:00:39", burst=member, quirks=["burst"])
    n("00003IMG_00003_BURST20171111030039.jpg", "F04", "2017-11-11T03:00:39", burst=member, quirks=["burst"])
    n("00000PORTRAIT_00000_BURST20190828181853475.jpg", "F04", "2019-08-28T18:18:53.475", quirks=["burst"])
    n("00001IMG_00001_BURST1723801037429_COVER.jpg", "F04", "1723801037429",
      **{**EPOCH, "quirks": ("epoch_name", "burst")})
    n("00004XTR_00004_BURST20190216172030.jpg", "F04", "2019-02-16T17:20:30", quirks=["burst"])
    samsung = {"vendor": "samsung"}
    n("20231207_101605.jpg", "F05", "2023-12-07T10:16:05", **samsung)
    n("20231207_101606_001.jpg", "F05", "2023-12-07T10:16:06", burst=("20231207_101606", "burst_cover"),
      quirks=["burst"], **samsung)
    n("20231207_101606_002.jpg", "F05", "2023-12-07T10:16:06", burst=("20231207_101606", "burst_member"),
      quirks=["burst"], **samsung)
    n("20231207_101607(0).jpg", "F05", "2023-12-07T10:16:07", **samsung)
    n("IMG_20231014_183246_BURST001_COVER.jpg", "F06", "2023-10-14T18:32:46", vendor="huawei",
      burst=("20231014_183246", "burst_cover"), quirks=["burst"])
    n("IMG_20231014_183246_BURST002.jpg", "F06", "2023-10-14T18:32:46", vendor="huawei",
      burst=("20231014_183246", "burst_member"), quirks=["burst"])
    n("IMG20231231123456.jpg", "F07", "2023-12-31T12:34:56", vendor="oneplus")
    n("VID20231231123457.mp4", "F07", "2023-12-31T12:34:57", vendor="oneplus")
    n("IMG_20231231_123456789.jpg", "F08", "2023-12-31T12:34:56.789", vendor="motorola")
    n("DSC_0002_BURST20230115120000123_COVER.JPG", "F09", "2023-01-15T12:00:00.123", vendor="sony", quirks=["burst"],
      burst=("20230115120000123", "burst_cover"))
    n("DSC_0003_BURST20230115120000123.JPG", "F09", "2023-01-15T12:00:00.123", vendor="sony", quirks=["burst"],
      burst=("20230115120000123", "burst_member"))


def counters_and_apps():
    n = named
    counted = {"quirks": ("counter_not_time",)}
    n("IMG_1234.HEIC", "F10", vendor="apple", **counted)
    n("IMG_0005.MOV", "F10", vendor="apple", **counted)
    n("WIN_20231231_12_34_56_Pro.jpg", "F11", "2023-12-31T12:34:56", vendor="microsoft")
    n("WIN_20231231_12_35_10_Pro.mp4", "F11", "2023-12-31T12:35:10", vendor="microsoft")
    shot = {"quirks": ("screenshot",)}
    n("Screenshot_20201215-090626.png", "F12", "2020-12-15T09:06:26", **shot)
    n("Screenshot_20201215-090627-display-1.png", "F12", "2020-12-15T09:06:27", **shot)
    n("Screenshot_20231027_123303_Facebook.jpg", "F13", "2023-10-27T12:33:03", vendor="samsung", **shot)
    n("Screenshot_20190919-053857_Camera-edited.jpg", "F13", "2019-09-19T05:38:57", vendor="samsung", **shot)
    n("Screenshot_2019-04-16-11-19-37-232_com.google.android.youtube.jpg", "F14", "2019-04-16T11:19:37.232",
      vendor="xiaomi", **shot)
    rec = {"quirks": ("screen_recording",)}
    n("screen-20240131-142530.mp4", "F15", "2024-01-31T14:25:30", **rec)
    n("Screen_Recording_20231231-123456_Chrome.mp4", "F16", "2023-12-31T12:34:56", vendor="samsung", **rec)
    n("Screenrecorder-2023-12-31-12-34-56-789.mp4", "F17", "2023-12-31T12:34:56.789", vendor="xiaomi", **rec)
    n("RPReplay_Final1612345678.MP4", "F18", "1612345678", vendor="apple", kind="epoch", band="low",
      quirks=("epoch_name", "screen_recording"))
    n("Screenshot 2019-05-21 at 10.45.52.png", "F19", "2019-05-21T10:45:52", **shot)
    n("Screen Shot 2017-05-21 at 4.45.52 PM.png", "F19", "2017-05-21T16:45:52", **shot)
    n("Screen Recording 2023-12-31 at 12.34.56.mov", "F20", "2023-12-31T12:34:56", **rec)
    n("Screenshot 2023-12-31 123456.png", "F21", "2023-12-31T12:34:56", **shot)
    n("Screenshot (12).png", **shot, notes="Windows numbers its screenshots and records no time")
    n("Screenshot From 2023-12-31 12-34-56.png", "F22", "2023-12-31T12:34:56", **shot)
    n("Screenshot from 2023-12-31 12-34-57-1.png", "F22", "2023-12-31T12:34:57", **shot)
    n("Screencast From 2023-12-31 12-35-00.webm", "F22", "2023-12-31T12:35:00", **rec)
    n("Screenshot_20231231_123456.png", "F23", "2023-12-31T12:34:56", **shot)
    n("2023-12-31_12-34.png", "F24", "2023-12-31T12:34", **shot)
    n("2023-12-31_12-35_1.png", "F24", "2023-12-31T12:35", **shot)
    n("Bildschirmfoto 2019-05-21 um 10.45.52.png", "F54", "2019-05-21", band="low", quirks=("screenshot",
                                                                                          "localized_name"))
    n("スクリーンショット 2023-12-31 12.34.56.png", "F52", "2023-12-31T12:34:56",
      quirks=("screenshot", "localized_name"))


def messengers():
    n = named
    n("IMG-20191120-WA0001.jpg", "F25", "2019-11-20", **CHAT)
    n("VID-20191120-WA0003.mp4", "F25", "2019-11-20", **CHAT)
    n("STK-20191120-WA0005.webp", "F25", "2019-11-20", **CHAT)
    n("DOC-20191120-WA0006.pdf", "F25", "2019-11-20", **CHAT)
    n("WhatsApp Image 2023-05-14 at 10.22.31 AM.jpeg", "F26", "2023-05-14T10:22:31", **CHAT)
    n("WhatsApp Video 2023-05-14 at 4.22.31 PM (1).mp4", "F26", "2023-05-14T16:22:31", **CHAT)
    n("IMG_20231231_123456_789.jpg", "F27", "2023-12-31T12:34:56.789", **SAVED)
    n("VID_20231231_123500_123.mp4", "F27", "2023-12-31T12:35:00.123", **SAVED)
    n("photo_2023-12-31_12-34-56.jpg", "F28", "2023-12-31T12:34:56", **SAVED)
    n("video_2023-12-31_12-35-10 (2).mp4", "F28", "2023-12-31T12:35:10", **SAVED)
    n("telegram_2020-01-30_09-57-18.jpg", "F28", "2020-01-30T09:57:18", **SAVED)
    n("photo_1@31-12-2023_12-34-56.jpg", "F29", "2023-12-31T12:34:56", folder="names/telegram-export/photos/", **CHAT)
    n("signal-2024-01-30-09-57-18-123.jpg", "F30", "2024-01-30T09:57:18.123", **CHAT)
    n("signal-2020-10-26-163832.jpg", "F30", "2020-10-26T16:38:32", **CHAT)
    n("IMG-0a1b2c3d4e5f60718293a4b5c6d7e8f9-V.jpg", "F31", quirks=("counter_not_time", "messenger_copy"))
    n("VID-0a1b2c3d4e5f60718293a4b5c6d7e8fa-V.mp4", "F31", quirks=("counter_not_time", "messenger_copy"))
    n("mmexport1703999999999.jpg", "F32", "1703999999999", **EPOCH_SAVED)
    n("wx_camera_1703999999999.mp4", "F32", "1703999999999", **EPOCH)
    n("KakaoTalk_20231231_123456789.jpg", "F33", "2023-12-31T12:34:56.789", **SAVED)
    n("KakaoTalk_Photo_2023-12-31-12-34-56.jpeg", "F33", "2023-12-31T12:34:56", **SAVED)
    n("LINE_ALBUM_trip_231231_1.jpg", rules=("F34",), quirks=("counter_not_time",),
      notes="LINE has no documented pattern; the registry says to collect real samples before adding a rule")
    n("FB_IMG_1703999999999.jpg", "F35", "1703999999999", **EPOCH_SAVED)
    n("received_1234567890123456.jpeg", quirks=("counter_not_time", "messenger_copy"),
      notes="Messenger names carry an id and no date")
    n("17912345678901234.jpg", "F36", "2023-12", folder="instagram/media/posts/202312/", event="transfer",
      band="low", bound="upper", quirks=("upper_bound_name",))
    n("Snapchat-1234567890.jpg", rules=("F37",), quirks=("counter_not_time",),
      notes="F55 also matches the ten digits; Snapchat's number is an id, so rule F37 vetoes it")


def cameras_and_devices():
    n = named
    n("DJI_20240225080944_0032_D.JPG", "F38", "2024-02-25T08:09:44", vendor="dji")
    n("DJI_20240225081020_0033_D.MP4", "F38", "2024-02-25T08:10:20", vendor="dji")
    n("DJI_0005.JPG", "F39", vendor="dji", quirks=("counter_not_time",))
    n("dji_fly_20240225_080944_0032_1708850908777_photo.jpg", "F40", "2024-02-25T08:09:44", vendor="dji",
      also=[captime.name_claim("F40", epoch("1708850908777")[0], "ms", "transfer", utc=True)])
    for stem in ("GOPR0001.JPG", "GP010001.JPG", "GX010002.MP4", "GS010003.JPG"):
        n(stem, "F41", vendor="gopro", quirks=("counter_not_time",))
    for stem in ("IMG_0001.JPG", "DSCN0001.JPG", "IMGP0001.JPG", "DSC_0001.NEF", "_DSC0001.NEF", "_MG_0001.CR2",
                 "DSC00001.ARW", "DSCF0001.RAF", "MVI_0001.MP4"):
        n(stem, "F43", quirks=("counter_not_time",), folder="names/dcf/")
    n("PC310001.JPG", "F44", vendor="olympus", rejected="no_year", value=None, quirks=("counter_not_time",))
    n("P1000001.JPG", "F44", vendor="panasonic", quirks=("counter_not_time",),
      notes="Panasonic counters look like Olympus month and day names: rule F44 matches with day 00")


def scans_and_sync():
    n = named
    for suffix in ("_a", "_b"):
        scan = "2023-06-18T14:20:05"
        block = tiffexif.exif_block(make="EPSON", model="FF-680W", digitized=tiffexif.exif_text(scan), size=(640, 480))
        data = images.jpeg(640, 480, [images.exif_segment(block)], seed=f"names/photo-name{suffix}.jpg")
        add(f"names/photo-name{suffix}.jpg", data, "jpeg", vendor="epson", quirks=["scan"],
            meta={"width": 640, "height": 480, "make": "EPSON", "model": "FF-680W"}, rules=["F45"],
            claims=[captime.claim("exif_createdate", scan, "s", "scan")])
    n("CamScanner 12-31-2023 12.34.jpg", rules=("F46",), quirks=("scan",), also=[
        captime.claim("filename:F46", "2023-12-31T12:34", "min", "scan")])
    n("2023-12-31 12.34.56.jpg", "F47", "2023-12-31T12:34:56")
    n("2023-12-31 12.34.57-1.jpg", "F47", "2023-12-31T12:34:57")
    jpg("names/20231231_123456000_iOS.jpg", 4032, 3024, "Apple", APPLE, "2023-12-31T13:34:56", "+01:00", vendor="apple",
        more=[captime.name_claim("F48", "2023-12-31T12:34:56.000", "ms", utc=True)],
        entry={"notes": "OneDrive names are reportedly UTC: the EXIF zone (+01:00) agrees"})
    n("Photo 22-04-06 15-21-03 2160.jpg", "F49", "2022-04-06T15:21:03", quirks=("two_digit_year",))
    n("22-04-07 15-21-04 2161.jpg", "F49", "2022-04-07T15:21:04", quirks=("two_digit_year",))
    n("Photo on 31-12-2023 at 12.34.jpg", "F51", "2023-12-31T12:34", quirks=())
    n("Photo on 12-31-23 at 12.34 PM.jpg", "F51", "2023-12-31T12:34", quirks=("two_digit_year",))
    n("Photo on 4-5-2019 at 9.15.jpg", "F51", rejected="ambiguous_order", quirks=("ambiguous_date_order",))


def generic():
    n = named
    n("2023-12-31_12-34-56.jpg", "F52", "2023-12-31T12:34:56")
    n("2016_01_30_11_49_15.mp4", "F52", "2016-01-30T11:49:15")
    n("2018-04-12 19:24:49.gif", "F52", "2018-04-12T19:24:49", stored="2018-04-12 19_24_49.gif")
    n("20231231T123456.jpg", "F52", "2023-12-31T12:34:56")
    n("Minecraft 2023-12-31 12-34-56.png", "F52", "2023-12-31T12:34:56", quirks=("screenshot",))
    n("201801261147521000.jpg", "F53", "2018-01-26T11:47:52", band="low")
    n("2019-07-23.jpg", "F54", "2019-07-23", band="low")
    n("IMG-2019-07-23.jpg", "F54", "2019-07-23", band="low")
    n("1703999999.jpg", "F55", "1703999999", **EPOCH)
    n("image_1703999999999.png", "F55", "1703999999999", **EPOCH)
    n("image_1999999999999.png", "F55", "1999999999999", rejected="out_of_range", kind="epoch",
      quirks=("epoch_name", "counter_not_time"))
    n("31.12.2023.jpg", "F56", "2023-12-31", rules=("F56",), band="low")
    n("12-31-2023.jpg", "F56", "2023-12-31", rules=("F56",), band="low")
    n("04.05.2019.jpg", "F56", rejected="ambiguous_order", quirks=("ambiguous_date_order",), rules=("F56",))


TAKEOUT = "takeout/Google Photos/"
LEGACY = ("takeout_legacy_sidecar",)
SUPPLEMENTAL = ("takeout_supplemental_sidecar",)


def takeout_json(title, taken, geo, serial):
    """A Google Takeout sidecar. taken is the UTC capture time, 'YYYY-MM-DDTHH:MM:SS'."""
    moment = datetime.fromisoformat(taken).replace(tzinfo=UTC)
    shown = (f"{moment:%b} {moment.day}, {moment.year}, {moment.hour % 12 or 12}:{moment:%M:%S} "
             f"{'AM' if moment.hour < 12 else 'PM'} UTC")
    stamp = {"timestamp": str(int(moment.timestamp())), "formatted": shown}
    record = {
        "title": title, "description": "", "imageViews": "0", "creationTime": stamp, "photoTakenTime": stamp,
        "geoData": {"latitude": geo[0], "longitude": geo[1], "altitude": geo[2], "latitudeSpan": 0.0,
                    "longitudeSpan": 0.0},
        "url": f"https://photos.google.com/photo/AF1QipSynthetic{serial:04d}",
    }
    return (json.dumps(record, indent=2) + "\n").encode()


def takeout(album, shown, taken, *, original=None, sidecar=None, local=None, rule=None, geo=(0.0, 0.0, 0.0),
            quirks=(), **options):
    """A Takeout media file and its JSON sidecar. taken is the UTC time the JSON holds. shown is the name on disk;
    original is the name before Takeout shortened it. When the name carries a local reading (rule, local) the JSON's
    UTC time fixes the zone."""
    serial = len(ENTRIES) + 1
    kept = list(quirks)
    if album.startswith("Photos from"):
        kept.append("takeout_year_folder")
    if album.startswith("Fotos von"):
        kept.append("takeout_localized_folder")
    files = []
    if sidecar:
        files = [(sidecar, takeout_json(original or shown, taken, geo, serial), "takeout_json")]
        if geo == (0.0, 0.0, 0.0):
            kept.append("takeout_geo_zero")
    else:
        kept.append("takeout_no_sidecar")
    text = taken + "Z"
    outcome = captime.resolve("takeout_photoTakenTime", utc=text, tz="device_default", band="medium")
    if local:
        outcome = captime.resolve(f"filename:{rule}", local=local, utc=text,
                                  offset=captime.offset_between(local, taken), tz="paired_utc_delta", band="medium")
    return named(original or shown, rule if local else None, local, folder=f"{TAKEOUT}{album}/",
                 stored=shown if original else None, before=[captime.claim("takeout_photoTakenTime", text, "s")],
                 outcome=outcome, quirks=kept, sidecars=files, rules=("F50",), **options)


def takeouts():
    t = takeout
    t("Photos from 2019", "IMG_20190509_154733.jpg", "2019-05-09T13:47:33", sidecar="IMG_20190509_154733.jpg.json",
      local="2019-05-09T15:47:33", rule="F01", quirks=LEGACY)
    t("Photos from 2019", "IMG_20190509_154733-edited.jpg", "2019-05-09T13:47:33", local="2019-05-09T15:47:33",
      rule="F01", quirks=("takeout_edited",))
    full = "IMG_20190510_101112_a_very_long_descriptive_title_that_gets_cut.jpg"
    cut = full[:46]
    t("Photos from 2019", cut + ".jpg", "2019-05-10T08:11:12", original=full, sidecar=cut + ".json",
      local="2019-05-10T10:11:12", rule="F01", quirks=("takeout_truncated_name", *LEGACY))
    t("Photos from 2019", "IMG_5001.jpg", "2019-06-01T09:00:00", sidecar="IMG_5001.jpg.json",
      quirks=("counter_not_time", *LEGACY))
    t("Photos from 2019", "IMG_5001(1).jpg", "2019-06-01T09:05:00", original="IMG_5001.jpg",
      sidecar="IMG_5001.jpg(1).json", quirks=("takeout_duplicate_counter", "counter_not_time", *LEGACY))
    t("Photos from 2020", "IMG_20200101_120000.jpg", "2020-01-01T11:00:00",
      sidecar="IMG_20200101_120000.jpg.supplemental-metadata.json", local="2020-01-01T12:00:00", rule="F01",
      quirks=SUPPLEMENTAL)
    t("Photos from 2020", "IMG_20200101_130000.jpg", "2020-01-01T12:00:00",
      sidecar="IMG_20200101_130000.jpg.supplemental-metad.json", local="2020-01-01T13:00:00", rule="F01",
      quirks=SUPPLEMENTAL)
    t("Trip to Rome", "IMG_20190509_160000.JPG", "2019-05-09T14:00:00", sidecar="IMG_20190509_160000.jpg.json",
      local="2019-05-09T16:00:00", rule="F01", quirks=("takeout_case_drift", *LEGACY))
    t("Trip to Rome", "VID_20190509_154800.mp4", "2019-05-09T13:48:00", sidecar="VID_20190509_154800.mp4.json",
      local="2019-05-09T15:48:00", rule="F01", quirks=LEGACY)
    t("Trip to Rome", "IMG_20190511_090000.jpg", "2019-05-11T07:00:00", sidecar="IMG_20190511_090000.jpg.json",
      local="2019-05-11T09:00:00", rule="F01", geo=(41.9028, 12.4964, 21.0), quirks=LEGACY,
      meta_extra={"gps": {"lat": 41.9028, "lon": 12.4964}})
    t("Fotos von 2019", "IMG_20190512_100000.jpg", "2019-05-12T08:00:00", sidecar="IMG_20190512_100000.jpg.json",
      local="2019-05-12T10:00:00", rule="F01", quirks=LEGACY)
    t("Fotos von 2019", "IMG_20190513_100000.jpg", "2019-05-13T08:00:00", local="2019-05-13T10:00:00", rule="F01")
    t("Trip to Rome", "holiday-photo", "2019-05-14T10:00:00", sidecar="holiday-photo.json",
      quirks=("takeout_extension_dropped", "no_extension", *LEGACY), data=(
          images.jpeg(640, 480, [], seed="takeout/Google Photos/Trip to Rome/holiday-photo"), "jpeg",
          {"width": 640, "height": 480}, ()))


def takeout_live():
    album, content_id = "Photos from 2022", "3E8A5D1C-7B24-49F0-A6C3-5D9E0F1B2A47"
    local, offset = "2022-09-03T10:15:20", "+02:00"
    taken = captime.convert(local, offset, True).rstrip("Z")
    cid = tiffexif.apple_maker_note(content_id)
    base = f"{TAKEOUT}{album}/IMG_6001"
    group = {"kind": "live_photo", "key": content_id}
    json_file = [("IMG_6001.HEIC.json", takeout_json("IMG_6001.HEIC", taken, (0.0, 0.0, 0.0), 90), "takeout_json")]
    heic(f"{base}.HEIC", local=local, offset=offset, maker_note=cid, gps=None,
         quirks=["live_photo", "takeout_year_folder", "takeout_geo_zero", *LEGACY],
         more=[captime.claim("takeout_photoTakenTime", taken + "Z", "s")],
         entry={"group": {**group, "role": "primary"}, "sidecars": json_file, "rules": ["F50"]})
    clip(f"{base}.MOV", "mov", vendor="apple", make="Apple", model=APPLE, codec="hevc", mode="keys", when=taken,
         offset=offset, brand=b"qt  ", compat=(b"qt  ",), w=1440, h=1080, ms=3000,
         keys=[("com.apple.quicktime.content.identifier", content_id)],
         quirks=["live_photo", "takeout_live_video", "takeout_no_sidecar", "takeout_year_folder"],
         entry={"group": {**group, "role": "live_motion"}, "rules": ["F50"]})


def register():
    android_and_oems()
    counters_and_apps()
    messengers()
    cameras_and_devices()
    scans_and_sync()
    generic()
    takeouts()
    takeout_live()
