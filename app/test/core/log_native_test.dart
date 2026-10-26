import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/log_native.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('log'));
  tearDown(() => dir.deleteSync(recursive: true));

  LogRecord record(int n) => LogRecord(
    time: DateTime.utc(2026),
    level: LogLevel.debug,
    logger: 'photolib.test',
    message: 'record $n',
    fields: {'padding': 'x' * 100},
  );
  Future<List<String>> messages(LogStore log) async => [
    for (final l in await log.lines()) LogRecord.fromJson(l).message,
  ];
  List<String> names() =>
      [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();

  Future<void> rotates(LogSeal? seal, String extension) async {
    final file = LogFile(
      Future.value(dir.path),
      seal: seal,
      maxBytes: 1000,
      files: 3,
    );
    for (var n = 0; n < 50; n++) {
      file.add(record(n));
    }
    await file.flushed;
    expect(names(), [
      'photolib.1.$extension',
      'photolib.2.$extension',
      'photolib.$extension',
    ]);
    for (final f in dir.listSync().cast<File>()) {
      expect(f.lengthSync(), inInclusiveRange(1, 1000));
    }
    final kept = await messages(file);
    expect(kept.last, 'record 49');
    expect(kept, isNot(contains('record 0')));
    expect(kept, [for (var n = 50 - kept.length; n < 50; n++) 'record $n']);
  }

  test('rotates at its bound, keeping the newest files', () async {
    await rotates(null, 'log');
  });

  test('a new run appends to the last file', () async {
    final first = LogFile(Future.value(dir.path))..add(record(1));
    await first.flushed;
    final second = LogFile(Future.value(dir.path))..add(record(2));
    await second.flushed;
    expect(await messages(second), ['record 1', 'record 2']);
  });

  group('a release build seals its log (ADR-0115)', () {
    late Vault vault;
    setUp(() async {
      // Beside the log, its own: every run on the machine shares the temp dir.
      final store = '${dir.path}-store';
      vault = Vault(
        location: store,
        keystore: MemoryKeystore(),
        files: storeFiles(store),
        keyring: Kernel().keyring,
      );
      await vault.unlock();
      addTearDown(() => Directory(store).delete(recursive: true));
    });
    tearDown(() => vault.lock());
    LogFile sealed() =>
        LogFile(Future.value(dir.path), seal: vaultSeal(() async => vault));

    test("each batch a PLB envelope under the vault's class C key of the "
        'log, after its length', () async {
      final log = sealed()
        ..add(record(1))
        ..add(record(2));
      await log.flushed;
      final bytes = File('${dir.path}/photolib.plb').readAsBytesSync();
      expect(latin1.decode(bytes), isNot(contains('record')));
      expect(ByteData.sublistView(bytes).getUint32(0), bytes.length - 4);
      expect(
        utf8.decode(await vault.unseal('log', bytes.sublist(4))),
        '${record(1).toJson()}\n${record(2).toJson()}\n',
      );
      expect(await messages(log), ['record 1', 'record 2']);
    });

    test('rotates at its bound, envelopes included', () async {
      await rotates(vaultSeal(() async => vault), 'plb');
    });

    test('deletes the plaintext log of an earlier build, and a new run '
        'appends', () async {
      final plain = LogFile(Future.value(dir.path))..add(record(0));
      await plain.flushed;
      final first = sealed()..add(record(1));
      await first.flushed;
      expect(names(), ['photolib.plb']);
      final second = sealed()..add(record(2));
      expect(await messages(second), ['record 1', 'record 2']);
    });

    test('cuts an envelope a crash left short before the next', () async {
      await (sealed()..add(record(1))).flushed;
      File('${dir.path}/photolib.plb')
          .writeAsBytesSync([0, 0, 1, 0, 1, 2, 3], mode: FileMode.append);
      final log = sealed()..add(record(2));
      expect(await messages(log), ['record 1', 'record 2']);
    });

    test('skips what the store cannot open, as after a crypto-erase', () async {
      await (sealed()..add(record(1))).flushed;
      await vault.erase();
      await vault.unlock();
      final log = sealed()..add(record(2));
      expect(await messages(log), ['record 2']);
    });

    test("the app's log store, in a release build only", () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async => dir.path,
            );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      for (final release in [false, true]) {
        final container = ProviderContainer(
          overrides: [
            releaseBuildProvider.overrideWithValue(release),
            vaultProvider.overrideWith((ref) async => vault),
          ],
        );
        final log = container.read(logStoreProvider);
        const Logger('photolib.test').info('release: $release');
        expect((await messages(log)).last, 'release: $release');
        container.dispose();
      }
      expect(Directory('${dir.path}/logs').listSync(), [
        isA<File>().having((f) => f.path, 'path', endsWith('photolib.plb')),
      ]);
    });
  });
}
