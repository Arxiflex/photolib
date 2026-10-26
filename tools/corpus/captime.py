"""Capture-time claims and resolved outcomes for golden records, built from the same inputs as the file bytes."""
from datetime import datetime, timedelta

import tiffexif

RANK = {"ms": 23, "s": 19, "min": 16, "day": 10, "month": 7, "year": 4}


def claim(source, value, precision, event="capture", offset=None, rejected=None):
    out = {"source": source, "kind": "utc" if value and value.endswith("Z") else "local", "value": value,
           "precision": precision, "event": event}
    if offset:
        out["offset"] = offset
    if rejected:
        out["rejected"] = rejected
    return out


def convert(stamp, offset, to_utc):
    """Local to UTC (or back) for a 'YYYY-MM-DDTHH:MM:SS[.mmm]' value; milliseconds pass through."""
    base = datetime.fromisoformat(stamp.rstrip("Z")[:19])
    sign = -1 if offset.startswith("-") else 1
    delta = timedelta(hours=int(offset[1:3]), minutes=int(offset[4:6])) * sign
    text = (base - delta if to_utc else base + delta).strftime("%Y-%m-%dT%H:%M:%S")
    return text + stamp.rstrip("Z")[19:] + ("Z" if to_utc else "")


def resolve(source, *, local=None, utc=None, offset=None, tz="explicit_offset", precision="s", band="high",
            bound="exact", flags=()):
    """The expected outcome. Whichever of local and utc is missing is derived from the other and the offset."""
    if precision in ("s", "ms") and offset:
        if local and not utc:
            utc = convert(local, offset, True)
        elif utc and not local:
            local = convert(utc, offset, False)
    return {"local": local, "utc": utc, "offset": offset, "tz_source": tz, "precision": precision, "bound": bound,
            "source": source, "confidence_band": band, "flags": list(flags)}


def home_time(local, offset, there):
    """A camera on another zone than its GPS position's, which is on offset there: the camera's offset fixes the
    instant, the position's zone shows the wall clock, for review (ADR-0051)."""
    return resolve("exif_dto_with_offset", utc=convert(local, offset, True), offset=there, tz="gps_polygon",
                   flags=("needs_review", "zone_mismatch"))


def offset_between(local, utc):
    """The whole-quarter-hour offset that turns the UTC reading into the local one."""
    minutes = round((datetime.fromisoformat(local[:19]) - datetime.fromisoformat(utc[:19])).total_seconds() / 900) * 15
    sign = "-" if minutes < 0 else "+"
    return f"{sign}{abs(minutes) // 60:02d}:{abs(minutes) % 60:02d}"


def exif_time(local, offset=None, subsec=None, gps_utc=None):
    """What a camera wrote for one shot: (EXIF fields, claims a parser must extract, expected resolution).

    local is 'YYYY-MM-DDTHH:MM:SS', offset '+02:00' (OffsetTimeOriginal), subsec three digits, gps_utc the GPS time.
    """
    fields = {"original": tiffexif.exif_text(local), "offsets": (None, offset, None), "subsec": subsec}
    value, precision = (f"{local}.{subsec}", "ms") if subsec else (local, "s")
    source = "exif_dto_with_offset" if offset else "exif_dto_no_offset"
    claims = [claim(source, value, precision, offset=offset)]
    if gps_utc:
        claims.append(claim("gps_datetime", gps_utc + "Z", "s"))
    if offset:
        return fields, claims, resolve(source, local=value, offset=offset, precision=precision)
    if gps_utc:
        return fields, claims, resolve(source, local=value, utc=gps_utc + "Z", offset=offset_between(local, gps_utc),
                                       tz="gps_delta", precision=precision)
    return fields, claims, resolve(source, local=value, tz="floating", band="medium", precision=precision)


def name_claim(rule, local, precision="s", event="capture", utc=False, rejected=None):
    """A claim parsed from the file name by rule F01..F56; local values carry no zone, utc ones end in Z."""
    value = None if local is None else local + ("Z" if utc else "")
    return claim(f"filename:{rule}", value, precision, event, rejected=rejected)


def from_name(rule, local, *, precision="s", event="capture", band="medium", tz="floating", offset=None, utc=None,
              bound="exact", flags=()):
    """(claims, resolved) for a file with nothing but its name: the name wins at its own precision."""
    pick = name_claim(rule, local, precision, event, utc=utc is True)
    value = pick["value"]
    if utc is True:
        return [pick], resolve(f"filename:{rule}", utc=value, offset=offset, tz=tz, precision=precision, band=band,
                               bound=bound, flags=flags)
    return [pick], resolve(f"filename:{rule}", local=value, offset=offset, tz=tz, precision=precision, band=band,
                           bound=bound, flags=flags)
