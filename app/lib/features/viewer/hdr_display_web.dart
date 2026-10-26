import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:photolib_data/browser.dart';
import 'package:web/web.dart' as web;

/// The views made, which name their factories.
int _made = 0;

/// What a test says the display is, instead of the browser's answer.
@visibleForTesting
bool? debugBrowserShowsHdr;

/// The `<img>` elements being shown, which a test looks at: Flutter's test
/// engine keeps platform views out of the page.
@visibleForTesting
final List<web.HTMLImageElement> debugHdrImages = [];

/// Whether the browser's display has HDR headroom: where Chrome shows a JPEG
/// with a gain map, or a PQ or HLG AVIF, in HDR (docs/10 §4.5).
bool get browserShowsHdr =>
    debugBrowserShowsHdr ??
    web.window.matchMedia('(dynamic-range: high)').matches;

/// The HDR leaf of the web: the file of the folder item at [uri] in an `<img>`
/// of its own, which the browser decodes with its gain map. [loaded] says
/// whether it showed; the picture it cannot decode (a HEIC in Chrome) stays
/// the SDR frame's.
Widget browserHdrView(Uri uri, void Function({required bool shown}) loaded) =>
    _BrowserHdr(uri, loaded);

class _BrowserHdr extends StatefulWidget {
  const new(this.uri, this.loaded);

  final Uri uri;
  final void Function({required bool shown}) loaded;

  @override
  State<_BrowserHdr> createState() => _BrowserHdrState();
}

class _BrowserHdrState extends State<_BrowserHdr> {
  String? _url;
  late String _type;
  var _gone = false;
  web.HTMLImageElement? _image;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final segments = widget.uri.pathSegments;
    final blob = widget.uri.isScheme('folder') && segments.length > 1
        ? await browserFile(segments.first, segments.skip(1).join('/'))
        : null;
    if (_gone) return;
    if (blob == null) return widget.loaded(shown: false);
    final url = web.URL.createObjectURL(blob);
    final image = web.HTMLImageElement();
    image.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      // Flutter keeps every gesture, as over the native leaves.
      ..pointerEvents = 'none';
    image
      ..onload = ((web.Event _) => widget.loaded(shown: true)).toJS
      ..onerror = ((web.Event _) => widget.loaded(shown: false)).toJS
      ..src = url;
    _image = image;
    debugHdrImages.add(image);
    ui_web.platformViewRegistry.registerViewFactory(
      _type = 'photolib/hdr-img-${_made++}',
      (_) => image,
    );
    setState(() => _url = url);
  }

  @override
  void dispose() {
    _gone = true;
    if (_image case final image?) debugHdrImages.remove(image);
    if (_url case final url?) web.URL.revokeObjectURL(url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _url == null
      ? const SizedBox.shrink()
      : HtmlElementView(
          viewType: _type,
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
}
