#!/usr/bin/env python3
"""Bundles Homebrew's libvips, its libraries and its HEIF and JPEG XL modules into a built photolib.app (ADR-0394).

    tools/macos/bundle_vips.py <photolib.app> <entitlements> [--optional] [--prefix <arch>=<homebrew prefix>]...

The desktop app decodes photos for on-device ML (faces, text, search) through libvips, which it looks for in
Contents/Frameworks/libvips.42.dylib (app/lib/features/library/timeline/vips.dart). For each architecture of the app's
executable this finds that architecture's Homebrew (arm64: /opt/homebrew, x86_64: /usr/local), walks every
non-system dependency of libvips and of its modules, copies them into Contents/Frameworks (the modules into
Contents/Frameworks/vips-modules, which the app names in VIPS_MODULEDIR), points every install name and reference at
@loader_path, removes every RPATH, joins the architectures with lipo, signs each library, then the app, ad hoc with
the entitlements. An architecture without a Homebrew libvips is left out with a warning (an Intel Homebrew under
Rosetta installs with `arch -x86_64 /usr/local/bin/brew install vips`); without any, it fails (--optional: warns).
Running it again rebuilds the same Frameworks from Homebrew. Python's standard library and Xcode's otool,
install_name_tool, lipo and codesign only.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PREFIXES = {"arm64": "/opt/homebrew", "x86_64": "/usr/local"}
LIBRARY = "libvips.42.dylib"
SYSTEM = ("/usr/lib/", "/System/")
TIMEOUT = 300


class Failure(Exception):
    pass


def run(*command):
    done = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT, check=False)
    if done.returncode:
        raise Failure(f"{' '.join(map(str, command))} failed: {done.stderr.strip() or done.stdout.strip()}")
    return done.stdout


def references(file):
    """The install names `file` loads, not its own id (`otool -D`; a module has none): `otool -L` lists both."""
    own = [line.strip() for line in run("otool", "-D", file).splitlines()[1:]]
    lines = run("otool", "-L", file).splitlines()[1:]
    names = [line.strip().split(" (")[0] for line in lines if line.startswith("\t")]
    return [name for name in names if name not in own]


def rpaths(file):
    return re.findall(r"^\s+path (.+) \(offset \d+\)$", run("otool", "-l", file), re.MULTILINE)


def resolve(name, referrer, prefix):
    """The file an install name `name` in `referrer` stands for, or None."""
    if name.startswith(("@rpath/", "@loader_path/")):
        candidates = [Path(referrer).resolve().parent, Path(prefix) / "lib"]
        candidates = [directory / name.split("/", 1)[1] for directory in candidates]
    else:
        candidates = [Path(name)]
    return next((path.resolve() for path in candidates if path.exists()), None)


class Slice:
    """One architecture's libvips with everything it loads: names to the Homebrew files they came from."""

    def __init__(self, arch, prefix):
        self.arch, self.prefix = arch, prefix
        self.libraries = {}  # install name's file name -> source file
        self.modules = {}  # module file name -> source file
        self.edges = {}  # source file -> [(install name, library file name)]

    def walk(self):
        root = Path(self.prefix) / "lib" / LIBRARY
        modules = sorted(path for pattern in ("vips-*.dylib", "vips-*.so") for path in self.modules_dir().glob(pattern))
        pending = [(root, LIBRARY, False)] + [(path.resolve(), path.name, True) for path in modules]
        seen = set()
        while pending:
            source, name, module = pending.pop()
            (self.modules if module else self.libraries)[name] = source
            if (source, module) in seen:
                continue
            seen.add((source, module))
            edges = []
            for reference in references(source):
                if reference.startswith(SYSTEM) or reference in ("@executable_path", "@loader_path"):
                    continue
                target = resolve(reference, source, self.prefix)
                if target is None:
                    raise Failure(f"{source}: {reference} was not found; reinstall with `brew reinstall vips`")
                if target.as_posix().startswith(SYSTEM):
                    continue
                edges.append((reference, Path(reference).name))
                if Path(reference).name not in self.libraries:
                    pending.append((target, Path(reference).name, False))
            self.edges[source] = edges

    def modules_dir(self):
        found = sorted((Path(self.prefix) / "lib").glob("vips-modules-*"))
        return found[-1] if found else Path(self.prefix) / "lib" / "vips-modules-none"


