import 'dart:typed_data';
import 'dart:ui' as ui;

/// Natively Flutter's codecs decode encoded tiles: no browser to ask.
Future<ui.Image>? browserImage(Uint8List encoded, int tier) => null;
