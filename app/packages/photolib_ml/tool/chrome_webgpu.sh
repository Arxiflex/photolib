#!/bin/sh
# Chrome with --enable-unsafe-webgpu, without which headless Chrome on Linux has no WebGPU adapter (with it, SwiftShader's,
# a CPU implementation). The gate passes it to web_test.dart as CHROME_EXECUTABLE; $CHROME is the Chrome it runs.
exec "${CHROME:-google-chrome}" --enable-unsafe-webgpu "$@"
