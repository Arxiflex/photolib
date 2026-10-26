#!/usr/bin/env python3
"""Validate the media corpus: every golden record against golden.schema.json and against its file.

Usage: validate.py [--root DIR] [--min-entries N]    (defaults: testdata/corpus, 300)
Exit status 1 and one line per problem when the corpus is not sound.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filename_rules  # noqa: E402
import jsonschema_lite  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_ROOT = os.path.join(REPO, "testdata", "corpus")
UNPORTABLE = re.compile(r'[<>:"\\|?*\x00-\x1f]|[ .]$|^ ')
LOCAL_LENGTH = {"year": 4, "month": 7, "day": 10, "min": 16, "s": 19, "ms": 23}
PAD = {4: "-01-01T00:00:00", 7: "-01T00:00:00", 10: "T00:00:00", 16: ":00", 19: "", 23: ""}
TIFF_MAGIC = (b"II*\0", b"MM\0*", b"II+\0", b"MM\0+", b"IIRO", b"IIRS", b"IIU\0")
JXL_BOX = bytes.fromhex("0000000c4a584c200d0a870a")
ASF_GUID = bytes.fromhex("3026b2758e66cf11a6d900aa0062ce6c")


def sniff(data):
    """The container the magic bytes announce, and the ISOBMFF major brand when there is one."""
    head = data[:16]
    if head[:3] == b"\xff\xd8\xff":
        return "jpeg", None
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return "png", None
    if head[:4] == b"GIF8":
        return "gif", None
    if head[:2] == b"BM":
        return "bmp", None
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp", None
    if head[:4] == b"RIFF" and head[8:12] == b"AVI ":
        return "avi", None
    if head[4:8] == b"ftyp":
        return "isobmff", data[8:12].decode("latin-1")
    if head[4:8] in (b"moov", b"mdat", b"wide"):
        return "isobmff", None
    if head[:4] in TIFF_MAGIC:
        return "tiff", None
    if head[:4] == b"8BPS":
        return "psd", None
    if head[:15] == b"FUJIFILMCCD-RAW":
        return "raf", None
    if head[:4] == b"\x1a\x45\xdf\xa3":
        return "ebml", None
    if len(data) > 196 and data[0] == 0x47 and data[188] == 0x47:
        return "mpegts", None
    if len(data) > 196 and data[4] == 0x47 and data[196] == 0x47:
        return "m2ts", None
    if head[:4] == b"\x00\x00\x01\xba":
        return "mpegps", None
    if head[:16] == ASF_GUID:
        return "asf", None
    if head[:4] == b"FLV\x01":
        return "flv", None
    if head[:2] == b"\xff\x0a" or data[:12] == JXL_BOX:
        return "jxl", None
    if head[:4] == b"%PDF":
        return "pdf", None
    if head[:4] == b"%!PS" or head[:4] == b"\xc5\xd0\xd3\xc6":
        return "eps", None
    if head[:4] == b"OggS":
        return "ogg", None
    if b"<svg" in data[:1024]:
        return "svg", None
    return "unknown", None


def read(path):
    with open(path, "rb") as handle:
        return handle.read()


def walk(base):
    found = []
    for folder, _, names in os.walk(base):
        for name in names:
            found.append(os.path.relpath(os.path.join(folder, name), base).replace(os.sep, "/"))
    return sorted(found)


def load_schema(root):
    return json.loads(read(os.path.join(root, "golden.schema.json")))


def load_goldens(root):
    """(relative golden path, record or None, error or None) for every file below golden/."""
    out = []
    for rel in walk(os.path.join(root, "golden")):
        try:
            out.append((rel, json.loads(read(os.path.join(root, "golden", rel))), None))
        except ValueError as error:
            out.append((rel, None, f"golden/{rel}: not valid JSON ({error})"))
    return out


def parse_time(text, offset=None):
    """An aware UTC datetime for a (possibly truncated) ISO value; local values need their offset."""
    body = text.rstrip("Z")
    stamp = datetime.fromisoformat(body + PAD[len(body)])
    if text.endswith("Z"):
        return stamp.replace(tzinfo=timezone.utc)
    sign = -1 if offset.startswith("-") else 1
    delta = timedelta(hours=int(offset[1:3]), minutes=int(offset[4:6]))
    return (stamp - sign * delta).replace(tzinfo=timezone.utc)


def time_errors(record, label):
    errors = []
    capture = record.get("capture_time", {})
    sources = set()
    for number, claim in enumerate(capture.get("claims", [])):
        sources.add(claim.get("source"))
        value = claim.get("value")
        if value is None:
            continue
        if value.endswith("Z") != (claim.get("kind") == "utc"):
            errors.append(f"{label}: claim {number} kind {claim.get('kind')!r} disagrees with value {value!r}")
        precision = claim.get("precision")
        if precision and not value.endswith("Z") and len(value) != LOCAL_LENGTH[precision]:
            errors.append(f"{label}: claim {number} value {value!r} does not have precision {precision}")
    final = capture.get("resolved")
    if not final:
        return errors
    if final["local"] is None and final["utc"] is None:
        errors.append(f"{label}: resolved needs a local or a utc time")
    if final["source"] not in sources:
        errors.append(f"{label}: resolved source {final['source']!r} is not one of the claims")
    if final["local"] and len(final["local"]) != LOCAL_LENGTH[final["precision"]]:
        errors.append(f"{label}: resolved local {final['local']!r} does not have precision {final['precision']}")
    if final["local"] and final["utc"]:
        if final["offset"] is None:
            errors.append(f"{label}: resolved has local and utc but no offset")
        elif parse_time(final["local"], final["offset"]) != parse_time(final["utc"]):
            errors.append(f"{label}: resolved utc {final['utc']} is not local {final['local']} minus {final['offset']}")
    return errors


def filename_errors(record, rel, label):
    name = record.get("original_name") or rel.rsplit("/", 1)[-1]
    path = rel.rsplit("/", 1)[0] + "/" + name if "/" in rel else name
    expected = filename_rules.matching(name, path)
    listed = record.get("filename", {}).get("matches", [])
    errors = [f"{label}: filename rule {rule} matches {name!r} but is not listed" for rule in expected if rule not in listed]
    errors += [
        f"{label}: filename rule {rule} is listed but does not match {name!r}"
        for rule in listed
        if filename_rules.RULES.get(rule) and rule not in expected
    ]
    return errors


def check_tree(root):
    errors = []
    schema = load_schema(root)
    files = walk(os.path.join(root, "files"))
    claimed = set()
    seen = {}
    for rel in files:
        folded = rel.lower()
        if folded in seen:
            errors.append(f"files/{rel}: collides with files/{seen[folded]} on a case-insensitive disk (case)")
        seen[folded] = rel
        if any(UNPORTABLE.search(part) for part in rel.split("/")):
            errors.append(f"files/{rel}: name is not portable to Windows or macOS")
    for gold_rel, record, problem in load_goldens(root):
        label = f"golden/{gold_rel}"
        if problem:
            errors.append(problem)
            continue
        path = gold_rel[:-5] if gold_rel.endswith(".json") else gold_rel
        errors += [f"{label}: {e}" for e in jsonschema_lite.validate(record, schema)]
        if record.get("path") != path:
            errors.append(f"{label}: path {record.get('path')!r} does not mirror the golden location {path!r}")
        if path not in files:
            errors.append(f"{label}: no file files/{path}")
            continue
        claimed.add(path)
        data = read(os.path.join(root, "files", path))
        if record.get("size") != len(data):
            errors.append(f"{label}: size {record.get('size')} but the file has {len(data)} bytes")
        if record.get("sha256") != hashlib.sha256(data).hexdigest():
            errors.append(f"{label}: sha256 does not match the file")
        container, brand = sniff(data)
        media = record.get("media", {})
        if media.get("container") != container:
            errors.append(f"{label}: container {media.get('container')!r} but the magic bytes say {container!r}")
        if media.get("brand") and media["brand"] != brand:
            errors.append(f"{label}: brand {media['brand']!r} but ftyp says {brand!r}")
        for side in record.get("sidecars", []):
            target = os.path.join(root, "files", side.get("path", ""))
            if not os.path.isfile(target):
                errors.append(f"{label}: sidecar {side.get('path')!r} does not exist")
                continue
            claimed.add(side["path"])
            if hashlib.sha256(read(target)).hexdigest() != side.get("sha256"):
                errors.append(f"{label}: sidecar {side['path']!r} does not match its sha256")
        try:
            errors += time_errors(record, label)
            errors += filename_errors(record, path, label)
        except (KeyError, TypeError, ValueError):
            pass  # the schema errors above already describe the malformed part
    errors += [f"files/{rel}: file has no golden record" for rel in files if rel not in claimed]
    return errors


def check_coverage(root, min_entries):
    schema = load_schema(root)
    defs = schema["$defs"]
    records = [record for _, record, problem in load_goldens(root) if not problem]
    errors = []
    if len(records) < min_entries:
        errors.append(f"entries: {len(records)} golden records, at least {min_entries} required")
    used = {"format": set(), "vendor": set(), "quirk": set(), "rule": set(), "container": set()}
    for record in records:
        used["format"].add(record.get("format"))
        used["vendor"].add(record.get("vendor"))
        used["quirk"].update(record.get("quirks", []))
        used["rule"].update(record.get("filename", {}).get("matches", []))
        used["container"].add(record.get("media", {}).get("container"))
    vocabulary = {
        "format": defs["format"]["enum"],
        "vendor": defs["vendor"]["enum"],
        "quirk": defs["quirk"]["enum"],
        "rule": list(filename_rules.RULES),
        "container": schema["properties"]["media"]["properties"]["container"]["enum"],
    }
    for kind, values in vocabulary.items():
        errors += [f"{kind}:{value} is never used by any entry" for value in values if value not in used[kind]]
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=DEFAULT_ROOT)
    parser.add_argument("--min-entries", type=int, default=300)
    args = parser.parse_args()
    errors = check_tree(args.root) + check_coverage(args.root, args.min_entries)
    for error in errors:
        print(error)
    if errors:
        print(f"corpus: {len(errors)} problem(s)", file=sys.stderr)
        return 1
    print(f"corpus: {len(load_goldens(args.root))} entries, all consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
