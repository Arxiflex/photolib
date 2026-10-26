/// Structured logging for the app and its packages (ADR-0115): named [Logger]s send [LogRecord]s to [Log], one hub per
/// isolate, which keeps or drops them by the build's policy and hands them to whoever listens.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

enum LogLevel { debug, info, warning, error }

typedef LogSink = void Function(LogRecord record);

final _secret = RegExp(
  'pass(word|phrase)|token|secret|key|authorization',
  caseSensitive: false,
);

/// A word of a field name that says its value names files or folders.
final _personal = RegExp(
  r'^(file(name)?|folder|path|root|dir|directory|directories|name|uri)s?$',
);
// Between the words of a field name: camelCase, snake_case, kebab-case.
final _wordBreak = RegExp(r'(?<=[a-z\d])(?=[A-Z])|[^A-Za-z\d]+');
// A stack frame's member, Dart's `#0  Class.method` or a browser's
// `at Class.method`: code, not a file name.
final _frame = RegExp(r'^\s*(#\d+|at)\s+[^/\\(]*?(?=\s\(|$)', multiLine: true);
// A word between spaces, quotes, brackets and separators, without a trailing full stop or colon.
final _token = RegExp(
  r'''[^\s'"`()<>\[\]{},;=]+?(?=[.:]*([\s'"`()<>\[\]{},;=]|$))''',
);
final _fileName = RegExp(
  r'\.(?=[a-z\d]*[a-z])[a-z\d]{1,5}$',
  caseSensitive: false,
);
final _kept = RegExp(
  r'^(package:|dart:|(image|video|audio|text|application)/[\w.+-]+$)',
);
const _redacted = '<redacted>';

/// [text] without paths, URIs and file names, which a release log must not hold.
String _scrub(String text) => text.replaceAllMapped(_token, (m) {
  final token = m[0]!;
  return !_kept.hasMatch(token) &&
          (token.contains('/') ||
              token.contains(r'\') ||
              _fileName.hasMatch(token))
      ? _redacted
      : token;
});

bool _names(Object? key) =>
    '$key'.split(_wordBreak).any((w) => _personal.hasMatch(w.toLowerCase()));

Object? _redact(Object? value) => switch (value) {
  null || num() || bool() => value,
  Map() => <String, Object?>{
    for (final MapEntry(:key, :value) in value.entries)
      '$key': _names(key) && value is! num && value is! bool
          ? _redacted
          : _redact(value),
  },
  Iterable() => [for (final v in value) _redact(v)],
  _ => _scrub('$value'),
};

class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.logger,
    required this.message,
    this.fields = const {},
    this.error,
    this.stackTrace,
  });

  /// A record that [toJson] wrote, its error as text.
  factory LogRecord.fromJson(String line) {
    final json = jsonDecode(line) as Map<String, Object?>;
    return LogRecord(
      time: DateTime.parse(json['time']! as String),
      level: LogLevel.values.byName(json['level']! as String),
      logger: json['logger']! as String,
      message: json['message']! as String,
      fields: json['fields']! as Map<String, Object?>,
      error: json['error'],
      stackTrace: switch (json['stackTrace']) {
        final String stack => StackTrace.fromString(stack),
        _ => null,
      },
    );
  }

  final DateTime time;
  final LogLevel level;
  final String logger;
  final String message;
  final Map<String, Object?> fields;
  final Object? error;
  final StackTrace? stackTrace;

  /// One JSON line; fields named like secrets are redacted.
  String toJson() => jsonEncode({
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'logger': logger,
    'message': message,
    'fields': {
      for (final field in fields.entries)
        field.key: _secret.hasMatch(field.key) ? '***' : field.value,
    },
    'error': ?error?.toString(),
    'stackTrace': ?stackTrace?.toString(),
  }, toEncodable: (value) => '$value');

  /// This record without file names, paths or URIs: the values of fields named for them, and whatever looks like one
  /// in its text.
  LogRecord redacted() => LogRecord(
    time: time,
    level: level,
    logger: logger,
    message: _scrub(message),
    fields: _redact(fields)! as Map<String, Object?>,
    error: error == null ? null : _scrub('$error'),
    stackTrace: stackTrace == null
        ? null
        : StackTrace.fromString(
            '$stackTrace'.splitMapJoin(
              _frame,
              onMatch: (m) => m[0] ?? '',
              onNonMatch: _scrub,
            ),
          ),
  );
}

/// This isolate's log: debug and profile builds keep every record with full detail, release builds info and above,
/// [redacted](LogRecord.redacted).
abstract final class Log {
  static var level = LogLevel.debug;
  static var redact = false;
  static final _records = StreamController<LogRecord>.broadcast(sync: true);
  static final _pending = Queue<LogRecord>();
  static var _firing = false;

  /// Every record kept, as it is logged.
  static Stream<LogRecord> get records => _records.stream;

  static void configure({required bool release}) {
    level = release ? LogLevel.info : LogLevel.debug;
    redact = release;
  }

  static void emit(LogRecord record) {
    if (record.level.index < level.index) return;
    _pending.add(redact ? record.redacted() : record);
    // A sync controller cannot fire while it fires: what a listener logs as
    // it hears a record follows that record.
    if (_firing) return;
    _firing = true;
    try {
      while (_pending.isNotEmpty) {
        _records.add(_pending.removeFirst());
      }
    } finally {
      _firing = false;
    }
  }
}

class Logger {
  const Logger(
    this.name, {
    this.sink = Log.emit,
    this.minLevel = LogLevel.debug,
  });

  final String name;
  final LogSink sink;
  final LogLevel minLevel;

  Logger child(String suffix) =>
      Logger('$name.$suffix', sink: sink, minLevel: minLevel);

  void log(
    LogLevel level,
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index || level.index < Log.level.index) return;
    sink(
      LogRecord(
        time: DateTime.now(),
        level: level,
        logger: name,
        message: message,
        fields: fields,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void debug(String message, {Map<String, Object?> fields = const {}}) =>
      log(LogLevel.debug, message, fields: fields);

  void info(String message, {Map<String, Object?> fields = const {}}) =>
      log(LogLevel.info, message, fields: fields);

  void warning(
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.warning,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  void error(
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.error,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );
}
