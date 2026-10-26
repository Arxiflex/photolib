// root-isolate-ok: the decoders run in the data isolate, libvips on
// isolates of its own.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/features/library/timeline/vips.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart' show Server;
import 'package:photolib_data/ml.dart';
import 'package:photolib_data/ml.dart'
    as photolib_ml
    show startFaces, stopFaces;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_ml/registry.dart';
import 'package:photolib_ml/runner.dart';

/// On-device ML's channel: the phones' decoders and background tasks
/// (MlChannel.kt, MlChannel.swift).
const mlChannel = MethodChannel('org.photolib/ml');

/// The platform's text recognition on [mlChannel] (`recognize`, `textSupport`)
/// is MlChannel.kt's ML Kit, MlChannel.swift's Vision.

/// The thumb_m rendition's short side, what the indexer reads (design 09
/// §2.2).
const _size = 720;

/// The short side of the picture on-device OCR reads: PP-OCR's detector
/// shrinks anything whose long side is over 1280 pixels.
const _textSize = 1024;

/// This device's host: phones decode through the runners, desktops with
/// libvips; null where nothing decodes.
Future<MlHost?> mlHost() async {
  final (target, phone) = switch (defaultTargetPlatform) {
    TargetPlatform.android => ('android', true),
    TargetPlatform.iOS => ('ios', true),
    TargetPlatform.macOS => ('macos', false),
    TargetPlatform.windows => ('windows', false),
    TargetPlatform.linux => ('linux', false),
    TargetPlatform.fuchsia => ('', false),
  };
  final Decode decode;
  Decode? text;
  (Recognise, String)? platform;
  final String decoder;
  if (phone) {
    final token = RootIsolateToken.instance;
    if (token == null) return null;
    decode = _channel(token, target == 'ios');
    decoder = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    if (await platformEngine() case final engine?) {
      platform = (platformRecogniser(token, photoKit: target == 'ios'), engine);
    }
  } else if (await vipsLibrary() case (final library, final version)) {
    decode = _vips(library);
    text = _vips(library, _textSize);
    decoder = version;
  } else {
    return null;
  }
  final support = (await getApplicationSupportDirectory()).path;
  return _NativeHost(
    target,
    '$support/models',
    decode,
    decoder,
    phone: phone,
    text: text,
    recognise: platform,
  );
}

