// The shaders against the kernel's WebAssembly build in Chrome: `flutter test --platform chrome [--wasm]
// test/web_test.dart` (CanvasKit with dartdevc, Skwasm with dart2wasm; the `web` part of tools/check.sh). Browsers
// export up to ~50 MP (design 11 §4.5).
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_editor/photolib_editor.dart';
import 'package:photolib_editor/testing.dart';
import 'package:photolib_kernel/photolib_kernel_web.dart';

import 'probe.dart';

/// The JavaScript heap and the renderer's WebAssembly memory, which only grows; GPU memory is not visible.
int memory() {
  var total = 0;
  for (final path in [
    'performance.memory.usedJSHeapSize',
    'flutterCanvasKit.HEAPU8.byteLength',
    '_flutter_skwasmInstance.exports.memory.buffer.byteLength',
  ]) {
    JSAny? value = globalContext;
    for (final key in path.split('.')) {
      value = value.isA<JSObject>() ? (value as JSObject)[key] : null;
    }
    total += value.isA<JSNumber>()
        ? (value as JSNumber).toDartDouble.toInt()
        : 0;
  }
  return total;
}

void main() {
  probe(() async {
    final module =
        await spawnHybridUri('web_assets.dart').stream.first as String;
    return (
      await ShaderRenderer.load(assets: ''),
      Reference((await Kernel.load(Uri.base.resolve(module))).call),
    );
  }, memory);
}
