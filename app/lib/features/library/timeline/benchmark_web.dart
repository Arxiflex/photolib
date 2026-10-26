import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'thumbnails.dart';

@JS()
external JSPromise<JSAny> createImageBitmap(JSAny image, JSAny options);

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external _Blob(JSArray<JSAny> parts);
}

/// The browser's decoders: `createImageBitmap` decodes and resizes off the
/// main thread in every engine, and Flutter takes the bitmap as a texture.
Future<(Map<String, ThumbnailSource>, Future<void> Function())> platformSources(
  List<Uint8List> jpegs,
) async => (
  {
    'bitmap': (Object asset, int tier, Tile _) async {
      final bitmap = await createImageBitmap(
        _Blob([jpegs[(asset as int) % jpegs.length].toJS].toJS),
        {
          'resizeWidth': tier,
          'resizeHeight': tier,
          'resizeQuality': 'medium',
        }.jsify()!,
      ).toDart;
      return ui_web.createImageFromImageBitmap(bitmap);
    },
  },
  () async {},
);
