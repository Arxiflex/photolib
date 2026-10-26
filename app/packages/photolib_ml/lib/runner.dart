/// The ML isolate (docs/10-client-app.md §1.5, ADR-0254): one model on an
/// isolate of its own, as inference calls are long and synchronous, run with
/// the first execution provider that reproduces the server's output for the
/// model's golden input (ADR-0050).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_ml/photolib_ml.dart';

/// A model as a [Runner] runs it.
class RunnerModel {
  /// A model at [path] that maps [input], of [shape], to [output].
  const new({
    required this.name,
    required this.path,
    required this.input,
    required this.shape,
    required this.output,
    required this.golden,
    required this.reference,
    this.precision = 'fp32',
  });

  /// Its id@revision.
  final String name;

  /// The ONNX file.
  final String path;

  /// The input's name, float32.
  final String input;

  /// The input's shape.
  final List<int> shape;

  /// The output's name, float32.
  final String output;

  /// The golden input.
  final Float32List golden;

  /// The fp32 model's output for [golden] on the CPU: the server's.
  final Float32List reference;

  /// The weights' precision, such as fp16.
  final String precision;
}

/// The cosine of the angle between [a] and [b]: 1 when they point the same
/// way, and 0 for vectors of different lengths.
double cosine(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var ab = 0.0;
  var aa = 0.0;
  var bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    ab += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return ab / sqrt(aa * bb);
}

/// A model running on an isolate of its own.
class Runner {
  new _(this._port) {
    _port.listen(_receive);
  }

  /// Loads [model] with the ONNX Runtime library at [runtime] on a new
  /// isolate, with the first of [providers], then the CPU, that reproduces
  /// its reference within cosine 0.99 (design 09 §3.3). A provider is
  /// quarantined for the runtime's version in [state], a directory, when its
  /// output strays or when it failed to load or run three times, a crash
  /// included. Fails when no provider is left. A null [runtime] is the one
  /// bundled with the app (`Ort.bundled`).
  static Future<Runner> start(
    String? runtime,
    RunnerModel model, {
    required String state,
    List<String> providers = const [],
  }) async {
    final runner = Runner._(ReceivePort());
    await Isolate.spawn(_serve, (
      runner._port.sendPort,
      runtime,
      model,
      providers,
      '$state/${model.name}.json',
    ), onExit: runner._port.sendPort);
    await runner._started.future;
    return runner;
  }

  final ReceivePort _port;
  final _started = Completer<void>();
  final _pending = <int, Completer<List<Float32List>>>{};
  SendPort? _requests;
  var _next = 0;

  /// The runtime, execution provider and precision that compute the outputs,
  /// as `onnxruntime 1.31.0 CPU fp16`.
  late final String rtFlags;

  /// The model's output for each of [inputs].
  Future<List<Float32List>> run(List<Float32List> inputs) {
    final requests = _requests;
    if (requests == null) {
      return Future.error(OrtException('the runner is closed'));
    }
    final id = _next++;
    final reply = _pending[id] = Completer();
    requests.send((id, inputs));
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
        final error = OrtException('the ML isolate ended');
        if (!_started.isCompleted) _started.completeError(error);
        for (final reply in _pending.values) {
          reply.completeError(error);
        }
        _pending.clear();
    }
  }
}

typedef _Start = (SendPort, String?, RunnerModel, List<String>, String);

void _serve(_Start start) {
  final (reply, runtime, model, providers, state) = start;
  final Ort ort;
  final Session session;
  final String provider;
  try {
    ort = runtime == null ? Ort.bundled() : Ort.open(runtime);
    (session, provider) = _choose(ort, model, providers, File(state));
  } on Object catch (error) {
    reply.send(error is OrtException ? error.message : '$error');
    return;
  }
  final tensor = Tensor.float32(model.shape);
  final requests = ReceivePort();
  reply.send((
    requests.sendPort,
    'onnxruntime ${ort.version} $provider ${model.precision}',
  ));
  requests.listen((message) {
    if (message case (final int id, final List<Float32List> inputs)) {
      try {
        reply.send((
          id,
          [
            for (final input in inputs)
              if (input.length != tensor.length)
                throw ArgumentError(
                  '${input.length} values for ${tensor.shape}',
                )
              else
                session
                    .run(
                      {model.input: tensor..values.setAll(0, input)},
                      [model.output],
                    )
                    .single,
          ],
        ));
      } on Object catch (error) {
        reply.send((id, error is OrtException ? error.message : '$error'));
      }
    } else {
      session.close();
      tensor.free();
      requests.close();
    }
  });
}

/// A session of [model] on the first provider that reproduces its reference,
/// and the provider's name.
(Session, String) _choose(
  Ort ort,
  RunnerModel model,
  List<String> providers,
  File state,
) {
  var failures = <String, int>{};
  try {
    final saved = jsonDecode(state.readAsStringSync()) as Map;
    if (saved['runtime'] == ort.version) {
      failures = (saved['failures'] as Map).cast<String, int>();
    }
  } on Object {
    // None saved, or unreadable: every provider is tried.
  }
  void save() => state.writeAsStringSync(
    jsonEncode({'runtime': ort.version, 'failures': failures}),
  );
  final golden = Tensor.float32(model.shape)..values.setAll(0, model.golden);
  try {
    for (final provider in [...providers, 'CPU']) {
      if ((failures[provider] ?? 0) >= 3) continue;
      // Counted before it loads, so that a crash counts too.
      failures[provider] = (failures[provider] ?? 0) + 1;
      save();
      Session? session;
      try {
        session = Session(
          ort,
          model.path,
          provider: provider == 'CPU' ? null : provider,
        );
        final output = session.run({model.input: golden}, [model.output]);
        if (cosine(output.single, model.reference) >= .99) {
          failures.remove(provider);
          save();
          return (session, provider);
        }
        failures[provider] = 3;
        save();
      } on OrtException {
        // Counted already.
      }
      session?.close();
    }
  } finally {
    golden.free();
  }
  throw OrtException('no execution provider reproduces ${model.name}');
}