/// The engine of the platform's own text recognition, `mlkit` or `vision`;
/// null where the build has none (the libre flavour has no ML Kit).
@visibleForTesting
Future<String?> platformEngine() async {
  try {
    return await mlChannel.invokeMethod<String>('textSupport');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Reads an item's text with the platform's own recognition, in the data
/// isolate; it is given a picture of at most 1024 pixels on its short side.
@visibleForTesting
Recognise platformRecogniser(
  RootIsolateToken token, {
  required bool photoKit,
}) => (item) {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  return mlChannel.invokeMethod<String>('recognize', {
    'source': photoKit ? 'photokit' : 'mediastore',
    'id': item.sourceId,
    'size': _textSize,
  });
};

// Each runs in the data isolate: only what it captures goes there.
Decode _channel(RootIsolateToken token, bool photoKit) => (item) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final pixels = await mlChannel.invokeMapMethod<String, Object?>('decode', {
    'source': photoKit ? 'photokit' : 'mediastore',
    'id': item.sourceId,
    'size': _size,
  });
  if (pixels == null) return null;
  return (
    width: pixels['width']! as int,
    height: pixels['height']! as int,
    rgba: pixels['rgba']! as Uint8List,
  );
};

Decode _vips(String library, [int size = _size]) => (item) {
  final path = '${item.volume}/${item.path}';
  return item.source != 'folder'
      ? Future.value()
      : Isolate.run(() => vipsPixels(library, path, size));
};

class _NativeHost implements MlHost {
  new(
    this.target,
    this._models,
    this._decode,
    this._decoder, {
    required this.phone,
    this.text,
    this.recognise,
  });

  @override
  final String target;
  @override
  final bool phone;
  @override
  bool get platformText => recognise != null;
  final String _models;
  final Decode _decode;
  final String _decoder;

  /// The decoder on-device OCR reads with; null where nothing decodes.
  final Decode? text;

  /// What reads text on a phone, and its engine's name.
  final (Recognise, String)? recognise;

  String _path(RegistryModel model, RegistryFile file) =>
      '$_models/${model.name}/${file.name}';

  @override
  Future<bool> install(
    RegistryModel model,
    RegistryFile file,
    SavedServer? server,
    void Function(int bytes) progress,
  ) async {
    final api = server == null
        ? null
        : Server(server.config, instance: server.instance);
    try {
      await installModel(
        _path(model, file),
        size: file.size,
        sha256: file.sha256,
        // Connected apps get models from their server only (NFR-PRIV-1).
        sources: api == null
            ? [for (final url in file.urls) mirrorModel(Uri.parse(url))]
            : [serverModel(api, model.name, file.name)],
        progress: progress,
      );
      return true;
    } on ModelMissing {
      return false;
    } finally {
      api?.close();
    }
  }

  @override
  void start(
    Replica db,
    RegistryModel model,
    RegistryFile file, {
    required bool backlog,
  }) {
    final (input, shape) = file.input;
    final preprocess =
        model.preprocess ?? (throw StateError('${model.name} takes no image'));
    startMl(
      db,
      MlSetup(
        runtime: null,
        model: RunnerModel(
          name: model.name,
          path: _path(model, file),
          input: input,
          shape: shape,
          output: file.output,
          golden: file.goldenInput,
          reference: file.reference,
          precision: file.precision,
        ),
        input: (
          size: preprocess.size,
          mean: preprocess.mean,
          std: preprocess.std,
          crop: preprocess.crop,
        ),
        decode: _decode,
        decoder: _decoder,
        state: _models,
        backlog: backlog,
        // New captures go in small foreground batches (design 09 §3.4).
        chunk: backlog ? 8 : 2,
      ),
    );
  }

  @override
  void startFaces(
    Replica db, {
    required RegistryModel detector,
    required RegistryFile detectorFile,
    required RegistryModel embedder,
    required RegistryFile embedderFile,
    required bool backlog,
  }) => photolib_ml.startFaces(
    db,
    FacesSetup(
      runtime: null,
      detector: detector,
      detectorPath: _path(detector, detectorFile),
      embedder: embedder,
      embedderPath: _path(embedder, embedderFile),
      target: target,
      decode: _decode,
      decoder: _decoder,
      backlog: backlog,
      chunk: backlog ? 4 : 1,
    ),
  );

  @override
  void stopFaces(Replica db) => photolib_ml.stopFaces(db);

  @override
  void stop(Replica db) => stopMl(db);

  @override
  void startText(
    Replica db,
    List<(RegistryModel, RegistryFile)> models, {
    required bool backlog,
  }) {
    if (recognise case (final read, final engine)) {
      return startOcr(
        db,
        OcrSetup.platform(recognise: read, engine: engine, backlog: backlog),
      );
    }
    final decode = text;
    if (decode == null) return;
    startOcr(
      db,
      OcrSetup(
        runtime: null,
        files: {
          for (final (model, file) in models) model.id: _path(model, file),
        },
        decode: decode,
        decoder: _decoder,
        backlog: backlog,
      ),
    );
  }

  @override
  void stopText(Replica db) => stopOcr(db);

  @override
  void interacted(Replica db) => reportInteraction(db);

  @override
  void hold(Replica db, {required bool held}) => holdMl(db, held: held);

  @override
  Future<void> schedule({required bool on}) async {
    try {
      await (on
          ? mlChannel.invokeMethod<void>('schedule')
          : mlChannel.invokeMethod<void>('cancel'));
    } on MissingPluginException {
      // A runner without the channel, as on the desktops' tests.
    }
  }

  @override
  void listen({
    required Future<bool> Function() background,
    required void Function() stop,
  }) => mlChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'background':
        return {'more': await background()};
      case 'stop':
        stop();
    }
    return null;
  });
}
