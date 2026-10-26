#!/usr/bin/env bash
# ONNX Runtime for Android reduced to the operators of the models devices run (ADR-0050: the full library takes 13 MB
# of a 30 MB per-ABI APK budget), built from source outside the gate:
#
#   bash tools/ml/ort_android.sh
#
# Builds ONNX Runtime 1.31.0 for arm64-v8a, armeabi-v7a and x86_64 with only tools/ml/ort-ops.config's operators
# (python3 tools/ml/ort_ops.py writes it), XNNPACK, the smallest configuration and 16 KB pages, then prints each
# library's ABI, path, bytes and SHA-256 for pinning. Needs git, Python 3, CMake, Ninja, a JDK and the Android SDK and
# NDK (ANDROID_HOME, ANDROID_NDK_HOME), and hours, so the gate never runs it. Until a library it built is pinned, the
# app bundles the official AAR's (app/packages/photolib_ml/hook/build.dart); pin one only once every device model
# passes its golden check through photolib_ml's Runner with it, as ONNX Runtime's graph optimisations may fuse nodes
# into operators the models do not name.
set -euo pipefail

version=1.31.0
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=${ORT_WORK:-${TMPDIR:-/tmp}/photolib-ort-android-$version}
: "${ANDROID_HOME:?the Android SDK}" "${ANDROID_NDK_HOME:?the Android NDK}"

python3 "$root/tools/ml/ort_ops.py" --check
[[ -d $work/onnxruntime ]] || git clone --quiet --depth 1 --branch "v$version" --recurse-submodules \
  --shallow-submodules https://github.com/microsoft/onnxruntime "$work/onnxruntime"
for abi in arm64-v8a armeabi-v7a x86_64; do
  python3 "$work/onnxruntime/tools/ci_build/build.py" --build_dir "$work/build/$abi" --config MinSizeRel --parallel \
    --android --android_abi "$abi" --android_api 24 --android_sdk_path "$ANDROID_HOME" \
    --android_ndk_path "$ANDROID_NDK_HOME" --cmake_generator Ninja --build_shared_lib --use_xnnpack \
    --include_ops_by_config "$root/tools/ml/ort-ops.config" --disable_ml_ops --disable_rtti --enable_lto --skip_tests \
    --cmake_extra_defines CMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384
  library=$work/build/$abi/MinSizeRel/libonnxruntime.so
  python3 "$root/tools/page_size.py" "$library" >&2
  echo "$abi $library $(wc -c <"$library") $(sha256sum "$library" | cut -d' ' -f1)"
done
