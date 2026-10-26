import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// [player]'s 360° video through the sphere shader, its frames shown by
/// [frame] (ADR-0146): its view, the browser's `<video>` element
/// (BrowserPlayers), kept out of sight under them, each frame copied at its
/// picture's size as the element presents it.
Widget sphereVideo(
  VideoPlayerController player,
  Sphere sphere,
  ValueNotifier<SphereView> view,
  Widget Function(ui.Image? image, Widget? over) frame,
) => _VideoFrames(player, (image) => frame(image, null));

class _VideoFrames extends StatefulWidget {
  const new(this.player, this.builder);

  final VideoPlayerController player;
  final Widget Function(ui.Image? frame) builder;

  @override
  State<_VideoFrames> createState() => _VideoFramesState();
}

class _VideoFramesState extends State<_VideoFrames> {
  web.HTMLVideoElement? _video;
  ui.Image? _frame;
  final _events = <StreamSubscription<web.Event>>[];

  @override
  void dispose() {
    for (final e in _events) {
      unawaited(e.cancel());
    }
    _video = null;
    _frame?.dispose();
    super.dispose();
  }

  void _created(Object element) {
    if (!(element as JSObject).isA<web.HTMLVideoElement>()) return;
    final video = element as web.HTMLVideoElement;
    if (_video == video) return;
    _video = video;
    // Paused, its first frame and a seek's present no frame callback.
    for (final event in [
      web.EventStreamProviders.loadedDataEvent,
      web.EventStreamProviders.seekedEvent,
    ]) {
      _events.add(event.forTarget(video).listen((_) => _copy(video)));
    }
    _watch(video);
    unawaited(_copy(video));
  }

  void _watch(web.HTMLVideoElement video) => video.requestVideoFrameCallback(
    (JSNumber _, JSObject _) {
      if (_video != video) return;
      _watch(video);
      unawaited(_copy(video));
    }.toJS,
  );

  Future<void> _copy(web.HTMLVideoElement video) async {
    // Until it has a frame (HAVE_CURRENT_DATA), and not while it seeks.
    if (video.readyState < 2 || video.seeking) return;
    final ui.Image frame;
    try {
      frame = await ui_web.createImageFromTextureSource(
        video,
        width: video.videoWidth,
        height: video.videoHeight,
      );
    } on Object {
      return; // A seek began: its end copies again.
    }
    if (!mounted || _video != video) return frame.dispose();
    setState(() {
      _frame?.dispose();
      _frame = frame;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // i18n-ok: out of sight in a corner, whichever
      Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: SphereProjection(
          onElement: _created,
          child: VideoPlayer(widget.player),
        ),
      ),
      widget.builder(_frame),
    ],
  );
}
