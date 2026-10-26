import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The bundle [name] as the browser's download.
Future<bool> saveBundle(String name, Uint8List bytes) async {
  final url = web.URL.createObjectURL(
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/zip')),
  );
  (web.HTMLAnchorElement()
        ..href = url
        ..download = name)
      .click();
  // Revoked once the download surely started.
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return true;
}
