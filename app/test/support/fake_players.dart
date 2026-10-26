import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Players that play nothing: each says it is a [duration] video of
/// 1920 × 1080 with a sound track, but none when its URI ends with one of
/// [silent], or fails to open when it ends with one of [failing]; what the app
/// asks of them is in [calls], as `play 0` for player 0, whether each was
/// made to play over other audio in [mixes], and how each is viewed in
/// [viewTypes].
class FakePlayers extends VideoPlayerPlatform {
  new({
    this.failing = const {},
    this.silent = const {},
    this.duration = const Duration(seconds: 3),
  });

  final Set<String> failing;
  final Set<String> silent;
  final Duration duration;
  final calls = <String>[];
  final uris = <String>[];
  final mixes = <bool?>[];
  final viewTypes = <VideoViewType>[];
  final _events = <int, StreamController<VideoEvent>>{};
  final _positions = <int, Duration>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = uris.length;
    final uri = options.dataSource.uri!;
    uris.add(uri);
    mixes.add(options.videoPlayerOptions?.mixWithOthers);
    viewTypes.add(options.viewType);
    // Whose cancel, which a player's disposal awaits, ends in the test's
    // time rather than the root zone's.
    final events = _events[id] = StreamController<VideoEvent>(
      onCancel: Future<void>.value,
    );
    if (failing.any(uri.endsWith)) {
      events.addError(
        PlatformException(code: 'decoder', message: 'no decoder'),
      );
    } else {
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(1920, 1080),
          duration: duration,
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  /// Fails player [id] as a decoder that breaks while it plays does.
  void fail(int id) => _events[id]!.addError(
    PlatformException(code: 'decoder', message: 'decode error'),
  );

  /// Ends player [id]'s video, as a platform says it played to its end.
  void complete(int id) =>
      _events[id]!.add(VideoEvent(eventType: VideoEventType.completed));

  void _say(int id, bool playing) => _events[id]!.add(
    VideoEvent(
      eventType: VideoEventType.isPlayingStateUpdate,
      isPlaying: playing,
    ),
  );

  @override
  Future<void> play(int playerId) async {
    calls.add('play $playerId');
    _say(playerId, true);
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause $playerId');
    _say(playerId, false);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seek $playerId ${position.inMilliseconds}');
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('volume $playerId $volume');

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      calls.add('loop $playerId $looping');

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      calls.add('speed $playerId $speed');

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async =>
      calls.add('mix $mixWithOthers');

  @override
  bool isAudioTrackSupportAvailable() => true;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async => [
    if (!silent.any(uris[playerId].endsWith))
      const VideoAudioTrack(
        id: '0',
        label: null,
        language: null,
        isSelected: true,
      ),
  ];

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      SizedBox.expand(key: ValueKey('player ${options.playerId}'));

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose $playerId');
    unawaited(_events.remove(playerId)?.close());
  }
}
