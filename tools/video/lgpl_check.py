"""ADR-0013's licence check on the Windows libmpv tools/video/libmpv.sh builds: every FFmpeg library says it is LGPL
and is configured without --enable-gpl or --enable-nonfree, and libmpv's features hold no `gpl` (-Dgpl=false).

    tools/video/lgpl_check.py <directory of the DLLs>
"""

import re
import sys
from pathlib import Path


def problems(directory):
    dlls = sorted(Path(directory).glob("*.dll"))
    ffmpeg = [dll for dll in dlls if re.fullmatch(r"(av|sw)[a-z]+-\d+\.dll", dll.name)]
    mpv = [dll for dll in dlls if dll.name.startswith("libmpv")]
    if not ffmpeg or not mpv:
        yield f"{directory} holds no FFmpeg or no libmpv"
    for dll in ffmpeg:
        data = dll.read_bytes()
        if b"LGPL version 2.1 or later" not in data:
            yield f"{dll.name} does not say LGPL version 2.1 or later"
        for flag in ("--enable-gpl", "--enable-nonfree"):
            if re.search(re.escape(flag.encode()) + rb"[\s\0]", data):
                yield f"{dll.name} is configured with {flag}"
    for dll in mpv:
        features = [
            m[1].decode().split() for m in re.finditer(rb"List of enabled features: ([a-z0-9 -]+)\n", dll.read_bytes())
        ]
        if len(features) != 1:
            yield f"{dll.name}: no list of its features, so no telling whether it is LGPL"
        elif "gpl" in features[0]:
            yield f"{dll.name} is built with its GPL parts (gpl among its features)"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: tools/video/lgpl_check.py <directory of the DLLs>")
    found = list(problems(sys.argv[1]))
    for problem in found:
        print(f"lgpl_check.py: {problem}", file=sys.stderr)
    sys.exit(1 if found else 0)
