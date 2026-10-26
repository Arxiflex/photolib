import 'dart:convert';

import 'package:test/test.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_log/photolib_log.dart';

void main() {
  final at = DateTime.utc(2026, 10, 15, 19, 10, 20);

  LogRecord record({
    LogLevel level = LogLevel.info,
    String message = 'synced',
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => LogRecord(
    time: at,
    level: level,
    logger: 'sync',
    message: message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  group('LogRecord.toJson', () {
    test('is one JSON line with the fixed keys', () {
      final json = record(fields: {'assets': 12}).toJson();
      expect(json, isNot(contains('\n')));
      expect(jsonDecode(json), {
        'time': '2026-10-15T19:10:20.000Z',
        'level': 'info',
        'logger': 'sync',
        'message': 'synced',
        'fields': {'assets': 12},
      });
    });

    test('adds the error and the stack trace when there are any', () {
      final json = jsonDecode(
        record(
          level: LogLevel.error,
          error: StateError('boom'),
          stackTrace: StackTrace.fromString('#0 main'),
        ).toJson(),
      );
      expect(json['error'], 'Bad state: boom');
      expect(json['stackTrace'], '#0 main');
    });

    test('redacts fields that look like secrets', () {
      final fields =
          jsonDecode(
                record(
                  fields: {
                    'password': 'hunter2',
                    'apiToken': 'abc',
                    'Authorization': 'Bearer abc',
                    'assets': 3,
                  },
                ).toJson(),
              )['fields']
              as Map;
      expect(fields, {
        'password': '***',
        'apiToken': '***',
        'Authorization': '***',
        'assets': 3,
      });
    });

    test('writes values that JSON cannot hold as text', () {
      final fields =
          jsonDecode(
                record(fields: {'at': at, 'kind': LogLevel.debug}).toJson(),
              )['fields']
              as Map;
      expect(fields['at'], '2026-10-15 19:10:20.000Z');
      expect(fields['kind'], 'LogLevel.debug');
    });
  });

  group('Logger', () {
    test('sends records with its name to the sink', () {
      final sent = <LogRecord>[];
      Logger('sync', sink: sent.add).warning('slow', fields: {'ms': 900});
      expect(sent.single.logger, 'sync');
      expect(sent.single.level, LogLevel.warning);
      expect(sent.single.message, 'slow');
      expect(sent.single.fields, {'ms': 900});
    });

    test('drops records below the minimum level', () {
      final sent = <LogRecord>[];
      Logger('a', sink: sent.add, minLevel: LogLevel.warning)
        ..debug('d')
        ..info('i')
        ..warning('w')
        ..error('e');
      expect(sent.map((r) => r.message), ['w', 'e']);
    });

    test('a child logger extends the name and keeps the sink', () {
      final sent = <LogRecord>[];
      Logger('app', sink: sent.add).child('router').info('go');
      expect(sent.single.logger, 'app.router');
    });

    test('keeps the error and stack trace of a failure', () {
      final sent = <LogRecord>[];
      final stack = StackTrace.current;
      Logger(
        'a',
        sink: sent.add,
      ).error('failed', error: 'x', stackTrace: stack);
      expect(sent.single.error, 'x');
      expect(sent.single.stackTrace, stack);
    });
  });

  group('LogRecord.fromJson', () {
    test('reads back what toJson wrote', () {
      final back = LogRecord.fromJson(
        record(
          level: LogLevel.error,
          fields: {'n': 1, 'tier': 'T2'},
          error: StateError('boom'),
          stackTrace: StackTrace.fromString('#0 main'),
        ).toJson(),
      );
      expect(back.time, at);
      expect(back.level, LogLevel.error);
      expect(back.logger, 'sync');
      expect(back.message, 'synced');
      expect(back.fields, {'n': 1, 'tier': 'T2'});
      expect(back.error, 'Bad state: boom');
      expect('${back.stackTrace}', '#0 main');
    });
  });

  group('LogRecord.redacted', () {
    test('drops the values of fields that name files and folders', () {
      final fields = record(
        fields: {
          'file': '/home/annika/Pictures/IMG_0001.jpg',
          'folderRoot': r'C:\Users\ann',
          'name': 'IMG_0001.jpg',
          'skipped': {'path': 'a/b.png', 'ignored': 2},
          'decoder': 'vips',
          'format': 'image/jpeg',
          'ms': 12,
        },
      ).redacted().fields;
      expect(fields, {
        'file': '<redacted>',
        'folderRoot': '<redacted>',
        'name': '<redacted>',
        'skipped': {'path': '<redacted>', 'ignored': 2},
        'decoder': 'vips',
        'format': 'image/jpeg',
        'ms': 12,
      });
    });

    test('matches field names by whole words and keeps numbers and flags', () {
      final fields = record(
        fields: {
          'directive': 'img-src',
          'fileSystemAccess': true,
          'fileCount': 3,
          'lostFolders': ['/home/annika/Pictures'],
          'source_uri': 'content://media/external/1',
          'originalFilename': 'beach',
          'rootURI': 'beach',
        },
      ).redacted().fields;
      expect(fields, {
        'directive': 'img-src',
        'fileSystemAccess': true,
        'fileCount': 3,
        'lostFolders': '<redacted>',
        'source_uri': '<redacted>',
        'originalFilename': '<redacted>',
        'rootURI': '<redacted>',
      });
    });

    test('keeps the members of stack frames, such as Class.method', () {
      final stack = record(
        stackTrace: StackTrace.fromString(
          '#0      FlutterSecureStorage.write (package:a/b.dart:120:5)\n'
          '#1      Vault.read.<anonymous closure> (file:///home/x/v.dart:4:1)\n'
          '<asynchronous suspension>\n'
          '    at Keys.open (http://localhost:8080/main.dart.js:9:2)\n'
          '    at http://localhost:8080/beach.jpg:1:1',
        ),
      ).redacted().stackTrace;
      expect(
        '$stack',
        '#0      FlutterSecureStorage.write (package:a/b.dart:120:5)\n'
            '#1      Vault.read.<anonymous closure> (<redacted>)\n'
            '<asynchronous suspension>\n'
            '    at Keys.open (<redacted>)\n'
            '    at <redacted>',
      );
    });

    test('removes paths, URIs and file names from text', () {
      final redacted = record(
        message: 'cannot read /home/annika/My Photos/IMG 0001.jpg',
        fields: {'cause': 'beach.HEIC: EncodingError'},
        error: "FileSystemException: Cannot open file, path = 'C:\\ann\\x.png'",
        stackTrace: StackTrace.fromString(
          '#0 open (package:photolib/core/files.dart:12:3)\n'
          '#1 read (file:///home/annika/app/main.dart:4:1)',
        ),
      ).redacted();
      final text = redacted.toJson();
      for (final name in ['annika', 'Photos', '0001', 'beach', 'x.png']) {
        expect(text, isNot(contains(name)));
      }
      expect(redacted.message, 'cannot read <redacted> <redacted> <redacted>');
      expect(redacted.fields['cause'], '<redacted>: EncodingError');
      expect(
        '${redacted.stackTrace}',
        contains('package:photolib/core/files.dart:12:3'),
      );
    });

    test('keeps what names no file', () {
      final kept = record(
        message: 'scanned 3 folders in 1.5 s',
        error: StateError('closed'),
      ).redacted();
      expect(kept.message, 'scanned 3 folders in 1.5 s');
      expect(kept.error, 'Bad state: closed');
    });
  });

  group('Log', () {
    late List<LogRecord> heard;
    setUp(() {
      heard = [];
      final listening = Log.records.listen(heard.add);
      addTearDown(() {
        listening.cancel();
        Log.configure(release: false);
      });
    });

    test('a logger sends to the hub unless given a sink', () {
      const Logger('photolib.test').debug('hello', fields: {'n': 1});
      expect(heard.single.logger, 'photolib.test');
      expect(heard.single.fields, {'n': 1});
    });

    test('whoever hears a record may log at once, after it', () async {
      const log = Logger('t');
      final answering = Log.records.listen((r) {
        if (r.message == 'a') log.info('b');
      });
      addTearDown(answering.cancel);
      // firstWhere completes inside the dispatch, and so runs what awaits it.
      final awaiting = Log.records
          .firstWhere((r) => r.message == 'b')
          .then((_) => log.info('c'));
      log.info('a');
      await awaiting;
      expect(heard.map((r) => r.message), ['a', 'b', 'c']);
    });

    test('debug and profile builds keep everything with full detail', () {
      Log.configure(release: false);
      const Logger('t')
        ..debug('d', fields: {'file': '/a/b.jpg'})
        ..info('i');
      expect(heard.map((r) => r.message), ['d', 'i']);
      expect(heard.first.fields['file'], '/a/b.jpg');
    });

    test('release builds keep info and above, redacted', () {
      Log.configure(release: true);
      const Logger('t')
        ..debug('d')
        ..info('i', fields: {'file': '/a/b.jpg'})
        ..error('e', error: 'cannot open /a/b.jpg');
      expect(heard.map((r) => r.message), ['i', 'e']);
      expect(heard.first.fields['file'], '<redacted>');
      expect(heard.last.error, 'cannot open <redacted>');
      expect(takeProblems(), [contains('cannot open <redacted>')]);
    });
  });
}