def executable(app):
    files = [path for path in (app / "Contents" / "MacOS").iterdir() if path.is_file()]
    if len(files) != 1:
        raise Failure(f"{app}/Contents/MacOS holds {len(files)} executables, expected one")
    return files[0]


def stage(slc, directory):
    """Copies the slice's files into `directory` with their references rewritten; returns {destination: file}."""
    staged = {}
    for modules, files in ((False, slc.libraries), (True, slc.modules)):
        for name, source in files.items():
            copy = directory / ("vips-modules" if modules else ".") / name
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, copy)
            copy.chmod(0o644)
            up = "@loader_path/../" if modules else "@loader_path/"
            command = ["install_name_tool"]
            if not modules:
                command += ["-id", f"@loader_path/{name}"]
            for reference, library in slc.edges[source]:
                command += ["-change", reference, up + library]
            for rpath in rpaths(copy):
                command += ["-delete_rpath", rpath]
            if len(command) > 1:
                run(*command, copy)
            staged[(modules, name)] = copy
    return staged


def bundle(app, entitlements, prefixes, optional=False):
    frameworks = app / "Contents" / "Frameworks"
    archs = run("lipo", "-archs", executable(app)).split()
    slices, missing = [], []
    for arch in archs:
        slc = Slice(arch, prefixes.get(arch, PREFIXES.get(arch, "")))
        if (Path(slc.prefix) / "lib" / LIBRARY).exists():
            slc.walk()
            slices.append(slc)
        else:
            missing.append(arch)
    if not slices:
        why = (
            f"libvips was not found for {', '.join(archs)} ({', '.join(PREFIXES.get(a, a) for a in archs)}): "
            "install it with `brew install vips`, then build again"
        )
        if not optional:
            raise Failure(why)
        print(f"WARNING: {why}; this app finds no faces or text", file=sys.stderr)
        return
    for arch in missing:
        print(
            f"WARNING: no Homebrew libvips for {arch}: its slice has none, and face finding is unavailable there "
            f"(on an Apple silicon Mac: arch -x86_64 /usr/local/bin/brew install vips)",
            file=sys.stderr,
        )
    shutil.rmtree(frameworks / "vips-modules", ignore_errors=True)
    frameworks.mkdir(parents=True, exist_ok=True)
    signed = []
    with tempfile.TemporaryDirectory() as temp:
        staged = [stage(slc, Path(temp) / slc.arch) for slc in slices]
        for key in sorted({key for one in staged for key in one}, key=lambda k: (k[0], k[1])):
            modules, name = key
            parts = [one[key] for one in staged if key in one]
            destination = frameworks / ("vips-modules" if modules else ".") / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.unlink(missing_ok=True)
            if len(parts) > 1:
                run("lipo", "-create", *parts, "-output", destination)
            else:
                shutil.copyfile(parts[0], destination)
            signed.append(destination)
    # Modules before libraries before the app: a signature covers what it holds.
    for path in sorted(signed, key=lambda p: (p.parent.name != "vips-modules", p.name)):
        run("codesign", "--force", "--sign", "-", path)
    run("codesign", "--force", "--sign", "-", "--entitlements", entitlements, app)
    run("codesign", "--verify", "--deep", "--strict", app)
    print(
        f"bundle_vips: {sum(1 for p in signed if p.parent.name != 'vips-modules')} libraries and "
        f"{sum(1 for p in signed if p.parent.name == 'vips-modules')} modules for {', '.join(s.arch for s in slices)}"
        + (f"; no libvips for {', '.join(missing)}" if missing else "")
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("app", type=Path)
    parser.add_argument("entitlements", type=Path)
    parser.add_argument("--optional", action="store_true", help="only warn when there is no libvips (debug builds)")
    parser.add_argument("--prefix", action="append", default=[], metavar="ARCH=PREFIX")
    args = parser.parse_args()
    prefixes = dict(item.split("=", 1) for item in args.prefix)
    try:
        if not (args.app / "Contents" / "MacOS").is_dir():
            raise Failure(f"{args.app} is not a built app")
        bundle(args.app.resolve(), args.entitlements.resolve(), prefixes, args.optional)
    except (Failure, subprocess.TimeoutExpired, OSError) as error:
        sys.exit(f"bundle_vips: {error}")


if __name__ == "__main__":
    os.umask(0o022)
    main()
