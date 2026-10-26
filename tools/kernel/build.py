#!/usr/bin/env python3
"""Builds the kernel's C ABI (kernel/ffi) for native targets and pins the libraries for the app's build hook.

    tools/kernel/build.py --out <dir> [--release <url>] [<target>...]

Each target is built in release mode and copied to <dir>/<target>-<library>. Then <dir>/prebuilt.json pins the
SHA-256 of every library in <dir>, and with --release the URL they are published under: the file that
app/packages/photolib_kernel/hook/build.dart verifies; a library over ADR-0004's size budget fails it. Android links
with the NDK's clang (ANDROID_NDK_HOME, else the newest under $ANDROID_HOME/ndk) for 16 KB pages; the other targets
need their platform's own linker. Cargo is found on PATH, else in $CARGO_HOME/bin (~/.cargo/bin: rustup's proxy), else
in the toolchain rust-toolchain.toml pins under $RUSTUP_HOME/toolchains (~/.rustup), so a build started without a shell
profile (a Dart build hook, Xcode) needs no PATH.
"""
import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

KERNEL = Path(__file__).resolve().parents[2] / "kernel"
ANDROID_API = 24  # Flutter's default minSdk
BUDGET = 3_000_000  # bytes of app size per native ABI (ADR-0004)
TARGETS = {
    "android-arm64": "aarch64-linux-android",
    "android-arm": "armv7-linux-androideabi",
    "android-x64": "x86_64-linux-android",
    "ios-arm64": "aarch64-apple-ios",
    "ios-sim-arm64": "aarch64-apple-ios-sim",
    "ios-sim-x64": "x86_64-apple-ios",
    "macos-arm64": "aarch64-apple-darwin",
    "macos-x64": "x86_64-apple-darwin",
    "windows-x64": "x86_64-pc-windows-msvc",
    "linux-x64": "x86_64-unknown-linux-gnu",
    "linux-arm64": "aarch64-unknown-linux-gnu",
}


def android_env(triple):
    ndk = os.environ.get("ANDROID_NDK_HOME")
    if not ndk:
        root = Path(os.environ.get("ANDROID_HOME", "")) / "ndk"
        versions = sorted((p for p in root.glob("*") if p.is_dir()),
                          key=lambda p: [int(part) for part in p.name.split(".") if part.isdigit()])
        if not versions:
            sys.exit("build.py: Android NDK not found; set ANDROID_NDK_HOME or ANDROID_HOME")
        ndk = versions[-1]
    host = {"Linux": "linux-x86_64", "Darwin": "darwin-x86_64", "Windows": "windows-x86_64"}[platform.system()]
    clang = f"{triple.replace('armv7-', 'armv7a-')}{ANDROID_API}-clang" + (".cmd" if host.startswith("win") else "")
    key = "CARGO_TARGET_" + triple.upper().replace("-", "_")
    return {key + "_LINKER": str(Path(ndk) / "toolchains" / "llvm" / "prebuilt" / host / "bin" / clang),
            key + "_RUSTFLAGS": "-C link-arg=-Wl,-z,max-page-size=16384"}


def rust_path():
    """PATH followed by the directories that hold cargo or rustup: rustup's proxies, then the pinned toolchain."""
    home = Path.home()
    cargo_home = Path(os.environ.get("CARGO_HOME") or home / ".cargo")
    rustup_home = Path(os.environ.get("RUSTUP_HOME") or home / ".rustup")
    pin = re.search(r'^channel\s*=\s*"([^"]+)"', (KERNEL.parent / "rust-toolchain.toml").read_text(), re.MULTILINE)
    toolchains = sorted((rustup_home / "toolchains").glob(pin.group(1) + "-*")) if pin else []
    dirs = [cargo_home / "bin"] + [toolchain / "bin" for toolchain in toolchains]
    dirs = [str(d) for d in dirs if any(shutil.which(tool, path=str(d)) for tool in ("cargo", "rustup"))]
    return os.pathsep.join([os.environ.get("PATH", "")] + dirs)


def build(target, out):
    triple, os_name = TARGETS[target], target.split("-")[0]
    name = {"windows": "photolib_kernel_ffi.dll", "ios": "libphotolib_kernel_ffi.dylib",
            "macos": "libphotolib_kernel_ffi.dylib"}.get(os_name, "libphotolib_kernel_ffi.so")
    env = dict(os.environ, **(android_env(triple) if target.startswith("android-") else {}), PATH=rust_path())
    if not shutil.which("cargo", path=env["PATH"]):
        sys.exit("build.py: cargo not found on PATH, in ~/.cargo/bin or in the toolchain rust-toolchain.toml pins "
                 "under ~/.rustup/toolchains; install Rust with rustup (https://rustup.rs) and run this again")
    if shutil.which("rustup", path=env["PATH"]):
        subprocess.run(["rustup", "target", "add", triple], cwd=KERNEL, env=env, check=True)
    cargo = subprocess.run(["cargo", "build", "--release", "--locked", "-p", "photolib-kernel-ffi", "--target", triple,
                            "--message-format=json-render-diagnostics"],
                           cwd=KERNEL, env=env, stdout=subprocess.PIPE, text=True)
    if cargo.returncode:
        sys.exit(f"build.py: cargo failed for {target}")
    built = [file for line in cargo.stdout.splitlines() if line.startswith("{")
             for message in [json.loads(line)] if message.get("reason") == "compiler-artifact"
             and message["target"]["name"] == "photolib_kernel_ffi"
             for file in message["filenames"] if Path(file).name == name]
    shutil.copyfile(built[-1], out / f"{target}-{name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--release")
    parser.add_argument("targets", nargs="*", choices=TARGETS)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for target in args.targets:
        build(target, args.out)
    libraries = [file for file in sorted(args.out.iterdir()) if file.suffix in (".so", ".dylib", ".dll")]
    for file in libraries:
        print(f"{file.name}: {file.stat().st_size} bytes, budget {BUDGET}")
    over = [file.name for file in libraries if file.stat().st_size > BUDGET]
    if over:
        sys.exit(f"build.py: over ADR-0004's budget of {BUDGET} bytes per native ABI: {', '.join(over)}")
    pins = {file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in libraries}
    manifest = {"release": args.release} if args.release else {}
    # Written aside and renamed: two builds of one output (the hook's, per architecture) never read half a file.
    pending = args.out / f"prebuilt.json.{os.getpid()}"
    pending.write_text(json.dumps({**manifest, "sha256": pins}, indent=2) + "\n")
    pending.replace(args.out / "prebuilt.json")


if __name__ == "__main__":
    main()
