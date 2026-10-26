import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib_harness/photolib_harness.dart';

void main() {
  LogRecord record({String message = 'synced'}) => LogRecord(
    time: DateTime.utc(2026, 10, 15, 19, 10, 20),
    level: LogLevel.info,
    logger: 'sync',
    message: message,
  );

  group('MemoryLog', () {
    test('keeps only the newest records', () {
      final log = MemoryLog(capacity: 2);
      for (final n in ['a', 'b', 'c']) {
        log.add(record(message: n));
      }
      expect(log.records.map((r) => r.message), ['b', 'c']);
    });

    test('lists newest last and notifies listeners', () {
      final log = MemoryLog();
      var notified = 0;
      log.addListener(() => notified++);
      log.add(record(message: 'a'));
      log.add(record(message: 'b'));
      expect(log.records.map((r) => r.message), ['a', 'b']);
      expect(notified, 2);
    });

    test('hears every record of the isolate until disposed', () {
      final log = MemoryLog();
      const Logger('photolib.test').debug('heard');
      log.dispose();
      const Logger('photolib.test').debug('not heard');
      expect(log.records.map((r) => r.message), ['heard']);
    });
  });

  testWidgets('the environment names each display by its size, '
      'which release builds cannot print', (tester) async {
    tester.view
      ..physicalSize = const Size(2400, 1800)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    expect(environment(), containsPair('display0', '2400x1800 @3.0'));
  });

  group('the native log', () {
    const channel = MethodChannel('org.photolib/log');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    testWidgets('brings what the runner logged before and after it listened '
        'into the log', (tester) async {
      final heard = <LogRecord>[];
      addTearDown(Log.records.listen(heard.add).cancel);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'listen'
            ? [
                [
                  1792400000000,
                  'warning',
                  'folders',
                  'bookmark is stale and was not renewed',
                  {
                    'folder': '/Users/ann/Pictures',
                    'error': 'NSCocoaErrorDomain 259',
                  },
                ],
              ]
            : null,
      );
      await listenToNativeLog();
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('log', [
            1792400000500,
            'error',
            'thumbnails',
            'loadThumbnail failed',
            {'uri': 'content://media/external/images/media/7'},
          ]),
        ),
        (_) {},
      );
      expect(heard.map((r) => (r.logger, r.level, r.message)), [
        (
          'photolib.native.folders',
          LogLevel.warning,
          'bookmark is stale and was not renewed',
        ),
        ('photolib.native.thumbnails', LogLevel.error, 'loadThumbnail failed'),
      ]);
      expect(takeProblems(), [contains('loadThumbnail failed')]);
      expect(heard.first.time.millisecondsSinceEpoch, 1792400000000);
      expect(heard.first.fields, {
        'folder': '/Users/ann/Pictures',
        'error': 'NSCocoaErrorDomain 259',
      });
    });

    testWidgets('is nothing where the runner has none', (tester) async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => throw MissingPluginException(),
      );
      await listenToNativeLog();
    });
  });
}
