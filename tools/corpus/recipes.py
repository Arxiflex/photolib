"""One camera shot as the EXIF block, the golden metadata and the capture-time expectations that go with it."""
import captime
import tiffexif


def shot(make, model, local, offset=None, *, size=None, subsec=None, gps=None, orientation=None, software=None,
         thumb=None, e="<", head4=None, extra=b"", maker_note=None, extra0=(), extra_exif=(), bad_exif_pointer=False):
    """Returns (EXIF block, metadata, claims, resolved).

    local is 'YYYY-MM-DDTHH:MM:SS' or None for a camera that stored no time. gps is (lat, lon, altitude, 'UTC time').
    """
    fields, claims, resolved = ({}, [], None)
    if local:
        fields, claims, resolved = captime.exif_time(local, offset, subsec, gps[3] if gps else None)
    block = tiffexif.exif_block(
        thumb=thumb, e=e, head4=head4, extra=extra, make=make, model=model, software=software, orientation=orientation,
        size=size, gps=tiffexif.gps_ifd(*gps) if gps else None, maker_note=maker_note, extra0=extra0,
        extra_exif=extra_exif, bad_exif_pointer=bad_exif_pointer, **fields)
    meta = {}
    if size:
        meta.update(width=size[0], height=size[1])
    if orientation:
        meta["orientation"] = orientation
    if make:
        meta["make"] = make
    if model:
        meta["model"] = model
    if gps:
        meta["gps"] = {"lat": gps[0], "lon": gps[1]}
    return block, meta, claims, resolved
