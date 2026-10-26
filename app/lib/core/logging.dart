import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photolib/core/log_native.dart'
    if (dart.library.js_interop) 'package:photolib/core/log_web.dart';
import 'package:photolib_data/photolib_data.dart' show Vault;
import 'package:photolib_log/photolib_log.dart';

export 'package:photolib_log/photolib_log.dart';

/// The versions of the app, Flutter, the operating system or browser and the
/// device, which the log starts with and the diagnostic bundle holds.
Map<String, Object?> environment() => {
  'app': '$appBuildName+$appBuildNumber',
  'build': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
  'flutter': FlutterVersion.version,
  'dart': FlutterVersion.dartVersion,
  ...platformInfo(),
  for (final view in PlatformDispatcher.instance.views)
    'display${view.viewId}':
        '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}'
        ' @${view.devicePixelRatio}',
};

/// Where a build keeps its log across restarts, which the diagnostic bundle
/// holds: a rotating file natively, IndexedDB in browsers (ADR-0115).
abstract interface class LogStore {
  /// Keeps [record].
  void add(LogRecord record);

  /// Every line kept, oldest first.
  Future<List<String>> lines();
}

/// How a release build seals its log at rest (ADR-0115): into PLB envelopes
/// and out of them.
typedef LogSeal = ({
  Future<Uint8List> Function(Uint8List bytes) seal,
  Future<Uint8List> Function(Uint8List envelope) unseal,
});

/// Under the class C key of the vault's object `log`, as every object of the
/// local store (ADR-0057).
LogSeal vaultSeal(Future<Vault> Function() vault) => (
  seal: (bytes) => vault().then((vault) => vault.seal('log', bytes)),
  unseal: (envelope) => vault().then((vault) => vault.unseal('log', envelope)),
);

/// The newest records of this isolate's [Log], for the diagnostics view.
class MemoryLog extends ChangeNotifier {
  /// The newest [capacity] records, from now on.
  new({this.capacity = 1000}) {
    _listening = Log.records.listen(add);
  }

  /// How many records are kept.
  final int capacity;
  final Queue<LogRecord> _records = Queue();
  late final StreamSubscription<LogRecord> _listening;

  /// The records kept, oldest first.
  List<LogRecord> get records => List.unmodifiable(_records);

  /// Keeps [record], dropping the oldest beyond [capacity].
  void add(LogRecord record) {
    _records.add(record);
    if (_records.length > capacity) _records.removeFirst();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_listening.cancel());
    super.dispose();
  }
}

const _native = MethodChannel('org.photolib/log');

/// Hands what the runner's own code logs (Kotlin, Swift, C++) to [Log] as
/// `photolib.native.<logger>`: what it logged before this listened comes with
/// the answer, the rest one record at a time. Runners without the channel
/// (Linux, the web) log nothing of their own.
Future<void> listenToNativeLog() async {
  _native.setMethodCallHandler((call) async => _nativeRecord(call.arguments));
  try {
    (await _native.invokeListMethod<Object?>('listen'))?.forEach(_nativeRecord);
  } on MissingPluginException {
    _native.setMethodCallHandler(null);
  }
}

/// A record as the runners send it: time in ms, level, logger, message, fields.
void _nativeRecord(Object? record) {
  if (record case [
    final int ms,
    final String level,
    final String logger,
    final String message,
    final Map<Object?, Object?> fields,
  ]) {
    Log.emit(
      LogRecord(
        time: DateTime.fromMillisecondsSinceEpoch(ms),
        level: LogLevel.values.asNameMap()[level] ?? LogLevel.error,
        logger: 'photolib.native.$logger',
        message: message,
        fields: {
          for (final MapEntry(:key, :value) in fields.entries) '$key': value,
        },
      ),
    );
  }
}
