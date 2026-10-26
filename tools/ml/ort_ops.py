#!/usr/bin/env python3
"""Writes ONNX Runtime's operator config for a reduced build, tools/ml/ort-ops.config (the format of build.py's
--include_ops_by_config: "<domain>;<opset>;<op>,<op>..." lines), from the models devices run: the files of
server/crates/photolib-models/registry.json for Android, by their pins in tools/ml/artefacts.json (ADR-0050).
tools/ml/ort_android.sh builds ONNX Runtime with it.

    tools/ml/ort_ops.py           # fetches those models (tools/ml/fetch.py) and writes the config
    tools/ml/ort_ops.py --check   # fails when the config misses an operator of one of them in the tools cache

It reads ONNX's protobuf wire format itself, nested graphs (If, Loop, Scan) included, as create_reduced_build_config.py
does with the onnx package: each node's operator at the opset its model imports for the domain.
"""
import json
import mmap
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import fetch

CONFIG = Path(__file__).parent / "ort-ops.config"
REGISTRY = Path(__file__).parents[2] / "server/crates/photolib-models/registry.json"


def fields(buf, start, end):
    """Yields (number, value) of each field of the message at buf[start:end]: a varint's value, a length-delimited
    field's (start, end), None for a fixed-size one."""
    def varint():
        nonlocal start
        value = shift = 0
        while buf[start] & 0x80:
            value, shift, start = value | (buf[start] & 0x7F) << shift, shift + 7, start + 1
        value, start = value | buf[start] << shift, start + 1
        return value

    while start < end:
        key = varint()
        wire = key & 7
        if wire == 0:
            value = varint()
        elif wire == 2:
            size = varint()
            value, start = (start, start + size), start + size
        elif wire in (1, 5):
            value, start = None, start + (8 if wire == 1 else 4)
        else:
            raise ValueError(f"wire type {wire} at byte {start}")
        yield key >> 3, value


def text(buf, span):
    return buf[span[0]:span[1]].decode()


def graph_ops(buf, graph, opsets, found):
    for number, node in fields(buf, *graph):
        if number != 1:  # GraphProto.node
            continue
        op, domain = "", ""
        for n, value in fields(buf, *node):
            if n == 4:  # NodeProto.op_type
                op = text(buf, value)
            elif n == 7:  # NodeProto.domain
                domain = text(buf, value)
            elif n == 5:  # NodeProto.attribute, whose g (6) and graphs (11) are subgraphs
                for a, subgraph in fields(buf, *value):
                    if a in (6, 11):
                        graph_ops(buf, subgraph, opsets, found)
        domain = domain or "ai.onnx"
        found.add((domain, opsets[domain], op))


def model_ops(path):
    """The (domain, opset, operator) of every node of the ONNX model at path."""
    with open(path, "rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as buf:
        opsets, graph, found = {}, None, set()
        for number, value in fields(buf, 0, len(buf)):
            if number == 8:  # ModelProto.opset_import: domain (1), version (2)
                entry = dict(fields(buf, *value))
                opsets[(text(buf, entry[1]) if 1 in entry else "") or "ai.onnx"] = entry[2]
            elif number == 7:  # ModelProto.graph
                graph = value
            elif number == 25:
                sys.exit(f"ort_ops.py: {path} has model-local functions, which this does not read")
        graph_ops(buf, graph, opsets, found)
        return found


def device_models():
    """The pins of the registry's files for Android."""
    pins = {pin["sha256"]: name for name, pin in fetch.PINS.items()}
    files = [f for model in json.loads(REGISTRY.read_text()) for f in model["files"] if "android" in f["targets"]]
    if unpinned := [f["name"] for f in files if f["sha256"] not in pins]:
        sys.exit(f"ort_ops.py: tools/ml/artefacts.json pins no {' '.join(unpinned)}")
    return [pins[f["sha256"]] for f in files]


def cached(name):
    """The model's file where fetch.py keeps it."""
    pin = fetch.PINS[name]
    return fetch.cache_root() / f"{name}-{pin['sha256'][:16]}" / pin["url"].rsplit("/", 1)[1]


def main(args):
    if args not in ([], ["--check"]):
        sys.exit(__doc__)
    names = device_models()
    if not args:
        ops = {}
        for name in names:
            for domain, opset, op in model_ops(fetch.fetch(name)[0]):
                ops.setdefault((domain, opset), set()).add(op)
        CONFIG.write_text(
            "# The operators of the models devices run, for ONNX Runtime's reduced build (tools/ml/ort_android.sh):\n"
            f"# {' '.join(names)}. Written by python3 tools/ml/ort_ops.py; do not edit.\n"
            + "".join(f"{domain};{opset};{','.join(sorted(o))}\n" for (domain, opset), o in sorted(ops.items())))
        return
    checked = [name for name in names if cached(name).is_file()]
    if not checked:
        sys.exit(f"ort_ops.py: no device model is in the tools cache; fetch one: python3 tools/ml/fetch.py {names[0]}")
    have = {(domain, int(opset), op) for line in CONFIG.read_text().splitlines() if line and not line.startswith("#")
            for domain, opset, ops in [line.split(";")] for op in ops.split(",")}
    missing = sorted(set().union(*(model_ops(cached(name)) for name in checked)) - have)
    if missing:
        sys.exit(f"ort_ops.py: {CONFIG.name} misses {' '.join(f'{d};{v};{o}' for d, v, o in missing)}; "
                 "write it again: python3 tools/ml/ort_ops.py")
    skipped = [name for name in names if name not in checked]
    print(f"{CONFIG.name} holds every operator of {' '.join(checked)}"
          + (f" (not in the tools cache: {' '.join(skipped)})" if skipped else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
