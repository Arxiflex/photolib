import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, StreamProviderFamily;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/link.dart';
import 'package:photolib/features/viewer/hdr_leaf.dart';
import 'package:photolib/features/viewer/info_panel.dart';
import 'package:photolib/features/viewer/mpv.dart'
    if (dart.library.js_interop) 'package:photolib/features/viewer/mpv_web.dart';
import 'package:photolib_data/photolib_data.dart'
    show LocalAssetData, keepFrameRate, watchFrameRate;
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;

export 'package:photolib/features/viewer/video_view.dart';

const _channel = MethodChannel('org.photolib/viewer');

/// A player of [item]'s video, made with [options]: its file, its MediaStore
/// URI, the file PhotoKit keeps of it (ViewerChannel in
/// ThumbnailChannel.swift) or the browser's file of it. An [hdr] one plays in
/// a platform view, which keeps its headroom, on Android and iOS screens that
/// have some (docs/10 §4.5).
Future<VideoPlayerController> videoOf(
  ThumbnailItem item,
  VideoPlayerOptions? options, {
  bool hdr = false,
  Future<Uri> Function(ThumbnailItem item)? server,
  Link? link,
  bool? adaptive,
}) async {
  final viewType =
      hdr &&
          const {
            TargetPlatform.android,
            TargetPlatform.iOS,
          }.contains(defaultTargetPlatform) &&
          await hdrSupport() == HdrSupport.hdr
      ? VideoViewType.platformView
      : VideoViewType.textureView;
  // A server video: the bytes of the offline store or the server's, over
  // loopback (ADR-0200 P1); a browser, which has no loopback server, plays
  // what it keeps and streams the rest from the server's signed URL.
  if (item.renditions != null && server != null) {
    final kept = await _keptUrl(item, server);
    if (kept != null) {
      return VideoPlayerController.networkUrl(
        kept,
        videoPlayerOptions: options,
        viewType: viewType,
      );
    }
    // A browser that streams HLS, with its own player (Safari) or hls.js, plays
    // the server's ladder (ADR-0246), another its H.264 proxy.
    final hls = adaptive ?? streamsHls;
    final signed = await (link ?? (throw StateError('not signed in'))).sign(
      '${item.uri.path}/${hls ? 'hls' : 'video_proxy_720'}',
    );
    return VideoPlayerController.networkUrl(
      signed,
      formatHint: hls ? VideoFormat.hls : null,
      videoPlayerOptions: options,
      viewType: viewType,
    );
  }
  return switch (item.uri.scheme) {
    'content' => VideoPlayerController.contentUri(
      item.uri,
      videoPlayerOptions: options,
      viewType: viewType,
    ),
    'folder' => await folderVideo(item),
    'ph' => VideoPlayerController.file(
      File(
        await _channel.invokeMethod<String>('video', ['${item.uri}']) ??
            (throw StateError('PhotoKit has no file of ${item.uri}')),
      ),
      videoPlayerOptions: options,
      viewType: viewType,
    ),
    _ => VideoPlayerController.file(
      File(item.uri.toFilePath()),
      videoPlayerOptions: options,
      viewType: viewType,
    ),
  };
}

/// The URL [server] gives for [item]'s kept or loopback video, or null where
/// this is a browser that keeps no such file.
Future<Uri?> _keptUrl(
  ThumbnailItem item,
  Future<Uri> Function(ThumbnailItem item) server,
) async {
  try {
    return await server(item);
    // The browser's proxy says so with this error when it holds no such file.
    // ignore: avoid_catching_errors
  } on UnsupportedError {
    return null;
  }
}

/// Where each video was left in this session, which [VideoPlayers] start it
/// at again while the user wants it to resume.
final Provider<Map<String, Duration>> videoPositionsProvider = Provider(
  (ref) => {},
);

/// The captions beside [item]'s video (I18N-15), in a file of its name with
/// `.vtt` or `.srt`; null when it has none.
Future<ClosedCaptionFile?> captionsOf(ThumbnailItem item) async {
  if (!item.video) return null;
  for (final type in ['vtt', 'VTT', 'srt', 'SRT']) {
    if (await bytesOf(item, extension: type) case final bytes?) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return type.toLowerCase() == 'vtt'
          ? WebVTTCaptionFile(text)
          : SubRipCaptionFile(text);
    }
  }
  return null;
}

