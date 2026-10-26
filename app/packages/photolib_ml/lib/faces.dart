/// Faces on the device (design 09 §7, ADR-0389): YuNet and SFace (or
/// AuraFace) on an isolate of their own, each checked against the registry's
/// golden output on ONNX Runtime's CPU before it runs. The kernel makes their
/// inputs and reads their outputs, as on the server.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/registry.dart';
import 'package:photolib_ml/runner.dart' show cosine;

/// YuNet's outputs, in the order the kernel's DecodeFaces reads them.
const yunetOutputs = [
  'cls_8',
  'cls_16',
  'cls_32',
  'obj_8',
  'obj_16',
  'obj_32',
  'bbox_8',
  'bbox_16',
  'bbox_32',
  'kps_8',
  'kps_16',
  'kps_32',
];

/// At most 1,024 evenly spaced values of [outputs], one after another: what a
/// golden keeps of them.
Float32List goldenSample(List<Float32List> outputs) {
  final all = [for (final o in outputs) ...o];
  final n = all.length < 1024 ? all.length : 1024;
  return Float32List.fromList([
    for (var i = 0; i < n; i++) all[i * all.length ~/ n],
  ]);
}

/// A detector and an embedder, on one isolate.
class FaceRunner {
  new _(this._port) {
    _port.listen(_receive);
  }

  /// Loads [detector] from [detectorPath] and [embedder] from [embedderPath]
  /// with the ONNX Runtime library at [runtime] (the bundled one when null),
  /// and fails when either does not reproduce the registry's golden output.
  /// [target] is the registry's name of this platform, such as `linux`.
  static Future<FaceRunner> start(
    String? runtime, {
    required RegistryModel detector,
    required String detectorPath,
    required RegistryModel embedder,
    required String embedderPath,
    required String target,
  }) async {
    final runner = FaceRunner._(ReceivePort());
    final d = detector.files.firstWhere((f) => f.targets.contains(target));
    final e = embedder.files.firstWhere((f) => f.targets.contains(target));
    await Isolate.spawn(_serve, (
      runner._port.sendPort,
      runtime,
      _Model(
        detectorPath,
        d.input.$1,
        d.input.$2,
        d.outputs,
        d.goldenInput,
        d.reference,
      ),
      _Model(
        embedderPath,
        e.input.$1,
        e.input.$2,
        e.outputs,
        e.goldenInput,
        e.reference,
      ),
    ), onExit: runner._port.sendPort);
    await runner._started.future;
    return runner;
  }

  final ReceivePort _port;
  final _started = Completer<void>();
  final _pending = <int, Completer<List<Float32List>>>{};
  SendPort? _requests;
  var _next = 0;

  /// The runtime and the execution provider, as `onnxruntime 1.31.0 CPU`.
  late final String rtFlags;

  /// YuNet's twelve outputs ([yunetOutputs]) for [tensor], blue, green and
  /// red planes of [width] × [height].
  Future<List<Float32List>> detect(Float32List tensor, int width, int height) =>
      _ask(('detect', _next++, tensor, width, height));

  /// The embedding of an aligned face, the 3 × 112 × 112 tensor of the
  /// kernel's AlignFace; not yet a unit vector.
  Future<Float32List> embed(Float32List face) async =>
      (await _ask(('embed', _next++, face, 0, 0))).single;

  Future<List<Float32List>> _ask((String, int, Float32List, int, int) request) {
    final requests = _requests;
    if (requests == null) {
      return Future.error(OrtException('the face runner is closed'));
    }
    final reply = _pending[request.$2] = Completer();
    requests.send(request);
    return reply.future;
  }

  /// Ends the isolate once the runs asked for are done.
  Future<void> close() async {
    _requests?.send(null);
    _requests = null;
    await Future.wait([for (final c in _pending.values) c.future]);
  }

  void _receive(Object? message) {
    switch (message) {
      case (final SendPort requests, final String flags):
        _requests = requests;
        rtFlags = flags;
        _started.complete();
      case (final int id, final List<Float32List> outputs):
        _pending.remove(id)?.complete(outputs);
      case (final int id, final String error):
        _pending.remove(id)?.completeError(OrtException(error));
      case final String error:
        _started.completeError(OrtException(error));
      case null:
        _requests = null;
        _port.close();
        final error = OrtException('the face runner ended');
        if (!_started.isCompleted) _started.completeError(error);
        for (final reply in _pending.values) {
          reply.completeError(error);
        }
        _pending.clear();
    }
  }
}

class _Model {
  const new(
    this.path,
    this.input,
    this.shape,
    this.outputs,
    this.golden,
    this.reference,
  );

  final String path;
  final String input;
  final List<int> shape;
  final List<String> outputs;
  final Float32List golden;
  final Float32List reference;
}

typedef _Start = (SendPort, String?, _Model, _Model);

/// Runs [model] on [tensor] of [shape].
List<Float32List> _run(
  Session session,
  _Model model,
  Float32List tensor,
  List<int> shape,
) {
  final input = Tensor.float32(shape)..values.setAll(0, tensor);
  try {
    return session.run({model.input: input}, model.outputs);
  } finally {
    input.free();
  }
}

Session _load(Ort ort, _Model model) {
  final session = Session(ort, model.path);
  final got = goldenSample(_run(session, model, model.golden, model.shape));
  if (cosine(got, model.reference) < .999) {
    session.close();
    throw OrtException(
      '${model.path} does not reproduce its golden output on the CPU',
    );
  }
  return session;
}

void _serve(_Start start) {
  final (reply, runtime, detectorModel, embedderModel) = start;
  final Ort ort;
  final Session detector;
  final Session embedder;
  try {
    ort = runtime == null ? Ort.bundled() : Ort.open(runtime);
    detector = _load(ort, detectorModel);
    embedder = _load(ort, embedderModel);
  } on Object catch (error) {
    reply.send(error is OrtException ? error.message : '$error');
    return;
  }
  final requests = ReceivePort();
  reply.send((requests.sendPort, 'onnxruntime ${ort.version} CPU fp32'));
  requests.listen((message) {
    if (message case (
      final String kind,
      final int id,
      final Float32List tensor,
      final int width,
      final int height,
    )) {
      try {
        reply.send((
          id,
          kind == 'detect'
              ? _run(detector, detectorModel, tensor, [1, 3, height, width])
              : _run(embedder, embedderModel, tensor, embedderModel.shape),
        ));
      } on Object catch (error) {
        reply.send((id, error is OrtException ? error.message : '$error'));
      }
    } else {
      detector.close();
      embedder.close();
      requests.close();
    }
  });
}
