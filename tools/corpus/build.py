#!/usr/bin/env python3
"""Generate testdata/corpus from the catalogs, byte for byte reproducibly.

    python3 tools/corpus/build.py          rewrite testdata/corpus/files and testdata/corpus/golden
    python3 tools/corpus/build.py --check  fail when the committed tree differs from what the catalogs produce
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

import avc_twins
import entries

ROOT = Path(__file__).resolve().parents[2] / "testdata" / "corpus"


def render():
    """Everything the corpus consists of, as {path relative to testdata/corpus: bytes}."""
    out = {}
    for path, item in entries.collect().items():
        data = item["data"]
        sidecars = []
        for sidecar_path, sidecar_data, kind in item["sidecars"]:
            out[f"files/{sidecar_path}"] = sidecar_data
            sidecars.append({"path": sidecar_path, "kind": kind, "sha256": hashlib.sha256(sidecar_data).hexdigest()})
        record = {}
        for key, value in item["record"].items():
            if key == "filename" and sidecars:
                record["sidecars"] = sidecars
            record[key] = value
        record["size"] = len(data)
        record["sha256"] = hashlib.sha256(data).hexdigest()
        out[f"files/{path}"] = data
        out[f"golden/{path}.json"] = (json.dumps(record, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    out.update(avc_twins.render())
    return out


def on_disk():
    return {
        str(file.relative_to(ROOT)): file.read_bytes()
        for folder in ("files", "golden", "twins") if (ROOT / folder).is_dir()
        for file in (ROOT / folder).rglob("*") if file.is_file()
    }


def main(argv):
    wanted = render()
    if argv == ["--check"]:
        have = on_disk()
        problems = [f"missing: {p}" for p in sorted(wanted.keys() - have.keys())]
        problems += [f"stale: {p}" for p in sorted(have.keys() - wanted.keys())]
        problems += [f"differs: {p}" for p in sorted(wanted.keys() & have.keys()) if wanted[p] != have[p]]
        for problem in problems[:20]:
            print(problem, file=sys.stderr)
        if problems:
            print(f"corpus is out of date ({len(problems)} files): run python3 tools/corpus/build.py", file=sys.stderr)
            return 1
        print(f"corpus is up to date ({len(wanted)} files)")
        return 0
    if argv:
        print(__doc__, file=sys.stderr)
        return 2
    for folder in ("files", "golden", "twins"):
        shutil.rmtree(ROOT / folder, ignore_errors=True)
    for relative, data in wanted.items():
        target = ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print(f"wrote {len(entries.ENTRIES)} entries, {len(wanted)} files under {ROOT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