/// [captionsOf] an item.
final FutureProviderFamily<ClosedCaptionFile?, ThumbnailItem> captionsProvider =
    FutureProvider.autoDispose.family((ref, item) => captionsOf(item));

/// An item's frames a second, which a frame step moves by: its file's, else
/// its server asset's; a PhotoKit video's, which extraction never reads,
/// AVAsset's nominal rate (ThumbnailChannel.swift's ViewerChannel), kept in
/// its row.
final StreamProviderFamily<double?, ThumbnailItem> frameRateProvider =
    StreamProvider.autoDispose.family((ref, item) async* {
      final id = item.id;
      if (id == null || !item.video) {
        yield null;
        return;
      }
      final db = await ref.watch(replicaProvider.future);
      await for (final rate in watchFrameRate(db, id)) {
        if (rate == null && item.uri.isScheme('ph') && _asking.add(item.key)) {
          unawaited(
            _channel
                .invokeMethod<double>('frameRate', ['${item.uri}'])
                .then(
                  (r) => r == null || r <= 0 ? null : keepFrameRate(db, id, r),
                )
                .whenComplete(() => _asking.remove(item.key)),
          );
        }
        yield rate;
      }
    });

// The PhotoKit videos whose frame rates are being asked.
final _asking = <String>{};

/// The app's cache directory.
final FutureProvider<Directory> cacheDirectoryProvider = FutureProvider(
  (ref) => getApplicationCacheDirectory(),
);

/// The clips the viewer keeps, newest first, up to this many bytes in all.
const int motionCacheBytes = 128 << 20;

/// The video of an item's motion photo or Live Photo as a file of its own, or
/// null for any other item (docs/10 §4.3): the bytes where extraction found it
/// in the file, or a Live Photo's paired video from PhotoKit, kept in the
/// cache's `motion` directory, which holds [motionCacheBytes] at most.
final FutureProviderFamily<File?, ThumbnailItem> motionClipProvider =
    FutureProvider.autoDispose.family<File?, ThumbnailItem>((ref, item) async {
      final row = await ref.watch(assetRowProvider(item).future);
      final live =
          item.uri.isScheme('ph') &&
          (row?.facets ?? '').split(',').contains('live');
      final span = switch ((row?.motionOffset, row?.motionLength)) {
        (final int offset, final int length) => (offset, length),
        _ => null,
      };
      if (row == null || !live && span == null) return null;
      final dir = Directory(
        '${(await ref.watch(cacheDirectoryProvider.future)).path}/motion',
      );
      final clip = File('${dir.path}/${item.key}.${live ? 'mov' : 'mp4'}');
      // The root isolate does no synchronous I/O (tool/root_isolate_lint.dart).
      // ignore: avoid_slow_async_io
      if (await clip.exists()) {
        await clip.setLastModified(DateTime.now());
        return clip;
      }
      await dir.create(recursive: true);
      final part = File('${clip.path}.part');
      if (live) {
        final made = await _channel.invokeMethod<String>('pairedVideo', [
          '${item.uri}',
          part.path,
        ]);
        if (made == null) return null;
      } else if (span case (final offset, final length)) {
        final file = await File(await _pathOf(ref, item, row)).open();
        try {
          await file.setPosition(offset);
          await part.writeAsBytes(await file.read(length));
        } finally {
          await file.close();
        }
      }
      await part.rename(clip.path);
      await keepNewest(dir, motionCacheBytes);
      return clip;
    });

/// Where [row]'s file is: a folder's, or MediaStore's under its volume's root.
Future<String> _pathOf(Ref ref, ThumbnailItem item, LocalAssetData row) async {
  if (item.uri.isScheme('file')) return item.uri.toFilePath();
  final db = await ref.read(replicaProvider.future);
  final cursor =
      await (db.select(db.volumeCursor)
            ..where((c) => c.source.equals(row.source))
            ..where((c) => c.volume.equals(row.volume)))
          .getSingle();
  final root =
      cursor.root ?? (throw StateError('volume ${row.volume} has no root'));
  return '${root.endsWith('/') ? root : '$root/'}${row.path}${row.name}';
}

