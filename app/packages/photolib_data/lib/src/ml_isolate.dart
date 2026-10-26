import 'package:photolib_data/ml.dart' show OcrSetup, Recognise, imageEmbed;
import 'package:photolib_data/photolib_data.dart' show MlIndexer, ocrModel;
import 'package:photolib_data/src/faces_native.dart';
import 'package:photolib_data/src/open_native.dart' show MlSetup;
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/faces.dart';
import 'package:photolib_ml/ocr.dart' show OcrReader, cleanOcrText;
import 'package:photolib_ml/runner.dart';
import 'package:photolib_workers/photolib_workers.dart';

const _log = Logger('photolib.workers');

/// On-device ML in the data isolate: the indexer and its runner, held back by
/// the device's gates and by an upload batch.
class MlIsolate {
  /// Starts nothing: [handle] does, on a message.
  MlIsolate(this._client, this._pool);

  final Future<Replica> Function() _client;
  final WorkerPool Function() _pool;
  (MlIndexer, Runner)? _running;
  (MlIndexer, OcrReader?)? _reading;
  (MlIndexer, FaceRunner)? _faces;
  bool _held = false;
  bool _uploading = false;

  /// Handles [message] when it is on-device ML's; false otherwise.
  Future<bool> handle(Object? message) async {
    switch (message) {
      case ('ml', final MlSetup setup):
        if (_running != null) break;
        _running = await _startMl(setup, await _client(), _pool());
        _hold();
        _running?.$1.start();
      case ('ml-stop', _):
        final (indexer, runner) = _running ?? (null, null);
        _running = null;
        await indexer?.stop();
        await runner?.close();
      case ('ocr', final OcrSetup setup):
        if (_reading != null) break;
        _reading = await _startOcr(setup, await _client());
        _hold();
        _reading?.$1.start();
      case ('ocr-stop', _):
        final (indexer, reader) = _reading ?? (null, null);
        _reading = null;
        await indexer?.stop();
        await reader?.close();
      case ('faces', final FacesSetup setup):
        if (_faces != null) break;
        _faces = await startFaceModels(setup, await _client(), _pool());
        _hold();
        _faces?.$1.start();
      case ('faces-stop', _):
        final (indexer, runner) = _faces ?? (null, null);
        _faces = null;
        await indexer?.stop();
        await runner?.close();
      case ('ml-hold', final bool held):
        _held = held;
        _hold();
      case ('uploads', final bool active):
        _uploading = active;
        _hold();
      case ('interaction', _):
        _running?.$1.interacted();
        _reading?.$1.interacted();
        _faces?.$1.interacted();
      default:
        return false;
    }
    return true;
  }

  void _hold() {
    _running?.$1.paused = _held || _uploading;
    _reading?.$1.paused = _held || _uploading;
    _faces?.$1.paused = _held || _uploading;
  }
}

/// The indexer and the runner of [setup] over [db], or null when the runner
/// does not start (no runtime, no provider reproduces the model).
Future<(MlIndexer, Runner)?> _startMl(
  MlSetup setup,
  Replica db,
  WorkerPool pool,
) async {
  try {
    final runner = await Runner.start(
      setup.runtime,
      setup.model,
      state: setup.state,
    );
    _log.info(
      'on-device ML started',
      fields: {'model': setup.model.name, 'rt_flags': runner.rtFlags},
    );
    return (
      MlIndexer(
        db,
        model: setup.model.name,
        rtFlags: runner.rtFlags,
        embed: imageEmbed(
          pool,
          runner.run,
          setup.decode,
          setup.input,
          kernel: setup.kernel,
        ),
        decoder: setup.decoder,
        chunk: setup.chunk,
        backlog: setup.backlog,
      ),
      runner,
    );
  } on Object catch (error) {
    _log.error(
      'on-device ML did not start',
      error: error,
      fields: {'model': setup.model.name},
    );
    return null;
  }
}

/// The indexer of text and the reader of [setup] over [db], or null when the
/// models do not load.
Future<(MlIndexer, OcrReader?)?> _startOcr(OcrSetup setup, Replica db) async {
  try {
    final recognise = setup.recognise;
    final reader = recognise == null
        ? await OcrReader.start(setup.runtime, setup.files)
        : null;
    final rtFlags = reader?.rtFlags ?? setup.engine;
    _log.info('on-device OCR started', fields: {'rt_flags': rtFlags});
    return (
      MlIndexer.text(
        db,
        model: ocrModel,
        rtFlags: rtFlags,
        read: (items) async => [
          for (final item in items)
            if (recognise != null)
              await _platformText(recognise, item)
            else
              switch (await setup.decode(item)) {
                final picture? when reader != null => await reader.read(
                  picture,
                ),
                _ => null,
              },
        ],
        decoder: setup.decoder,
        chunk: setup.chunk,
        backlog: setup.backlog,
      ),
      reader,
    );
  } on Object catch (error) {
    _log.error('on-device OCR did not start', error: error);
    return null;
  }
}

/// What the platform read in [item], cleaned like PP-OCR's (control and bidi
/// characters dropped, bounded), or null when it read nothing or failed.
Future<String?> _platformText(Recognise recognise, LocalAssetData item) async {
  try {
    final text = cleanOcrText(await recognise(item) ?? '');
    return text.isEmpty ? null : text;
  } on Object catch (error) {
    _log.warning('the platform did not read an item', error: error);
    return null;
  }
}
