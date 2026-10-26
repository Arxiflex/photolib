"""Video: containers, codecs, HDR flavours and the ways phones and cameras stamp creation time."""
import struct

import captime
import containers
import images
from entries import add

PARIS = (48.8584, 2.2945)
CANON_VIDEO = "Canon EOS R5"
SPIN = {0: None, 90: 6, 180: 3, 270: 8}


def iso6709(lat, lon):
    return f"{lat:+08.4f}{lon:+09.4f}/"


def clip(path, fmt="mp4", *, vendor=None, make=None, model=None, mode=None, when=None, offset=None, gps=None,
         quirks=(), codec="h264", w=1920, h=1080, ms=3000, rotation=0, brand=b"isom", compat=(b"isom", b"mp42"),
         keys=(), entry=None, more=(), outcome=None, meta_extra=None, **options):
    """mode 'phone': mvhd holds UTC, 'keys': Apple creationdate key plus UTC mvhd, 'camera': mvhd holds the wall
    clock, None: mvhd is zero. when is the stored mvhd text; offset is the zone the author expects. entry holds
    further add() arguments (group, name, notes, rules); more are claims to append; meta_extra is merged into the
    metadata."""
    claims, resolved, created, keys = [], None, None, list(keys)
    xyz = iso6709(*gps) if gps and mode == "phone" else None
    if gps and mode == "keys":
        keys.append(("com.apple.quicktime.location.ISO6709", iso6709(*gps)[:-1] + "+035.000/"))
    if mode in ("phone", "keys"):
        created = containers.qt_clock(when)
        claims.append(captime.claim("qt_mvhd_phone", when + "Z", "s", "record_start"))
        if mode == "keys":
            local = captime.convert(when + "Z", offset, False)
            stamp = local + offset.replace(":", "")
            keys.append(("com.apple.quicktime.creationdate", stamp))
            claims.insert(0, captime.claim("qt_keys_creationdate", local, "s", "record_start", offset=offset))
            resolved = captime.resolve("qt_keys_creationdate", local=local, offset=offset)
        elif gps:
            resolved = captime.resolve("qt_mvhd_phone", utc=when + "Z", offset=offset, tz="gps_polygon", band="medium")
        else:
            resolved = captime.resolve("qt_mvhd_phone", utc=when + "Z", tz="device_default", band="medium")
    elif mode == "camera":
        created = containers.qt_clock(when)
        claims.append(captime.claim("qt_mvhd_camera", when, "s", "record_start"))
        resolved = captime.resolve("qt_mvhd_camera", local=when, tz="floating", band="medium")
    quirks = list(quirks) + (["video_rotation"] if rotation else [])
    meta = {"width": w, "height": h, "duration_ms": ms, "codec": codec}
    if SPIN[rotation]:
        meta["orientation"] = SPIN[rotation]
    if make:
        meta["make"] = make
    if model:
        meta["model"] = model
    if gps:
        meta["gps"] = {"lat": gps[0], "lon": gps[1]}
    meta.update(meta_extra or {})
    data = containers.mp4(seed=path, brand=brand, compat=compat, codec=codec, width=w, height=h, duration_ms=ms,
                          created=created, rotation=rotation, keys=keys, xyz=xyz, **options)
    return add(path, data, fmt, vendor=vendor, quirks=quirks, meta=meta, claims=claims + list(more),
               resolved=outcome or resolved, **(entry or {}))


def other(path, data, fmt, codec, w, h, ms, quirks=(), **options):
    meta = {"width": w, "height": h, "duration_ms": ms, "codec": codec}
    return add(path, data, fmt, quirks=quirks, meta=meta, **options)