/// Deletes the oldest files of [dir] beyond the newest [bytes].
Future<void> keepNewest(Directory dir, int bytes) async {
  final clips = [
    for (final f in await dir.list().toList())
      // The root isolate does no synchronous I/O (tool/root_isolate_lint.dart).
      // ignore: avoid_slow_async_io
      if (f is File) (f, await f.stat()),
  ]..sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
  var kept = 0;
  for (final (file, stat) in clips) {
    kept += stat.size;
    // deletion-ok: a motion clip the cache copied out of its photo
    if (kept > bytes) await file.delete();
  }
}

/// A position to the millisecond, as `1:02.345` or `1:02:03.456`.
String clock(Duration d) {
  final ms = d.inMilliseconds;
  String two(int n) => '$n'.padLeft(2, '0');
  final (h, m, s) = (ms ~/ 3600000, ms ~/ 60000 % 60, ms ~/ 1000 % 60);
  final frac = '${ms % 1000}'.padLeft(3, '0');
  return '${h > 0 ? '$h:${two(m)}' : m}:${two(s)}.$frac';
}

/// Makes a player of a video, with [options] when given.
typedef PlayerOf = Future<VideoPlayerController> Function(
  VideoPlayerOptions? options,
);

/// Whether each player [VideoPlayers] made plays over other apps' audio.
final _mixes = Expando<bool>('mix');

/// Whether [player]'s video has a sound track, or its platform cannot tell
/// (libmpv, browsers), where audio always mixes.
Future<bool> _audible(VideoPlayerController player) async =>
    !player.isAudioTrackSupportAvailable() ||
    (await player.getAudioTracks()).isNotEmpty;

/// The viewer's players (docs/10 §4.2): made, played, paused, rewound and
/// disposed one at a time, and only while [still], so that neither the
/// viewer's opening nor a swipe waits on one. Those [want]ed are made in
/// order; one no longer wanted is disposed once its view has let it go.
/// Listeners hear when a player is ready, fails or goes.
class VideoPlayers extends ChangeNotifier {
  /// Whether the players made from now on loop.
  bool loop = false;

  /// Whether the players made from now on play over other apps' audio even
  /// with a sound track of their own; a silent video always does.
  bool mixAudio = false;

  /// Where each video was left, while set: one left is kept there rather
  /// than rewound, and a new player of it starts there.
  Map<String, Duration>? positions;

  /// Called when the video playing plays to its end; the next video then
  /// plays as it is shown.
  VoidCallback? onEnded;

  /// Whether the video to play starts as it is shown, rather than paused on
  /// its first frame until [toggle]d (docs/10 §4.6).
  bool autoplay = false;

  final _made = <String, VideoPlayerController>{};
  final _failed = <String>{};
  final _rewind = <String>{};
  // The videos to start once made: asked to play before, or after one ended.
  final _start = <String>{};
  var _carry = false;
  var _wanted = <String, PlayerOf>{};
  String? _play;
  String? _playing;
  var _still = false;
  var _busy = false;
  var _disposed = false;

  /// The player of [key] once it has its first frame and knows its audio.
  VideoPlayerController? operator [](String key) => switch (_made[key]) {
    final player? when _mixes[player] != null => player,
    _ => null,
  };

  /// Whether the player of [key] could not open or play.
  bool failed(String key) => _failed.contains(key);

  /// Keeps the players [wanted] opens and plays [play]'s alone.
  void want(Map<String, PlayerOf> wanted, String? play) {
    _wanted = wanted;
    if (play != _play) {
      if (_carry && play != null) _start.add(play);
      _carry = false;
    }
    _play = play;
    unawaited(_run());
  }

  /// Plays [key]'s video, or pauses it while it plays; one not yet made
  /// starts once it is.
  void toggle(String key) {
    switch (this[key]) {
      case final player? when player.value.isPlaying:
        unawaited(player.pause());
      case final player? when key == _playing:
        unawaited(player.start());
      case _:
        _start.add(key);
        unawaited(_run());
    }
  }

