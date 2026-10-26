"""Capture-time puzzles: sources that disagree, zones at the extremes, folder dates, DST overlaps, bad QuickTime clocks."""
import captime
import containers
import images
import tiffexif
from catalog_compound import exif_jpeg
from catalog_names import named, takeout_json
from catalog_stills import CANON, PARIS, jpg
from entries import add

PARIS_CITY = PARIS[:2]


def path_claim(kind, value, precision):
    return captime.claim(f"path:{kind}", value, precision)


def folder_dates():
    for folder, kind, value, precision in (("2019/05/09", "ymd", "2019-05-09", "day"),
                                           ("2019/05", "ym", "2019-05", "month"), ("2019", "y", "2019", "year")):
        outcome = captime.resolve(f"path:{kind}", local=value, tz="floating", precision=precision, band="low")
        add(f"time/folders/{folder}/photo.jpg", images.jpeg(640, 480, [], seed=f"time/folders/{folder}/photo.jpg"), "jpeg", quirks=["path_date"],
            meta={"width": 640, "height": 480}, claims=[path_claim(kind, value, precision)], resolved=outcome)
    jpg("time/folders/2020/02/29/leap-day.jpg", 640, 480, "NIKON CORPORATION", "NIKON D850", "2020-02-29T18:03:11",
        "+01:00", vendor="nikon", quirks=["path_date"], more=[path_claim("ymd", "2020-02-29", "day")])
    jpg("time/folders/2019/05/camera-roll.jpg", 640, 480, "Canon", CANON, "2018-08-20T09:30:15", "+02:00",
        vendor="canon", quirks=["path_date", "time_conflict"], more=[path_claim("ym", "2019-05", "month")])


def conflicts():
    xmp = images.xmp({"xmp": {"CreateDate": "2018-06-03T10:20:30+02:00"}})
    review = dict(band="medium", flags=("needs_review",))
    jpg("time/conflicts/exif-vs-xmp.jpg", 640, 480, "Canon", CANON, "2018-06-02T10:20:30", "+02:00", vendor="canon",
        xmp=xmp, quirks=["time_conflict"],
        more=[captime.claim("xmp_date_with_offset", "2018-06-03T10:20:30", "s", offset="+02:00")],
        outcome=captime.resolve("exif_dto_with_offset", local="2018-06-02T10:20:30", offset="+02:00", **review))
    jpg("time/conflicts/IMG_20190509_154733.jpg", 640, 480, "samsung", "SM-G991B", "2019-05-10T08:00:00", "+02:00",
        vendor="samsung", quirks=["time_conflict"], more=[captime.name_claim("F01", "2019-05-09T15:47:33")],
        outcome=captime.resolve("exif_dto_with_offset", local="2019-05-10T08:00:00", offset="+02:00", **review))
    jpg("time/conflicts/exif-vs-gps.jpg", 640, 480, "Canon", CANON, "2023-05-01T10:00:00", "+02:00", vendor="canon",
        gps=(*PARIS_CITY, 35.0, "2023-05-01T09:00:00"), quirks=["time_conflict"],
        outcome=captime.resolve("exif_dto_with_offset", local="2023-05-01T10:00:00", offset="+02:00", **review))
    jpg("time/conflicts/IMG-20191120-WA0010.jpg", 640, 480, "samsung", "SM-G991B", "2019-11-21T08:00:00",
        vendor="samsung", quirks=["time_conflict", "messenger_copy", "upper_bound_name"],
        more=[captime.name_claim("F25", "2019-11-20", "day", "receive")],
        outcome=captime.resolve("exif_dto_no_offset", local="2019-11-21T08:00:00", tz="floating", band="low",
                                flags=("capture_after_receive", "needs_review")))


def zones():
    for name, local, offset in (("nepal", "2023-04-14T20:00:00", "+05:45"), ("india", "2023-04-14T08:30:00", "+05:30"),
                                ("newfoundland", "2023-04-14T08:30:00", "-03:30"),
                                ("kiritimati", "2023-12-31T23:30:00", "+14:00"),
                                ("baker-island", "2024-01-01T00:15:00", "-12:00")):
        jpg(f"time/zones/{name}.jpg", 640, 480, "Canon", CANON, local, offset, vendor="canon")
    jpg("time/zones/year-end.jpg", 640, 480, "Canon", CANON, "2019-12-31T23:59:59", "+00:00", vendor="canon")
    jpg("time/zones/printed-1955.jpg", 640, 480, "EPSON", "Perfection V850", "1955-06-01T12:00:00", vendor="epson")


def dst_overlap():
    local = "2024-10-27T02:30:00"
    block = tiffexif.exif_block(make="Canon", model=CANON, size=(640, 480), original=tiffexif.exif_text(local),
                                gps=tiffexif.gps_ifd(*PARIS_CITY, 35.0))
    outcome = captime.resolve("exif_dto_no_offset", local=local, offset="+02:00", tz="gps_polygon", band="medium",
                              flags=("dst_ambiguous",))
    exif_jpeg("time/dst-overlap.jpg", block, ["dst_overlap"], meta={"make": "Canon", "model": CANON,
                                                                      "gps": {"lat": PARIS[0], "lon": PARIS[1]}},
              claims=[captime.claim("exif_dto_no_offset", local, "s")], resolved=outcome)


def quicktime_clocks():
    path = "time/VID_20220107_113306.mp4"
    when = "2036-02-07T06:28:16"
    data = containers.mp4(seed=path, created=containers.qt_clock(when))
    meta = {"width": 1920, "height": 1080, "duration_ms": 3000, "codec": "h264"}
    named("VID_20220107_113306.mp4", "F01", "2022-01-07T11:33:06", folder="time/", quirks=["mvhd_out_of_range"],
          before=[captime.claim("qt_mvhd_phone", when + "Z", "s", "record_start", rejected="out_of_range")],
          data=(data, "mp4", meta, ()))
    named("video-2011-09-25-18-58-53.mp4", "F52", "2011-09-25T18:58:53", folder="time/")


def takeout_with_exif():
    local, taken = "2024-07-29T04:45:00", "2024-07-28T19:45:00"
    name = "IMG_20240729_044500.jpg"
    offset = captime.offset_between(local, taken)
    outcome = captime.resolve("exif_dto_no_offset", local=local, utc=taken + "Z", offset=offset, tz="paired_utc_delta")
    sidecar = [(name + ".json", takeout_json(name, taken, (0.0, 0.0, 0.0), 500), "takeout_json")]
    jpg(f"takeout/Google Photos/Photos from 2024/{name}", 4000, 3000, "samsung", "SM-S911B", local, vendor="samsung",
        quirks=["takeout_year_folder", "takeout_legacy_sidecar", "takeout_geo_zero"],
        more=[captime.claim("takeout_photoTakenTime", taken + "Z", "s"), captime.name_claim("F01", local)],
        outcome=outcome, entry={"sidecars": sidecar, "rules": ["F50"]})


def register():
    folder_dates()
    conflicts()
    zones()
    dst_overlap()
    quicktime_clocks()
    takeout_with_exif()
