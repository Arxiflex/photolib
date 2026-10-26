# ADR-0229 — Windows video: our own LGPL libmpv and FFmpeg, cross-built reproducibly and taken by hash

* **Status**: Accepted — 2026-10-23. The owner kept all four choices
  (photolib-design#701,
  the provisional choices of photolib-design#508, roadmap M1-39): software rendering without ANGLE, this repository's
  release by hash, the llvm-mingw cross-build, and a Windows build that fails without the archive.
* **Requirements**: R-APP-5. **Design**: docs/10 §4.2, [ADR-0013](0013-licence.md),
  [ADR-0112](0112-video-and-motion-photo-playback.md).

## Context

ADR-0112 plays video on Windows and Linux through libmpv (media_kit_video). Linux links the system's libmpv; ADR-0013
forbids a vendor's prebuilt binary, so Windows had none and its videos said they could not play. media_kit_video's
Windows plugin, when `MEDIA_KIT_LIBS_AVAILABLE` is set, compiles against `<binary dir>/libmpv/include`, links
`libmpv/libmpv.dll.a`, and links ANGLE (`ANGLE/include`, `ANGLE/lib/libEGL.dll.lib`, `libGLESv2.dll.lib`) for its
hardware path. media_kit_libs_windows_video provides them by downloading a 2023 libmpv and a prebuilt ANGLE (with
SwiftShader and a Vulkan loader), checked by MD5. GitHub Actions minutes are off, so the build is a script.

## Decision

We will:

* **Cross-build on Linux x86-64** (WSL on Windows) with `bash tools/video/libmpv.sh`: llvm-mingw 20261006 (UCRT),
  meson 1.12.1 and nasm 3.02, each pinned by SHA-256; FFmpeg 8.1.3 (the release the tests' FFmpeg is), mpv 0.41.0,
  libplacebo 7.360.1, libass 0.17.5, FreeType 2.15.0, HarfBuzz 14.6.0, FriBidi 1.0.17, dav1d 1.5.4 and zlib 1.3.2,
  each a release tarball by SHA-256 or a git tag checked against its commit; ANGLE's EGL and GLES headers at a pinned
  commit, the last before it dropped the D3D9 names media_kit_video uses.
* **Configure LGPL only**: FFmpeg with `--disable-autodetect`, its native decoders, demuxers, parsers and filters (`v360`
  for ADR-0146, `http` for the loopback proxy), dav1d for AV1, zlib, D3D11VA and DXVA2, Schannel; no programs, no
  avdevice, not the C++/WinRT `gfxcapture` filter; libmpv alone, `-Dgpl=false`, with win32 threads, WASAPI, D3D11VA and
  the OpenGL render API. FFmpeg ships as its own DLLs, dynamically linked (ADR-0013); the rest, with the C++ runtime
  libplacebo needs, is linked into `libmpv-2.dll`, so the app ships no toolchain DLL (the script fails if one is
  imported). `tools/video/lgpl_check.py` is ADR-0013's licence check on the output: every FFmpeg DLL says "LGPL
  version 2.1 or later" and was configured without `--enable-gpl` or `--enable-nonfree`, and libmpv's feature list holds
  no `gpl`.
* **Build reproducibly**: no build path (`-ffile-prefix-map`, mpv's record of the meson command), no timestamp
  (`--no-insert-timestamp`, `SOURCE_DATE_EPOCH`, `-Dbuild-date=false`), a sorted tar and single-threaded xz. The
  script writes `app/build/libmpv/<archive>` and records the archive's SHA-256, each file's and the toolchain in
  `app/windows/libmpv.json`; `--check` rebuilds and fails on any difference.
* **Take it by hash**: `app/windows/libmpv.cmake` takes the archive from `app/build/libmpv/`, else downloads it from the
  release `libmpv-windows-<first 12 hex digits>` of this repository, refuses it unless it has the pinned SHA-256,
  extracts it where media_kit_video looks and sets `MEDIA_KIT_LIBS_AVAILABLE`; without it the Windows build fails,
  naming the script. Its DLLs and `libmpv-notices.txt` install beside `photolib.exe`, and so into the MSIX.
* **Render in software, without ANGLE**: ANGLE has no build of ours (Chromium's toolchain and the Windows SDK), so
  `mpvVideoConfiguration` turns media_kit_video's hardware path off on Windows, as Linux runs under Impeller. The
  archive's ANGLE import libraries, of the functions media_kit_video calls, are delay-loaded and never called.
  Decoding still uses the GPU (D3D11VA, copied back).
* **List the notices**: `libmpv-notices.txt`, in Flutter's NOTICES format, names each bundled library, its licence and
  the source it was built from, with the licence's text; on Windows `MpvPlayers.register` adds it to the app's licences.
* **Prepare, not publish**: the owner runs the script, checks the hash against `libmpv.json` and uploads the archive to
  that release. A new pin means a new build, archive name or hash, and release.

## Consequences

* Windows plays what Linux plays, with the same FFmpeg release; the probe of ADR-0112 runs there by hand.
* Until the release is published, a Windows build needs the archive copied into `app/build/libmpv/`.
* Software rendering costs CPU on large videos; a hardware path needs ANGLE built from source (a later item).
* Windows on Arm gets no libmpv yet; llvm-mingw can build it with an `aarch64` target.
* Upgrading libmpv or FFmpeg is a change to the script's pins, a rebuild and a new release.

## Options considered

* **media_kit_libs_windows_video**: a 2023 libmpv of unknown configuration and a prebuilt ANGLE, checked by MD5.
* **Build on Windows with MSYS2**: its packages move every day, so a build cannot be pinned or repeated.
* **A Docker image with Debian's mingw-w64**: needs a Docker daemon, which the machines running the gate lack.
* **FFmpeg linked into `libmpv-2.dll`**, as media_kit's builds do: ADR-0013 asks for FFmpeg dynamically linked.
* **Build ANGLE too**: Chromium's gn toolchain and the Windows SDK, hours per build; left for a later item.
* **A workflow**: Actions minutes are off; the script is what a release-only workflow would run.
