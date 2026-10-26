#!/usr/bin/env python3
"""16 KB page-size check of Android native libraries (Google Play requires it; docs/10-client-app.md §5.6).

    tools/page_size.py <library.so | app.apk | app.aab>...

Every LOAD segment of each ELF library must be aligned to at least 16 KB, and an APK or app bundle must store each
uncompressed `lib/<abi>/*.so` at a 16 KB-aligned offset, where Android maps it in place. Exit status: 0 all pass,
1 a check failed, 2 usage error.
"""
import struct
import sys
import zipfile

PAGE = 16384
PT_LOAD = 1


def elf_problems(name, data):
    if data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
        return [f"{name}: not an ELF file"]
    wide, order = data[4] == 2, "<" if data[5] == 1 else ">"
    phoff, phentsize, phnum = (struct.unpack_from(order + "Q", data, 32)[0], *struct.unpack_from(order + "HH", data, 54)) \
        if wide else (struct.unpack_from(order + "I", data, 28)[0], *struct.unpack_from(order + "HH", data, 42))
    problems = []
    for index in range(phnum):
        entry = phoff + index * phentsize
        kind = struct.unpack_from(order + "I", data, entry)[0]
        align = struct.unpack_from(order + "Q", data, entry + 48)[0] if wide else \
            struct.unpack_from(order + "I", data, entry + 28)[0]
        if kind == PT_LOAD and align < PAGE:
            problems.append(f"{name}: LOAD segment aligned to {align}, needs {PAGE}")
    return problems


def archive_problems(path):
    problems, libraries = [], 0
    with zipfile.ZipFile(path) as archive, open(path, "rb") as raw:
        for info in archive.infolist():
            parts = info.filename.split("/")
            if not (info.filename.endswith(".so") and "lib" in parts[:-2]):
                continue
            libraries += 1
            name = f"{path}!{info.filename}"
            problems += elf_problems(name, archive.read(info))
            if info.compress_type == zipfile.ZIP_STORED:
                raw.seek(info.header_offset + 26)
                name_length, extra_length = struct.unpack("<HH", raw.read(4))
                offset = info.header_offset + 30 + name_length + extra_length
                if offset % PAGE:
                    problems.append(f"{name}: stored at offset {offset}, not a multiple of {PAGE}")
    return problems if libraries else [f"{path}: no native libraries (lib/<abi>/*.so)"]


def main(paths):
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    problems = []
    for path in paths:
        if zipfile.is_zipfile(path):
            found = archive_problems(path)
        else:
            with open(path, "rb") as file:
                found = elf_problems(path, file.read())
        problems += found
        print(f"ok: {path}" if not found else "\n".join(f"FAIL: {p}" for p in found))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
