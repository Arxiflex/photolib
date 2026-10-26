import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/features/settings/diagnostics.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/pump_app.dart';

/// Records as a debug build keeps them: paths, file names and folders in
/// fields, messages and errors.
final _debugLog = [
  LogRecord(
    time: DateTime.utc(2026, 10, 18, 9),
    level: LogLevel.warning,
    logger: 'photolib.thumbnails',
    message: 'no thumbnail',
    fields: {'file': '/home/annika/Pictures/IMG_0001.jpg', 'tier': 256},
    error:
        'FileSystemException: Cannot open file, path = '
        "'/home/annika/Pictures/IMG_0001.jpg'",
  ),
  LogRecord(
    time: DateTime.utc(2026, 10, 18, 9),
    level: LogLevel.info,
    logger: 'photolib.index',
    message: 'scanned',
    fields: {'root': '/home/annika/Pictures', 'seen': 3},
  ),
  LogRecord(
    time: DateTime.utc(2026, 10, 18, 9),
    level: LogLevel.debug,
    logger: 'photolib.workers',
    message: 'browser decode',
    fields: {'file': 'folder:Holiday/beach.HEIC', 'via': 'ImageDecoder'},
  ),
];
const _names = ['annika', 'Pictures', 'IMG_0001', 'Holiday', 'beach'];

Map<String, String> _unzip(Uint8List zip) => {
  for (final file in ZipDecoder().decodeBytes(zip))
    file.name: utf8.decode(file.content),
};

class _Store implements LogStore {
  new(this._lines);

  final List<String> _lines;

  @override
  void add(LogRecord record) {}

  @override
  Future<List<String>> lines() async => _lines;
}

void main() {
  final lines = [for (final r in _debugLog) r.toJson()];

  test('a bundle holds the log and what the app runs on', () {
    final files = _unzip(
      diagnosticBundle(
        log: lines,
        info: {
          'environment': {'app': '0.1.0+1'},
        },
        release: false,
      ),
    );
    expect(files.keys, ['photolib.log', 'info.json']);
    expect(files['photolib.log'], '${lines.join('\n')}\n');
    expect(jsonDecode(files['info.json']!), {
      'environment': {'app': '0.1.0+1'},
    });
  });

  test('a bundle from a release build holds no file names', () {
    final files = _unzip(
      diagnosticBundle(log: lines, info: const {}, release: true),
    );
    for (final name in _names) {
      expect(files['photolib.log'], isNot(contains(name)));
    }
    expect(files['photolib.log'], contains('"message":"no thumbnail"'));
    expect(files['photolib.log'], contains('"seen":3'));
  });

  group('Settings › Diagnostics', () {
    late Replica db;
    setUp(() => db = Replica(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<List<Uint8List>> pump(
      WidgetTester tester, {
      bool release = false,
    }) async {
      final saved = <Uint8List>[];
      await pumpApp(
        tester,
        replica: (_) => db,
        overrides: [
          releaseBuildProvider.overrideWithValue(release),
          logStoreProvider.overrideWithValue(_Store(lines)),
          bundleSaverProvider.overrideWithValue((name, bytes) async {
            expect(name, matches(RegExp(r'^photolib-diagnostics-\d+\.zip$')));
            saved.add(bytes);
            return true;
          }),
        ],
      );
      return saved;
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollTo(find.text('Diagnostics'));
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
    }

    /// Unmounts the app, so that drift closes its queries on the test's clock.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    }

    testWidgets('are always there in a debug build', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollTo(find.text('Diagnostics'));
      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.text('Show diagnostics'), findsNothing);
      await unmount(tester);
    });

    testWidgets('hide behind an advanced setting in a release build', (
      tester,
    ) async {
      await pump(tester, release: true);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollTo(find.text('Show diagnostics'));
      expect(find.text('Diagnostics'), findsNothing);
      await tester.tap(find.text('Show diagnostics'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('show the live log by level and logger, and copy what they '
        'show', (tester) async {
      await pump(tester);
      await open(tester);
      const Logger('photolib.sync').info('first sync');
      const Logger('photolib.index').debug('a directory');
      await tester.pump();
      expect(find.textContaining('first sync'), findsOneWidget);
      expect(find.textContaining('a directory'), findsOneWidget);

      await tester.tap(find.byTooltip('Level'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('info').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('a directory'), findsNothing);
      expect(find.textContaining('first sync'), findsOneWidget);

      await tester.tap(find.byTooltip('Logger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('photolib.index').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('first sync'), findsNothing);

      await tester.tap(find.byTooltip('Logger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('photolib.sync').last);
      await tester.pumpAndSettle();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byTooltip('Copy the log shown'));
      await tester.pump();
      final records = [
        for (final line in copied!.split('\n')) LogRecord.fromJson(line),
      ];
      expect(records.map((r) => r.message), ['first sync']);
      await unmount(tester);
    });

    testWidgets('export a bundle with versions, settings and library counts, '
        'without a name in a release build', (tester) async {
      await addFolder(db, '/home/annika/Pictures');
      final saved = await pump(tester, release: true);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollTo(find.text('Show diagnostics'));
      await tester.tap(find.text('Show diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export diagnostic bundle'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Diagnostic bundle saved'), findsOneWidget);

      final files = _unzip(saved.single);
      final info = jsonDecode(files['info.json']!) as Map;
      expect(info['environment'], containsPair('build', isNotNull));
      expect(info['environment']['os'], isNotNull);
      expect(info['settings'], containsPair('theme', 'system'));
      expect(info['library'], containsPair('mediaSources', {'scanning': 1}));
      final all = files.values.join('\n');
      for (final name in _names) {
        expect(all, isNot(contains(name)));
      }
      expect(all, contains('no thumbnail'));
      await unmount(tester);
    });
  });
}
