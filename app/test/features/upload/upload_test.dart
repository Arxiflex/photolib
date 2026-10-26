import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/upload/hasher.dart';
import 'package:photolib/features/upload/upload.dart';
import 'package:photolib_workers/blake3.dart';

import '../../support/fake_server.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeServer server;
  late ProviderContainer app;
  setUp(() async {
    server = FakeServer();
    final store = MemoryStore()..value = null;
    app = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(store),
        connectProvider.overrideWithValue((config, instance) => server),
        sessionProvider.overrideWithValue(server),
      ],
    );
    addTearDown(app.dispose);
  });

  final dir = Directory.systemTemp.createTempSync('photolib-upload-');
  tearDownAll(() => dir.deleteSync(recursive: true));

  XFile file(String name, List<int> bytes) {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
    return XFile('${dir.path}/$name');
  }

  String hex(List<int> bytes) => (Blake3()..add(bytes)).hex;

  test('a picked file is hashed, created on the server by its BLAKE3 and '
      'sent, and its progress is kept', () async {
    final uploads = app.read(uploadsProvider.notifier);
    await uploads.add([
      file('IMG_1.jpg', [1, 2, 3, 4, 5]),
    ]);
    final [sent] = server.uploads;
    expect(
      (sent.length, sent.blake3, sent.path),
      (5, hex([1, 2, 3, 4, 5]), 'IMG_1.jpg'),
    );
    expect(sent.sent, [1, 2, 3, 4, 5]);
    final [item] = app.read(uploadsProvider);
    expect(
      (item.name, item.size, item.state),
      ('IMG_1.jpg', 5, UploadState.done),
    );
  });

  test(
    'the hasher gives the BLAKE3 of the file and its progress, only up',
    () async {
      final bytes = List.generate(300000, (i) => i * 7 & 0xff);
      final seen = <double>[];
      final hash = await hashFile(file('big.bin', bytes), seen.add);
      expect(hash, hex(bytes));
      expect(seen.last, 1);
      expect(seen.length, greaterThan(1));
      expect([
        for (var i = 1; i < seen.length; i++) seen[i] >= seen[i - 1],
      ], everyElement(isTrue));
    },
  );

  test("the progress of hashing is the item's, and the hasher is the "
      "app's to choose", () async {
    final hashed = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(MemoryStore()),
        sessionProvider.overrideWithValue(server),
        uploadHasherProvider.overrideWithValue((file, progress) async {
          progress(0.5);
          return 'cafe';
        }),
      ],
    );
    addTearDown(hashed.dispose);
    final seen = <double>[];
    hashed.listen(uploadsProvider, (_, items) {
      if (items.isNotEmpty) seen.add(items.first.hashed);
    });
    await hashed.read(uploadsProvider.notifier).add([
      file('a.jpg', [1]),
    ]);
    expect(seen, contains(0.5));
    expect(server.uploads.single.blake3, 'cafe');
    expect(hashed.read(uploadsProvider).single.hashed, 1);
  });

  test('files go one after another, and a refused one fails alone', () async {
    server.refuseUpload = 'b.jpg';
    await app.read(uploadsProvider.notifier).add([
      file('a.jpg', [1]),
      file('b.jpg', [2]),
      file('c.jpg', [3]),
    ]);
    expect(app.read(uploadsProvider).map((i) => i.state), [
      UploadState.done,
      UploadState.failed,
      UploadState.done,
    ]);
    expect(app.read(uploadsProvider)[1].error, isNotNull);
    expect(server.uploads.map((u) => u.path), ['a.jpg', 'c.jpg']);
  });

  test('without a session nothing is sent and the files wait failed', () async {
    final signedOut = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(MemoryStore()),
        sessionProvider.overrideWithValue(null),
      ],
    );
    addTearDown(signedOut.dispose);
    await signedOut.read(uploadsProvider.notifier).add([
      file('a.jpg', [1]),
    ]);
    expect(signedOut.read(uploadsProvider).single.state, UploadState.failed);
  });

  test('finished uploads can be cleared, running ones stay', () async {
    final uploads = app.read(uploadsProvider.notifier);
    await uploads.add([
      file('a.jpg', [1]),
    ]);
    uploads.clearFinished();
    expect(app.read(uploadsProvider), isEmpty);
  });
}
