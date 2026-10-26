"""Files that only make sense together or only in a broken state: pairs, motion photos, spheres, camera sidecars,
EXIF damage and files whose extension lies."""
import base64

import captime
import containers
import images
import tiffexif
from catalog_stills import APPLE, CANON, PARIS, PIXEL, SMALL, heic, jpg, plain, raw
from catalog_video import clip
from entries import add
from recipes import shot

PLIST = b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>adjustmentBaseVersion</key>
  <integer>0</integer>
  <key>adjustmentEditorBundleID</key>
  <string>com.apple.mobileslideshow</string>
  <key>adjustmentFormatIdentifier</key>
  <string>com.apple.photo</string>
  <key>adjustmentTimestamp</key>
  <date>2022-09-01T08:15:00Z</date>
</dict>
</plist>
"""


def group(kind, key, role):
    return {"group": {"kind": kind, "key": key, "role": role}}


def utc_of(local, offset):
    return captime.convert(local, offset, True).rstrip("Z")


def live():
    for stem, ext, local, offset, content_id in (
            ("IMG_2001", "HEIC", "2022-08-14T17:42:10", "+02:00", "9D2F6B0E-3A41-4C58-8E7B-1F0A5C6D7E81"),
            ("IMG_2002", "JPG", "2023-01-02T09:05:44", "-05:00", "0B7A4C21-6E93-47D5-A1F8-2C3D4E5F6A70")):
        note = tiffexif.apple_maker_note(content_id)
        entry = group("live_photo", content_id, "primary")
        path = f"compound/live/{stem}.{ext}"
        if ext == "HEIC":
            heic(path, local=local, offset=offset, maker_note=note, quirks=["live_photo"], entry=entry)
        else:
            jpg(path, 4032, 3024, "Apple", APPLE, local, offset, vendor="apple", quirks=["live_photo"], entry=entry,
                gps=PARIS, maker_note=note, outcome=captime.home_time(local, offset, "+01:00"))
        clip(f"compound/live/{stem}.MOV", "mov", vendor="apple", make="Apple", model=APPLE, codec="hevc", mode="keys",
             when=utc_of(local, offset), offset=offset, brand=b"qt  ", compat=(b"qt  ",), w=1440, h=1080,
             keys=[("com.apple.quicktime.content.identifier", content_id)], quirks=["live_photo"], ms=3000,
             entry=group("live_photo", content_id, "live_motion"))


def edited():
    local, offset = "2022-08-30T19:20:21", "+01:00"
    key = "IMG_3001"
    paris = captime.home_time(local, offset, "+02:00")
    heic("compound/edited/IMG_3001.HEIC", local=local, offset=offset, quirks=["sidecar_aae"], outcome=paris,
         entry={**group("edited_variant", key, "primary"), "sidecars": [("IMG_O3001.AAE", PLIST, "aae")]})
    jpg("compound/edited/IMG_E3001.JPG", 4032, 3024, "Apple", APPLE, local, offset, vendor="apple", gps=PARIS,
        quirks=["edited_render"], entry=group("edited_variant", key, "edited_render"), outcome=paris)


def motion_video(seed):
    return containers.mp4(seed=seed, codec="h264", width=1280, height=960, duration_ms=1500)


def motion():
    pixel_xmp = {"GCamera": {"MotionPhoto": 1, "MotionPhotoVersion": 1, "MotionPhotoPresentationTimestampUs": 700000},
                 "Container": {}, "Item": {}}
    path = "compound/motion/PXL_20230330_184138390.MP.jpg"
    video = motion_video(path)
    directory = images.container_directory([("image/jpeg", "Primary", 0), ("video/mp4", "MotionPhoto", len(video))])
    jpg(path, 4080, 3072, "Google", PIXEL, "2023-03-30T14:41:38", "-04:00", vendor="google", subsec="390", video=video,
        xmp=images.xmp(pixel_xmp, directory), quirks=["motion_photo_v1", "pixel_utc_name"],
        more=[captime.name_claim("F03", "2023-03-30T18:41:38.390", "ms", utc=True)])
    path = "compound/motion/MVIMG_20190215_193501.jpg"
    video = motion_video(path)
    legacy = {"GCamera": {"MicroVideo": 1, "MicroVideoVersion": 1, "MicroVideoOffset": len(video),
                          "MicroVideoPresentationTimestampUs": 700000}}
    jpg(path, 4032, 3024, "Google", "Pixel 3", "2019-02-15T19:35:01", vendor="google", video=video,
        xmp=images.xmp(legacy), quirks=["micro_video"], more=[captime.name_claim("F02", "2019-02-15T19:35:01")])
    path = "compound/motion/samsung-motion.jpg"
    jpg(path, 4000, 3000, "samsung", "SM-S911B", "2023-04-08T11:12:13", "+09:00", vendor="samsung",
        video=motion_video(path), sef="MotionPhoto_Data", quirks=["motion_photo_sef", "trailing_data"])
    heic("compound/motion/pixel-motion.heic", vendor="google", model="Pixel 8 Pro", local="2023-11-12T16:20:30",
         offset="-08:00", gps=None, quirks=["motion_photo_mpvd"], motion=motion_video("pixel-motion.heic"))
    stale = {"GCamera": {"MotionPhoto": 1, "MotionPhotoVersion": 1}, "Container": {}, "Item": {}}
    directory = images.container_directory([("image/jpeg", "Primary", 0), ("video/mp4", "MotionPhoto", 912345)])
    entry = group("live_photo", None, "primary")
    jpg("compound/motion/PXL_20230514_100000000.jpg", 4080, 3072, "Google", PIXEL, "2023-05-14T12:00:00", "+02:00",
        vendor="google", subsec="000", xmp=images.xmp(stale, directory), quirks=["motion_flag_stale", "live_photo"],
        entry=entry, more=[captime.name_claim("F03", "2023-05-14T10:00:00.000", "ms", utc=True)])
    clip("compound/motion/PXL_20230514_100000000.MP.mp4", vendor="google", make="Google", model=PIXEL, mode="phone",
         when="2023-05-14T10:00:00", w=1280, h=960, quirks=["live_photo"],
         entry=group("live_photo", None, "live_motion"))


def raw_pairs():
    pair = group("raw_jpeg", None, "primary")["group"]

    def both(stem, jpeg_ext, raw_ext, fmt, vendor, make, model, local, offset=None, extra=None, **options):
        key = {**pair, "key": stem}
        extra = extra or {}
        sidecar = [(f"{stem}.xmp", images.xmp({"xmp": {"Rating": "4"}}) + b"\n", "xmp")] if fmt == "cr2" else []
        quirks = ["raw_jpeg_pair"] + (["sidecar_xmp"] if sidecar else [])
        jpg(f"compound/raw-jpeg/{stem}.{jpeg_ext}", 6000, 4000, make, model, local, offset, vendor=vendor,
            quirks=quirks, entry={"group": key}, **extra)
        raw(f"compound/raw-jpeg/{stem}.{raw_ext}", fmt, vendor, make, model, local, offset, quirks=quirks,
            entry={"group": {**key, "role": "raw_alt"}, "sidecars": sidecar}, more=extra.get("more", ()), **options)

    both("_MG_0123", "JPG", "CR2", "cr2", "canon", "Canon", CANON, "2018-06-02T10:20:30")
    both("DSC_0456", "JPG", "NEF", "nef", "nikon", "NIKON CORPORATION", "NIKON D850", "2019-10-03T06:30:00")
    both("DSC00789", "JPG", "ARW", "arw", "sony", "SONY", "ILCE-7RM4", "2021-03-14T14:15:16", "+01:00")
    both("IMGP0034", "JPG", "PEF", "pef", "pentax", "PENTAX Corporation", "PENTAX K-1", "2015-12-24T17:00:01")
    claim = captime.claim("filename:F44", None, None, rejected="no_year")
    both("P4120056", "JPG", "ORF", "orf", "olympus", "OLYMPUS CORPORATION", "E-M5", "2016-04-12T08:08:08",
         extra={"more": [claim]})
    both("DJI_20231028130032_0001_D", "JPG", "DNG", "dng", "dji", "DJI", "FC3582", "2023-10-28T13:00:32",
         extra={"more": [captime.name_claim("F38", "2023-10-28T13:00:32")]})
    stem = "PXL_20230330_184138390"
    name_claim = captime.name_claim("F03", "2023-03-30T18:41:38.390", "ms", utc=True)
    key = {**pair, "key": stem}
    jpg(f"compound/raw-jpeg/{stem}.RAW-01.MP.COVER.jpg", 4080, 3072, "Google", PIXEL, "2023-03-30T14:41:38", "-04:00",
        vendor="google", subsec="390", quirks=["raw_jpeg_pair", "pixel_utc_name"], more=[name_claim],
        entry={"group": key})
    raw(f"compound/raw-jpeg/{stem}.RAW-02.ORIGINAL.dng", "dng", "google", "Google", PIXEL, "2023-03-30T14:41:38",
        "-04:00", quirks=["raw_jpeg_pair", "pixel_utc_name"], subsec="390", more=[name_claim],
        entry={"group": {**key, "role": "raw_alt"}})
    block, meta, claims, resolved = shot("FUJIFILM", "X-T4", "2022-05-01T10:11:12", size=(160, 120))
    embedded = images.jpeg(160, 120, [images.exif_segment(block)], seed="compound/raw-jpeg/DSCF0012.RAF")
    jpg("compound/raw-jpeg/DSCF0012.JPG", 6240, 4160, "FUJIFILM", "X-T4", "2022-05-01T10:11:12", vendor="fujifilm",
        quirks=["raw_jpeg_pair"], entry={"group": {**pair, "key": "DSCF0012"}})
    add("compound/raw-jpeg/DSCF0012.RAF", containers.raf(seed="DSCF0012", model="X-T4", jpeg_bytes=embedded), "raf",
        vendor="fujifilm", quirks=["raw_jpeg_pair", "embedded_preview"], meta=meta, claims=claims, resolved=resolved,
        group={**pair, "key": "DSCF0012", "role": "raw_alt"})


def gpano(full, cropped=None, heading=None):
    width, height = full
    area = cropped or full
    return images.xmp({"GPano": {
        "ProjectionType": "equirectangular", "UsePanoramaViewer": "True", "FullPanoWidthPixels": width,
        "FullPanoHeightPixels": height, "CroppedAreaImageWidthPixels": area[0], "CroppedAreaImageHeightPixels": area[1],
        "CroppedAreaLeftPixels": 0, "CroppedAreaTopPixels": (height - area[1]) // 2,
        **({"PoseHeadingDegrees": heading} if heading is not None else {})}})


def panoramas():
    sphere = {"projection": "equirectangular", "cropped": False}
    jpg("compound/pano/photosphere.jpg", 8192, 4096, "Google", PIXEL, "2022-06-18T18:30:00", "+02:00", vendor="google",
        xmp=gpano((8192, 4096)), meta_extra={"pano": sphere}, quirks=["photo_sphere"])
    jpg("compound/pano/photosphere-cropped.jpg", 8192, 2048, "Google", PIXEL, "2022-06-18T18:40:00", "+02:00",
        vendor="google", xmp=gpano((8192, 4096), (8192, 2048), heading=123.5), quirks=["photo_sphere_cropped"],
        meta_extra={"pano": {**sphere, "cropped": True, "heading": 123.5}})
    jpg("compound/pano/PANO_20190101_120000.jpg", 12000, 2000, "motorola", "moto g(7)", "2019-01-01T12:00:00",
        vendor="motorola", quirks=["flat_panorama"], more=[captime.name_claim("F02", "2019-01-01T12:00:00")])
    jpg("compound/pano/IMG_20201031_094049_00_189.insp", 6080, 3040, "Insta360", "Insta360 ONE X2",
        "2020-10-31T09:40:49",
        vendor="insta360", fmt="insp", xmp=gpano((6080, 3040)), meta_extra={"pano": sphere},
        quirks=["photo_sphere"], more=[captime.name_claim("F42", "2020-10-31T09:40:49")])
    jpg("compound/pano/IMG_20180318_205851_239.insp", 3008, 1504, "Insta360", "Insta360 Air", "2018-03-18T20:58:51",
        vendor="insta360", fmt="insp", xmp=gpano((3008, 1504)), meta_extra={"pano": sphere}, quirks=["photo_sphere"],
        more=[captime.name_claim("F01", "2018-03-18T20:58:51")],
        entry={"notes": "The research registry lists this name for F42 but its own pattern needs the lens field"})
    maker = dict(make="RICOH", model="THETA V", mode="camera", w=3840, h=1920, meta_extra={"pano": sphere})
    clip("compound/sphere/spherical-v1.mp4", when="2019-08-10T14:00:00", spherical_v1=True,
         quirks=["spherical_video_v1"], **maker)
    clip("compound/sphere/spherical-v2.mp4", when="2019-08-10T14:05:00", sphere="equi", quirks=["spherical_video_v2"],
         **maker)
    # A VR180-like half sphere: a quarter of the full 3840 × 1920 panorama cut off left and right.
    clip("compound/sphere/spherical-v2-cropped.mp4", when="2019-08-10T14:07:00", sphere="equi",
         bounds=(0, 0, 0x40000000, 0x40000000), quirks=["spherical_video_v2", "spherical_video_v2_bounds"],
         **{**maker, "w": 1920, "meta_extra": {"pano": {**sphere, "cropped": True}}})
    clip("compound/sphere/cubemap.mp4", when="2019-08-10T14:10:00", sphere="cube", quirks=["cubemap"],
         **{**maker, "meta_extra": {"pano": {**sphere, "projection": "cubemap"}}})
    clip("compound/sphere/stereo-top-bottom.mp4", when="2021-02-14T10:00:00", stereo=1, make="Canon", model="EOS R5",
         mode="camera", vendor="canon", quirks=["stereo_top_bottom"])
    clip("compound/sphere/stereo-left-right.mp4", when="2021-02-14T10:05:00", stereo=2, make="Canon", model="EOS R5",
         mode="camera", vendor="canon", quirks=["stereo_left_right"])
    heic("compound/pano/spatial.heic", model="iPhone 15 Pro", local="2024-03-09T15:00:00", offset="-05:00", w=3840,
         h=2160, stereo=True, quirks=["spatial_photo"],
         outcome=captime.home_time("2024-03-09T15:00:00", "-05:00", "+01:00"))


def depth():
    heic("compound/depth/portrait.heic", quirks=["depth_apple", "heif_aux_image"],
         aux=[("urn:mpeg:hevc:2015:auxid:2", 576, 432)], local="2022-04-02T11:30:00", offset="+02:00")
    note = base64.b64encode(images.filler("gdepth", 24)).decode()
    gdepth = images.xmp({"GDepth": {"Format": "RangeInverse", "Near": "0.3", "Far": "10.0", "Mime": "image/png",
                                    "Data": note}})
    jpg("compound/depth/gdepth.jpg", 4032, 3024, "Google", "Pixel 4", "2020-01-15T08:10:00", "-08:00", vendor="google",
        xmp=gdepth, quirks=["depth_gdepth"])
    depth_map = images.jpeg(504, 378, [], seed="compound/depth/dynamic.jpg depth map")
    directory = images.container_directory([("image/jpeg", "Primary", 0), ("image/jpeg", "Depth", len(depth_map))])
    jpg("compound/depth/dynamic.jpg", 4080, 3072, "Google", "Pixel 6 Pro", "2021-11-20T17:00:00", "-05:00",
        vendor="google", xmp=images.xmp({"Device": {"Revision": "1.0"}, "Container": {}, "Item": {}}, directory),
        jpeg={"tail": depth_map}, quirks=["depth_dynamic", "trailing_data"])
    trailer = containers.sef_trailer([("DepthMap_Data", images.filler("samsung-depth", 40))])
    jpg("compound/depth/samsung-live-focus.jpg", 4000, 3000, "samsung", "SM-N975F", "2020-02-02T12:00:00", "+01:00",
        vendor="samsung", jpeg={"tail": trailer}, quirks=["depth_samsung", "trailing_data"])


def camera_aux():
    gopro = {"vendor": "gopro", "make": "GoPro", "model": "HERO11 Black", "mode": "camera", "codec": "hevc",
             "when": "2023-07-09T10:20:30", "brand": b"mp41", "compat": (b"mp41",)}
    stack = group("camera_aux", "GH010001", "primary")
    clip("compound/gopro/GH010001.MP4", w=5312, h=2988, entry=stack, **gopro)
    clip("compound/gopro/GL010001.LRV", "lrv", w=640, h=360, quirks=["camera_proxy"],
         entry=group("camera_aux", "GH010001", "camera_aux"), **gopro)
    thumbnail = images.jpeg(160, 120, [], seed="compound/gopro/GH010001.THM")
    add("compound/gopro/GH010001.THM", thumbnail, "thm", vendor="gopro", meta={"width": 160, "height": 120},
        **group("camera_aux", "GH010001", "camera_aux"))
    insta = {"vendor": "insta360", "make": "Insta360", "model": "Insta360 ONE X2", "mode": "camera", "codec": "h264",
             "when": "2020-10-31T09:40:49", "brand": b"mp42", "compat": (b"mp42", b"isom")}
    more = [captime.name_claim("F42", "2020-10-31T09:40:49")]
    key = "20201031_094049_188"
    clip("compound/insta360/VID_20201031_094049_00_188.insv", "insv", w=2880, h=2880, quirks=["lens_pair"], more=more,
         entry=group("lens_pair", key, "lens"), **insta)
    clip("compound/insta360/VID_20201031_094049_10_188.insv", "insv", w=2880, h=2880, quirks=["lens_pair"], more=more,
         entry=group("lens_pair", key, "lens"), **insta)
    clip("compound/insta360/LRV_20201031_094049_01_188.lrv", "lrv", w=960, h=480, quirks=["camera_proxy"], more=more,
         entry=group("camera_aux", key, "camera_aux"), **insta)
    dji = {"vendor": "dji", "make": "DJI", "model": "Mavic 3", "mode": "camera", "codec": "hevc",
           "when": "2023-09-02T16:45:10"}
    clip("compound/dji/DJI_0007.MP4", w=3840, h=2160, entry=group("camera_aux", "DJI_0007", "primary"), **dji)
    clip("compound/dji/DJI_0007.LRF", "lrf", w=1280, h=720, quirks=["camera_proxy"],
         entry=group("camera_aux", "DJI_0007", "camera_aux"), **dji)


def orientations():
    for number in range(2, 9):
        jpg(f"compound/orientation/orientation-{number}.jpg", 640, 480, "Canon", CANON, f"2019-05-0{number}T15:47:33",
            vendor="canon", orientation=number, quirks=["exif_orientation"])


def exif_jpeg(path, block, quirks, *, size=(640, 480), meta=None, claims=(), resolved=None, **entry):
    segments = [images.exif_segment(block)] if block is not None else []
    data = images.jpeg(*size, segments, seed=path)
    return add(path, data, "jpeg", quirks=quirks, meta={"width": size[0], "height": size[1], **(meta or {})},
               claims=claims, resolved=resolved, **entry)


def broken_exif():
    camera = {"make": "Canon", "model": CANON}
    full = dict(**camera, size=(640, 480))
    exif_jpeg("compound/exif/no-metadata.jpg", None, ["exif_missing"])
    exif_jpeg("compound/exif/stripped.jpg", tiffexif.exif_block(orientation=6, size=(640, 480)), ["exif_stripped"],
              meta={"orientation": 6})
    good = tiffexif.exif_block(original=tiffexif.exif_text("2019-05-09T15:47:33"), **full)
    exif_jpeg("compound/exif/truncated.jpg", good[:20], ["exif_truncated"])
    name_only = captime.from_name("F01", "2019-05-09T15:47:33")
    exif_jpeg("compound/exif/bad-offset/IMG_20190509_154733.jpg",
              tiffexif.exif_block(original=tiffexif.exif_text("2019-05-09T15:47:33"), bad_exif_pointer=True, **full),
              ["exif_bad_offset"], meta=camera, claims=name_only[0], resolved=name_only[1])
    dated = captime.from_name("F47", "2019-05-09T15:47:33")
    exif_jpeg("compound/exif/sentinel-date/2019-05-09 15.47.33.jpg",
              tiffexif.exif_block(original="0000:00:00 00:00:00", **full), ["exif_sentinel_date"], meta=camera,
              claims=[captime.claim("exif_dto_no_offset", "0000-00-00T00:00:00", "s", rejected="sentinel"), *dated[0]],
              resolved=dated[1])
    boxed = captime.from_name("F01", "2020-12-25T08:09:10")
    exif_jpeg("compound/exif/invalid-date/IMG_20201225_080910.jpg",
              tiffexif.exif_block(original="2019:13:45 25:61:61", **full), ["exif_invalid_date"], meta=camera,
              claims=[captime.claim("exif_dto_no_offset", "2019-13-45T25:61:61", "s", rejected="invalid"), *boxed[0]],
              resolved=boxed[1])
    stamp = "2020-02-29T18:03:11"
    plain_claim = captime.claim("exif_dto_no_offset", stamp, "s")
    exif_jpeg("compound/exif/nonsense-offset.jpg",
              tiffexif.exif_block(original=tiffexif.exif_text(stamp), offsets=(None, "+99:99", None), **full),
              ["exif_nonsense_offset"], meta=camera,
              claims=[captime.claim("exif_dto_with_offset", stamp, "s", offset="+99:99", rejected="out_of_range"),
                      plain_claim],
              resolved=captime.resolve("exif_dto_no_offset", local=stamp, tz="floating", band="medium"))
    pixel = captime.from_name("F03", "2023-10-26T21:06:42.603", precision="ms", utc=True, tz="device_default")
    exif_jpeg("compound/exif/future-date/PXL_20231026_210642603.jpg",
              tiffexif.exif_block(original=tiffexif.exif_text("2099-01-01T00:00:00"), **full),
              ["exif_future_date", "pixel_utc_name"], meta=camera,
              claims=[captime.claim("exif_dto_no_offset", "2099-01-01T00:00:00", "s", rejected="out_of_range"),
                      *pixel[0]],
              resolved=pixel[1])
    exif_jpeg("compound/exif/garbage-text.jpg", tiffexif.exif_block(original="garbage", **full),
              ["exif_garbage_text"], meta=camera,
              claims=[captime.claim("exif_dto_no_offset", None, None, rejected="invalid")])
    exif_jpeg("compound/exif/null-island.jpg",
              tiffexif.exif_block(original=tiffexif.exif_text(stamp), gps=tiffexif.gps_ifd(0.0, 0.0), **full),
              ["gps_null_island"], meta=camera, claims=[plain_claim],
              resolved=captime.resolve("exif_dto_no_offset", local=stamp, tz="floating", band="medium"))


def odd_files():
    heic("compound/odd/heic-saved-as.jpg", quirks=["extension_mismatch"], local="2022-02-02T14:00:00", offset="+01:00")
    clip("compound/odd/mp4-saved-as.mov", "mp4", vendor="google", make="Google", model=PIXEL, mode="phone",
         when="2023-02-02T14:00:00", quirks=["extension_mismatch"])
    plain("compound/odd/webp-saved-as.png", images.webp(*SMALL, seed="compound/odd/webp-saved-as.png"), "webp", *SMALL,
          ["extension_mismatch"])
    plain("compound/odd/holiday-snap", images.jpeg(320, 240, [], seed="compound/odd/holiday-snap"), "jpeg", 320, 240,
          ["no_extension"])
    add("compound/odd/mystery.dat", containers.unknown(seed="mystery"), "unknown", quirks=["unknown_type"])
    plain("compound/odd/trailing-data.jpg",
          images.jpeg(320, 240, [], seed="compound/odd/trailing-data.jpg",
                      tail=b"PHOTOLIB-TRAILER\0" + images.filler("trail", 32)),
          "jpeg", 320, 240, ["trailing_data"])
    jpg("compound/odd/truncated.jpg", 640, 480, "Canon", CANON, "2019-05-09T15:47:33", vendor="canon",
        quirks=["truncated_file"], jpeg={"truncate": -20})


def register():
    live()
    edited()
    motion()
    raw_pairs()
    panoramas()
    depth()
    camera_aux()
    orientations()
    broken_exif()
    odd_files()
