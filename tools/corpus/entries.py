"""The corpus registry. Catalog modules call add() once per file; build.py turns the result into files and goldens."""
import filename_rules

FORMATS = {
    "jpeg": ("jpeg", "image/jpeg", "image"), "png": ("png", "image/png", "image"),
    "apng": ("png", "image/apng", "image"), "bmp": ("bmp", "image/bmp", "image"),
    "webp": ("webp", "image/webp", "image"), "gif": ("gif", "image/gif", "image"),
    "heic": ("isobmff", "image/heic", "image"), "avif": ("isobmff", "image/avif", "image"),
    "jxl": ("jxl", "image/jxl", "image"), "tiff": ("tiff", "image/tiff", "image"),
    "psd": ("psd", "image/vnd.adobe.photoshop", "image"), "psb": ("psd", "image/vnd.adobe.photoshop", "image"),
    "cr2": ("tiff", "image/x-canon-cr2", "image"), "cr3": ("isobmff", "image/x-canon-cr3", "image"),
    "nef": ("tiff", "image/x-nikon-nef", "image"), "arw": ("tiff", "image/x-sony-arw", "image"),
    "raf": ("raf", "image/x-fuji-raf", "image"), "orf": ("tiff", "image/x-olympus-orf", "image"),
    "rw2": ("tiff", "image/x-panasonic-rw2", "image"), "pef": ("tiff", "image/x-pentax-pef", "image"),
    "dng": ("tiff", "image/x-adobe-dng", "image"), "svg": ("svg", "image/svg+xml", "image"),
    "pdf": ("pdf", "application/pdf", "document"), "eps": ("eps", "application/postscript", "document"),
    "mp4": ("isobmff", "video/mp4", "video"), "mov": ("isobmff", "video/quicktime", "video"),
    "mkv": ("ebml", "video/x-matroska", "video"), "webm": ("ebml", "video/webm", "video"),
    "mts": ("mpegts", "video/mp2t", "video"), "m2ts": ("m2ts", "video/mp2t", "video"),
    "avi": ("avi", "video/x-msvideo", "video"), "3gp": ("isobmff", "video/3gpp", "video"),
    "wmv": ("asf", "video/x-ms-wmv", "video"), "mpeg": ("mpegps", "video/mpeg", "video"),
    "flv": ("flv", "video/x-flv", "video"), "insp": ("jpeg", "image/jpeg", "image"),
    "insv": ("isobmff", "video/mp4", "video"), "lrv": ("isobmff", "video/mp4", "video"),
    "lrf": ("isobmff", "video/mp4", "video"), "thm": ("jpeg", "image/jpeg", "image"),
    "unknown": ("unknown", "application/octet-stream", "unknown"),
}
UNSUPPORTED_CONTAINERS = {"svg", "pdf", "eps", "unknown", "ogg"}
NO_ENCODER = {"heic": "HEVC", "avif": "AV1", "jxl": "JPEG XL"}  # no reasonable stdlib encoder: placeholder pixels
RAW = {"cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "dng"}
ENTRIES = {}


def add(path, data, fmt, *, vendor=None, quirks=(), meta=None, claims=(), resolved=None, name=None, group=None,
        sidecars=(), notes=None, rules=(), container=None, mime=None, kind=None):
    """Register one file. name is the original file name when the source mangled it; rules are the filename rules
    the author expects to match: each must match, and the ones without a regex of their own are simply listed."""
    if path in ENTRIES:
        raise ValueError(f"duplicate corpus path {path}")
    default = FORMATS[fmt]
    container, mime, kind = container or default[0], mime or default[1], kind or default[2]
    folder = path.rsplit("/", 1)[0] + "/" if "/" in path else ""
    shown = name or path.rsplit("/", 1)[-1]
    seen = filename_rules.matching(shown, folder + shown)
    for rule in rules:
        if filename_rules.RULES[rule] and rule not in seen:
            raise ValueError(f"{path}: expected {rule} to match {shown!r}")
    listed = [r for r in filename_rules.RULES if r in seen or (r in rules and not filename_rules.RULES[r])]
    media = {"container": container}
    if container == "isobmff" and data[4:8] == b"ftyp":
        media["brand"] = data[8:12].decode("latin-1")
    media.update(mime=mime, kind=kind, support="unsupported" if container in UNSUPPORTED_CONTAINERS else "supported")
    record = {"schema_version": 1, "path": path, "size": None, "sha256": None, "origin": "synthetic"}
    if name:
        record["original_name"] = name
    notes = " ".join(filter(None, [notes, payload_note(fmt, kind, meta or {})]))
    if notes:
        record["notes"] = notes
    record["format"] = fmt
    if vendor:
        record["vendor"] = vendor
    record.update(quirks=sorted(set(quirks)), media=media, metadata=meta or {})
    if group:
        record["group"] = group
    record["filename"] = {"matches": listed}
    record["capture_time"] = {"claims": list(claims), "resolved": resolved}
    ENTRIES[path] = {"data": data, "record": record, "sidecars": [(folder + n, d, k) for n, d, k in sidecars]}
    return path


def payload_note(fmt, kind, meta):
    """What does not decode, for files whose pixels or samples are placeholders."""
    codec = meta.get("codec")
    if fmt in NO_ENCODER:
        note = f"Placeholder {NO_ENCODER[fmt]} payload: the structure and metadata are real, the image does not decode."
    elif fmt in RAW:
        note = "Placeholder sensor data, not a camera mosaic; the embedded JPEG preview decodes."
    elif kind in ("video", "audio") and codec != "mjpeg":
        note = f"Placeholder {codec or kind} payload: the structure and metadata are real, the {kind} does not decode."
    else:
        note = None
    if "motion" in meta:
        note = " ".join(filter(None, [note, "The embedded motion video is a placeholder."]))
    return note


def collect():
    """Import every catalog and let it register its files; returns the registry."""
    if not ENTRIES:
        import catalog_compound
        import catalog_names
        import catalog_stills
        import catalog_time
        import catalog_video
        for module in (catalog_stills, catalog_video, catalog_compound, catalog_names, catalog_time):
            module.register()
    return ENTRIES