def phones():
    qt = {"brand": b"qt  ", "compat": (b"qt  ",), "fmt": "mov"}
    apple = dict(vendor="apple", make="Apple", model="iPhone 13 Pro", codec="hevc", mode="keys", **qt)
    clip("video/iphone.mov", when="2021-07-14T10:15:42", offset="+02:00", gps=PARIS, **apple)
    clip("video/iphone-portrait.mov", when="2021-12-24T18:30:00", offset="+01:00", rotation=90, w=1080, h=1920, **apple)
    clip("video/iphone-hlg.mov", when="2022-03-05T09:00:00", offset="-08:00", quirks=["hdr_hlg", "bit_depth_10"],
         hdr="hlg", **apple)
    clip("video/iphone-dolby-vision.mov", when="2022-03-05T09:05:00", offset="-08:00", quirks=["dolby_vision"],
         hdr="dv", **apple)
    block = containers.box(b"vexu", containers.box(b"eyes", containers.full(b"stri", bytes([3]))))
    clip("video/vision-pro-spatial.mov", when="2024-02-10T15:00:00", offset="-05:00", quirks=["spatial_video"],
         extra_entry=block + containers.box(b"hfov", struct.pack(">I", 63400)), **apple)
    google = dict(vendor="google", make="Google", model="Pixel 7", mode="phone")
    clip("video/pixel.mp4", when="2023-10-26T21:06:42", offset="-07:00", gps=(37.7749, -122.4194), **google)
    clip("video/pixel-av1.mp4", codec="av1", when="2023-10-27T08:00:00", **google)
    samsung = dict(vendor="samsung", make="samsung", model="SM-G991B", mode="phone", codec="hevc")
    clip("video/samsung.mp4", when="2022-07-01T12:00:00", **samsung)
    clip("video/samsung-hdr10.mp4", when="2022-07-01T12:30:00", quirks=["hdr_pq", "hdr10", "bit_depth_10"], hdr="pq",
         **samsung)
    clip("video/samsung-hdr10plus.mp4", when="2022-07-01T12:40:00", hdr="pq", marker=b"\x00\x00\x01\x4e\x01\x04\x08\xb5\x00\x3c\x00\x01\x04",
         quirks=["hdr_pq", "hdr10", "hdr10_plus", "bit_depth_10"], **samsung)
    sef = containers.sef_trailer([("Slow_Motion_Data", images.filler("slow", 24))])
    clip("video/samsung-slow-motion.mp4", when="2022-07-02T10:00:00", quirks=["slow_motion_sef", "trailing_data"],
         trailer=sef, **samsung)
    clip("video/pixel-slow-motion.mp4", when="2023-10-28T10:00:00", quirks=["slow_motion"], ms=8000,
         keys=[("com.android.capture.fps", "240.0")], **google)
    clip("video/truncated.mp4", when="2023-10-29T10:00:00", quirks=["truncated_file"], truncate=-100, **google)
    clip("video/legacy.3gp", fmt="3gp", codec="h263", w=176, h=144, ms=5000, brand=b"3gp4", compat=(b"3gp4", b"isom"),
         mode="phone", when="2009-06-21T14:00:00")


def cameras():
    sony = dict(vendor="sony", make="SONY", model="ILCE-7M3", mode="camera", codec="hevc")
    clip("video/sony.mp4", when="2022-09-18T16:45:09", **sony)
    clip("video/canon.mov", fmt="mov", vendor="canon", make="Canon", model=CANON_VIDEO, mode="camera",
         when="2019-05-09T15:47:33", brand=b"qt  ", compat=(b"qt  ",))
    clip("video/prores.mov", fmt="mov", codec="prores", mode="camera", when="2020-06-15T10:00:00", brand=b"qt  ",
         compat=(b"qt  ",))
    clip("video/no-creation-time.mp4", quirks=["mvhd_zero"])
    clip("video/mjpeg.mov", fmt="mov", vendor="panasonic", make="Panasonic", model="DMC-TZ5", mode="camera",
         when="2008-07-19T14:30:00", codec="mjpeg", w=640, h=480, ms=1000, brand=b"qt  ", compat=(b"qt  ",))



def containers_and_codecs():
    other("video/matroska.mkv", containers.mkv(seed="mkv"), "mkv", "h264", 1280, 720, 5000)
    other("video/vp9.webm", containers.mkv(seed="vp9", doctype="webm", codec_id="V_VP9"), "webm", "vp9", 1280, 720, 5000)
    other("video/vp8.webm", containers.mkv(seed="vp8", doctype="webm", codec_id="V_VP8"), "webm", "vp8", 640, 360, 5000)
    other("video/avchd.mts", containers.mpegts(seed="mts"), "mts", "h264", 1920, 1080, 4000)
    other("video/bluray.m2ts", containers.mpegts(seed="m2ts", m2ts=True), "m2ts", "h264", 1920, 1080, 4000)
    other("video/mjpeg.avi", containers.avi(seed="video/mjpeg.avi"), "avi", "mjpeg", 640, 480, 1000)
    other("video/xvid.avi", containers.avi(seed="xvid", compression=b"XVID"), "avi", "xvid", 640, 480, 1000)
    other("video/dv.avi", containers.avi(seed="dv", width=720, height=576, compression=b"dvsd"), "avi", "dv", 720, 576,
          1000)
    other("video/legacy.wmv", containers.asf(seed="wmv"), "wmv", "wmv", 640, 480, 3000)
    other("video/dvd.mpg", containers.mpeg_ps(seed="mpg"), "mpeg", "mpeg2", 720, 576, 2000)
    other("video/flash.flv", containers.flv(seed="flv"), "flv", "flv1", 320, 240, 3000)
    add("video/voice.ogg", containers.ogg(seed="ogg"), "unknown", container="ogg", mime="audio/ogg", kind="audio")


def register():
    phones()
    cameras()
    containers_and_codecs()
