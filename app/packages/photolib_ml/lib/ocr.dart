/// PP-OCRv5 on an isolate of its own (M5-08, ADR-0388): the models load on
/// the CPU when first used, as inference calls are long and synchronous.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/src/ocr.dart';

export 'package:photolib_ml/src/ocr.dart'
    show OcrPicture, OcrScript, cleanOcrText, ocrDetector, readText;

/// The ONNX files of the detector and the three recognisers, by model id.
const ocrModels = [
  'ppocr-v5-det',
  'ppocr-v5-rec-latin',
  'ppocr-v5-rec-eslav',
  'ppocr-v5-rec-chinese',
];

/// A reader of pictures running on an isolate of its own.
class OcrReader {
  new _(this._port) {
    _port.listen(_receive);
  }

  /// Starts a reader on the ONNX Runtime library at [runtime], or the one
  /// bundled with the app if null, with the model files at [files] by id
  /// (`ocrModels`). Fails when the library does not load.
  static Future<OcrReader> start(
    String? runtime,
    Map<String, String> files,
  ) async {
    final reader = OcrReader._(ReceivePort());
    await Isolate.spawn(_serve, (
      reader._port.sendPort,
      runtime,
      files,
    ), onExit: reader._port.sendPort);
    await reader._started.future;
    return reader;
  }

  final ReceivePort _port;
  final _started = Completer<void>();
  final _pending = <int, Completer<String>>{};
  SendPort? _requests;
  var _next = 0;

  /// The runtime, execution provider and precision that read the text, as
  /// `onnxruntime 1.31.0 CPU fp32`.
  late final String rtFlags;

  /// The text in [picture], cleaned: one line of it per line of text, empty
  /// for none.
  Future<String> read(OcrPicture picture) {
    final requests = _requests;
    if (requests == null) {
      return Future.error(OrtException('the reader is closed'));
    }
    final id = _next++;
    final reply = _pending[id] = Completer();
    requests.send((
      id,
      picture.width,
      picture.height,
      TransferableTypedData.fromList([picture.rgba]),
    ));
    return reply.future;
  }

  /// Ends the isolate once the reads asked for are done.
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
      case (final int id, final String text):
        _pending.remove(id)?.complete(text);
      case (final int id, final Object error):
        _pending.remove(id)?.completeError(OrtException('$error'));
      case null:
        _requests = null;
        _port.close();
        final error = OrtException('the OCR isolate ended');
        if (!_started.isCompleted) _started.completeError(error);
        for (final reply in _pending.values) {
          reply.completeError(error);
        }
        _pending.clear();
      case final Object error:
        _started.completeError(OrtException('$error'));
    }
  }
}

typedef _Start = (SendPort, String?, Map<String, String>);

void _serve(_Start start) {
  final (reply, runtime, files) = start;
  final Ort ort;
  try {
    ort = runtime == null ? Ort.bundled() : Ort.open(runtime);
  } on Object catch (error) {
    reply.send(error is OrtException ? error.message : '$error');
    return;
  }
  final sessions = <String, Session>{};
  Float32List run(String file, List<int> shape, Float32List data) {
    final id = file.split('@').first;
    final session = sessions[id] ??= Session(
      ort,
      files[id] ?? (throw OrtException('no file for $id')),
    );
    final input = Tensor.float32(shape)..values.setAll(0, data);
    try {
      return session.run({'x': input}, ['fetch_name_0']).single;
    } finally {
      input.free();
    }
  }

  final requests = ReceivePort();
  reply.send((requests.sendPort, 'onnxruntime ${ort.version} CPU fp32'));
  requests.listen((message) {
    if (message case (
      final int id,
      final int width,
      final int height,
      final TransferableTypedData pixels,
    )) {
      try {
        final rgba = pixels.materialize().asUint8List();
        reply.send((
          id,
          readText(run, (width: width, height: height, rgba: rgba)),
        ));
      } on Object catch (error) {
        reply.send((id, error is OrtException ? error.message : '$error'));
      }
    } else {
      for (final session in sessions.values) {
        session.close();
      }
      requests.close();
    }
  });
}
