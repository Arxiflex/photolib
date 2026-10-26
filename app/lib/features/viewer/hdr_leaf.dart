import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib_data/photolib_data.dart' show LocalAssetData;

import 'hdr_display.dart' if (dart.library.js_interop) 'hdr_display_web.dart';

/// What the native HDR leaf can do here: `none` below Android 14, iOS 17 and
/// macOS 14 and on every other platform, `sdr` on a display without headroom.
enum HdrSupport { none, sdr, hdr }

const _viewType = 'photolib/hdr';
const _raise = Duration(milliseconds: 200);

/// Whether this platform has an HDR leaf; Windows and Linux show HDR items in
/// SDR (docs/10 §4.5). The web has one, an `<img>` of the file, where the
/// browser's display has HDR headroom: stills only, as a browser plays an HDR
/// video in HDR itself (ADR-0390).
bool get hdrLeaves =>
    kIsWeb ||
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

/// Whether a device index row is of an HDR item (`hdr` among its facets).
bool isHdr(LocalAssetData? row) =>
    (row?.facets ?? '').split(',').contains('hdr');

Future<HdrSupport> hdrSupport() async {
  if (kIsWeb) return browserShowsHdr ? HdrSupport.hdr : HdrSupport.none;
  try {
    final name = await const MethodChannel(_viewType)
        .invokeMethod<String>('support');
    return HdrSupport.values.byName(name ?? 'none');
  } on MissingPluginException {
    return HdrSupport.none;
  }
}

/// A full-screen HDR still or video in a native leaf view (docs/10 §4.5,
/// ADR-0060), while it is to [show]. The Flutter-drawn [sdr] frame stays on
/// top until the native view has rendered, then cross-fades out; it stays for
/// good where there is no HDR leaf, and comes back at once when hidden.
/// Flutter keeps every gesture: the native view only follows the transforms
/// and clips the engine applies to it.
class HdrLeaf extends StatefulWidget {
  const HdrLeaf({
    super.key,
    required this.uri,
    required this.sdr,
    this.show = true,
    this.video = false,
    this.force = false,
  });

  /// The dwell before the native view is created, so a fling past an item
  /// creates nothing.
  static const prewarm = Duration(milliseconds: 150);

  /// The item's file, MediaStore item or PhotoKit asset.
  final Uri uri;
  final Widget sdr;
  final bool show;
  final bool video;

  /// Uses the native view on an SDR display too, as the probe does to measure
  /// it on emulators and CI machines.
  final bool force;

  @override
  State<HdrLeaf> createState() => _HdrLeafState();
}

class _HdrLeafState extends State<HdrLeaf> {
  Timer? _prewarm;
  bool _native = false;
  bool _hcpp = false;
  bool _rendered = false;
  MethodChannel? _channel;

  @override
  void initState() {
    super.initState();
    _shown();
  }

  @override
  void didUpdateWidget(HdrLeaf old) {
    super.didUpdateWidget(old);
    if (widget.show != old.show) _shown();
  }

  void _shown() {
    _prewarm?.cancel();
    if (widget.show) {
      _prewarm = Timer(HdrLeaf.prewarm, _start);
    } else {
      // A view dropped says nothing more.
      _channel?.setMethodCallHandler(null);
      _native = _rendered = false;
    }
  }

  Future<void> _start() async {
    final support = await hdrSupport();
    if (support == HdrSupport.hdr ||
        (widget.force && support == HdrSupport.sdr)) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _hcpp = await HybridAndroidViewController.checkIfSupported();
      }
      if (mounted && widget.show) setState(() => _native = true);
    }
  }

  /// The web's `<img>` has loaded, or cannot show the file.
  void _loaded({required bool shown}) {
    if (!mounted || !widget.show) return;
    setState(() {
      _rendered = shown;
      _native = shown;
    });
  }

  void _attach(int id) {
    _channel = MethodChannel('$_viewType/$id')
      ..setMethodCallHandler((call) async {
        if (!mounted) return;
        setState(() {
          _rendered = call.method == 'rendered';
          _native = _rendered;
        });
      });
  }

  @override
  void dispose() {
    _prewarm?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_native) ExcludeSemantics(child: _view(context)),
      AnimatedOpacity(
        opacity: _rendered ? 0 : 1,
        // The SDR frame first, the headroom raised over 200 ms (docs/10 §4.6).
        duration: _rendered ? Motion.of(context, _raise) : Duration.zero,
        curve: Motion.curve,
        alwaysIncludeSemantics: true,
        child: widget.sdr,
      ),
    ],
  );

  Widget _view(BuildContext context) {
    if (kIsWeb) return browserHdrView(widget.uri, _loaded);
    final params = {'uri': '${widget.uri}', 'video': widget.video};
    const codec = StandardMessageCodec();
    const transparent = PlatformViewHitTestBehavior.transparent;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: transparent,
        ),
        onCreatePlatformView: (link) =>
            (_hcpp
                  ? PlatformViewsService.initHybridAndroidView
                  : PlatformViewsService.initExpensiveAndroidView)(
                id: link.id,
                viewType: _viewType,
                layoutDirection: Directionality.of(context),
                creationParams: params,
                creationParamsCodec: codec,
              )
              ..addOnPlatformViewCreatedListener(link.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(_attach)
              ..create(),
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: _viewType,
        creationParams: params,
        creationParamsCodec: codec,
        onPlatformViewCreated: _attach,
        hitTestBehavior: transparent,
      ),
      _ => AppKitView(
        viewType: _viewType,
        creationParams: params,
        creationParamsCodec: codec,
        onPlatformViewCreated: _attach,
        hitTestBehavior: transparent,
      ),
    };
  }
}
