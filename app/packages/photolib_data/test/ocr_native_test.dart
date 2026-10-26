// On-device OCR (ADR-0388): the data isolate reads the pictures of testdata/ocr/ with PP-OCRv5 on the device's CPU into
// local_ml, and the search finds the items by what they say. About 190 MB of models from tools/ml/fetch.py: it runs
// with PHOTOLIB_ML_MODELS=all or a list that names `ppocr`.
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:photolib_data/ml.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/ocr.dart';
import 'package:test/test.dart';

final String _runtime = {
  Abi.linuxX64: 'ort-linux-x64',
  Abi.linuxArm64: 'ort-linux-arm64',
  Abi.macosArm64: 'ort-macos-arm64',
  Abi.windowsX64: 'ort-windows-x64',
}[Abi.current()]!;

void main() {
  final models = Platform.environment['PHOTOLIB_ML_MODELS'];
  final wanted = models == 'all' || (models?.contains('ppocr') ?? false);
  final kernel = wanted ? buildKernel() : null;
  final pictures = Directory('../../../testdata/ocr').absolute.path;

  Map<String, String> fetch(List<String> names) {
    final result = Process.runSync('python3', [
      '../../../tools/ml/fetch.py',
      ...names,
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (jsonDecode(result.stdout as String) as Map).map(
      (name, files) =>
          MapEntry(name as String, (files as List).first as String),
    );
  }

  /// Decodes the picture a row names, as the desktop's libvips decoder does.
  Future<Rgba?> decode(LocalAssetData item) async {
    final image = img.decodePng(
      File('${item.volume}/${item.path}').readAsBytesSync(),
    )!;
    return (
      width: image.width,
      height: image.height,
      rgba: image.convert(numChannels: 4).toUint8List(),
    );
  }

  test(
    'the data isolate reads the pictures of the device index, and the '
    'search finds them by their text in any script',
    () async {
      final files = fetch([_runtime, ...ocrModels]);
      final dir = await Directory.systemTemp.createTemp('ocr-');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(
        location: '${dir.path}/store',
        keystore: MemoryKeystore(),
        files: storeFiles('${dir.path}/store'),
        keyring: Kernel.open(kernel!).keyring,
      );
      await vault.unlock();
      addTearDown(vault.lock);
      final db = await vault.openReplica();
      for (final (n, name) in ['latin', 'cyrillic', 'cjk', 'xss'].indexed) {
        await db
            .into(db.localAsset)
            .insert(
              LocalAssetCompanion.insert(
                id: Uint8List(16)..[15] = n + 1,
                source: 'folder',
                volume: Value(pictures),
                sourceId: '$n',
                size: 1,
                mtime: 1,
                path: Value('$name.png'),
              ),
            );
      }
      final started = Log.records
          .firstWhere((r) => r.message == 'on-device OCR started')
          .timeout(const Duration(minutes: 2));

      startOcr(
        db,
        OcrSetup(
          runtime: files[_runtime],
          files: {for (final name in ocrModels) name: files[name]!},
          decode: decode,
          decoder: 'test',
        ),
      );
      expect((await started).fields['rt_flags'], startsWith('onnxruntime'));
      await db
          .select(db.localMl)
          .watch()
          .firstWhere((rows) => rows.length == 4);

      Future<List<String>> found(String text) async => [
        for (final a in (await searchPage(
          db,
          LocalQuery(text: text),
          limit: 10,
        )).items)
          a.path!,
      ];
      expect(await found('ESTAÇÃO'), ['latin.png']);
      expect(await found('красная москва'), ['cyrillic.png']);
      expect(await found('東京'), ['cjk.png']);
      expect(await found('onerror=alert(1)'), ['xss.png']);
      final xss = (await db.select(db.localMl).get()).singleWhere(
        (m) => (m.ocrText ?? '').startsWith('<img'),
      );
      expect(xss.ocrText, '<img src=x onerror=alert(1)>');
      expect(xss.model, ocrModel);

      stopOcr(db);
    },
    skip: wanted
        ? null
        : 'set PHOTOLIB_ML_MODELS=all or ppocr-v5-det,... (about 190 MB)',
  );
}
