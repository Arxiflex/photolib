// The phones' own text recognition (ADR-0388): the data isolate asks the
// platform (ML Kit, Vision) for the text of each item, cleans it as PP-OCR's,
// keeps it in local_ml with the engine, and the search finds it. The platform
// here is a function that answers by path; no models and no phone.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:photolib_data/ml.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:test/test.dart';

/// What the fake platform reads by file name; the payload ends in a bidi
/// override and holds a control character, which are never kept.
Future<String?> _recognise(LocalAssetData item) async => switch (item.path) {
  'sign.jpg' => 'Красная площадь\u0007, Москва',
  'xss.png' => '<img src=x onerror=alert(1)>${String.fromCharCode(0x202e)}',
  'broken.jpg' => throw StateError('the platform failed'),
  _ => null,
};

void main() {
  final kernel = buildKernel();

  test('the data isolate keeps what the platform read, cleaned and named '
      'by its engine, and the search finds the items by it', () async {
    final dir = await Directory.systemTemp.createTemp('ocr-platform-');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(
      location: '${dir.path}/store',
      keystore: MemoryKeystore(),
      files: storeFiles('${dir.path}/store'),
      keyring: Kernel.open(kernel).keyring,
    );
    await vault.unlock();
    addTearDown(vault.lock);
    final db = await vault.openReplica();
    for (final (n, name) in [
      'sign.jpg',
      'xss.png',
      'plain.jpg',
      'broken.jpg',
    ].indexed) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = n + 1,
              source: 'mediastore',
              sourceId: '$n',
              size: 1,
              mtime: 1,
              path: Value(name),
            ),
          );
    }

    startOcr(
      db,
      const OcrSetup.platform(
        recognise: _recognise,
        engine: 'fake',
        backlog: true,
      ),
    );
    await db.select(db.localMl).watch().firstWhere((rows) => rows.length == 4);

    Future<List<String>> found(String text) async => [
      for (final a in (await searchPage(
        db,
        LocalQuery(text: text),
        limit: 10,
      )).items)
        a.path!,
    ];
    expect(await found('КРАСНАЯ москва'), ['sign.jpg']);
    expect(await found('onerror=alert(1)'), ['xss.png']);
    final rows = {
      for (final m in await db.select(db.localMl).get()) m.localAssetId: m,
    };
    final texts = [
      for (final m in rows.values)
        if (m.ocrText != null) m.ocrText,
    ];
    expect(
      texts,
      unorderedEquals([
        'Красная площадь, Москва',
        '<img src=x onerror=alert(1)>',
      ]),
      reason: 'control and bidi characters are dropped, markup is only data',
    );
    expect({for (final m in rows.values) m.model}, {ocrModel});
    expect({for (final m in rows.values) m.rtFlags}, {'fake'});
    expect(
      rows.values.where((m) => m.failure != null).length,
      2,
      reason: 'nothing read and a failure are kept as failed, not retried',
    );

    stopOcr(db);
  });
}