  /// Whether nothing moves: the viewer has opened and its pages rest.
  bool get still => _still;
  set still(bool still) {
    _still = still;
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_busy) return;
    _busy = true;
    // Never within the caller's frame.
    await Future<void>.value();
    while (_still && !_disposed) {
      final step = _next();
      if (step == null) break;
      try {
        await step();
      } on Object {
        // The player says so on its view.
      }
    }
    _busy = false;
  }

  /// Pauses the video played before, plays the one to play, rewinds the
  /// first, disposes those no longer wanted, then makes the next wanted.
  Future<void> Function()? _next() {
    final (play, playing) = (_play, _playing);
    if (playing != null && playing != play) {
      return () async {
        _playing = null;
        final player = _made[playing];
        if (positions == null) _rewind.add(playing);
        await player?.pause();
        if (player != null) positions?[playing] = player.value.position;
      };
    }
    if (play != null && playing == null && !_failed.contains(play)) {
      if (!_made.containsKey(play)) return () => _make(play, _wanted[play]!);
      return () async {
        _playing = play;
        _rewind.remove(play);
        if (_start.remove(play) || autoplay) await _made[play]!.start();
      };
    }
    if (_rewind.isNotEmpty) {
      final key = _rewind.first;
      return () async {
        _rewind.remove(key);
        await _made[key]?.seekTo(Duration.zero);
      };
    }
    for (final key in _made.keys) {
      if (!_wanted.containsKey(key)) {
        return () async {
          final player = _made.remove(key);
          notifyListeners();
          await SchedulerBinding.instance.endOfFrame;
          await player?.dispose();
        };
      }
    }
    for (final MapEntry(:key, value: open) in _wanted.entries) {
      if (!_made.containsKey(key) && !_failed.contains(key)) {
        return () => _make(key, open);
      }
    }
    return null;
  }

  Future<void> _make(String key, PlayerOf open) async {
    VideoPlayerController? player;
    Future<VideoPlayerController> start(VideoPlayerOptions? options) async {
      final made = player = await open(options);
      if (_disposed) throw StateError('the viewer closed');
      _made[key] = made;
      var ended = false;
      made.addListener(() {
        // A decoder can fail at any time after it opened.
        if (made.value.hasError && !_disposed && _failed.add(key)) {
          notifyListeners();
        }
        if (made.value.isCompleted == ended) return;
        ended = made.value.isCompleted;
        if (ended && key == _playing) {
          positions?.remove(key);
          _carry = onEnded != null;
          onEnded?.call();
        }
      });
      await made.initialize();
      return made;
    }

    try {
      // Android's player takes audio focus, or not, as it was made to; iOS's
      // audio session is the app's, which [VideoControls.start] sets.
      final fixed = defaultTargetPlatform == TargetPlatform.android;
      var made = await start(
        fixed ? VideoPlayerOptions(mixWithOthers: mixAudio) : null,
      );
      final mix = mixAudio || !await _audible(made);
      if (fixed && mix != mixAudio) {
        await made.dispose();
        made = await start(VideoPlayerOptions(mixWithOthers: mix));
      }
      _mixes[made] = mix;
      await made.setLooping(loop);
      if (positions?[key] case final at?) await made.seekTo(at);
    } on Object {
      _failed.add(key);
      _made.remove(key);
      await player?.dispose();
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final player in _made.values) {
      unawaited(player.dispose());
    }
    super.dispose();
  }
}

/// What the viewer's controls and keys do to a video's player.
extension VideoControls on VideoPlayerController {
  /// Plays, setting the app's audio session (iOS's) to pause other apps'
  /// audio or play over it as [VideoPlayers] found this video wants.
  Future<void> start() async {
    if (_mixes[this] case final mix?) {
      await VideoPlayerPlatform.instance.setMixWithOthers(mix);
    }
    await play();
  }

  /// Plays a paused video and pauses a playing one.
  void playPause() => unawaited(value.isPlaying ? pause() : play());

  /// Pauses and moves [frames] frames on, or back when negative, at [rate]
  /// frames a second, or 30 when the rate is unknown.
  void step(int frames, double? rate) {
    unawaited(pause());
    final frame = Duration(microseconds: (1e6 / (rate ?? 30)).round());
    unawaited(seekTo(value.position + frame * frames));
  }

  /// Mutes a video with sound and unmutes a muted one.
  void mute() => unawaited(setVolume(value.volume > 0 ? 0 : 1));

  /// Turns looping on or off.
  void loop() => unawaited(setLooping(!value.isLooping));
}
