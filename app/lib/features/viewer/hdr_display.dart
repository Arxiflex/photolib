import 'package:flutter/widgets.dart';

/// Whether the browser shows HDR: never off the web, where the leaves are
/// native views (`hdr_leaf.dart`).
bool get browserShowsHdr => false;

/// The web's HDR leaf, an `<img>` of the file at [uri]
/// (`hdr_display_web.dart`); nothing here. [loaded] says whether it showed.
Widget browserHdrView(Uri uri, void Function({required bool shown}) loaded) =>
    const SizedBox.shrink();
