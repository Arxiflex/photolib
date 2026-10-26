// Faces on the device (ADR-0389): from decoded pixels through the kernel's
// face calls on the worker pool and YuNet and SFace on the face runner into
// local_ml, finding what the server finds: the faces of public-domain
// portraits pinned in tools/ml/artefacts.json, where OpenCV's detector finds
// them and told apart as its recogniser tells them apart.
@TestOn('vm')
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:image/image.dart' as img;
import 'package:photolib_data/ml.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_kernel/photolib_kernel.dart' show Kernel;
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/faces.dart';
import 'package:photolib_ml/registry.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:test/test.dart';

final String _runtime = {
  Abi.linuxX64: 'ort-linux-x64',
  Abi.linuxArm64: 'ort-linux-arm64',
  Abi.macosArm64: 'ort-macos-arm64',
  Abi.windowsX64: 'ort-windows-x64',
}[Abi.current()]!;

Map<String, String> _fetch(List<String> names) {
  final result = Process.runSync('python3', [
    '../../../tools/ml/fetch.py',
    ...names,
  ]);
  if (result.exitCode != 0) {
    throw StateError('tools/ml/fetch.py failed:\n${result.stderr}');
  }
  return (jsonDecode(result.stdout as String) as Map).map(
    (name, files) => MapEntry(name as String, (files as List).first as String),
  );
}

/// A photo as the device's decoder gives it: upright RGBA whose short side
/// is 720 (ADR-0278).
Rgba _decode(String path) {
  final decoded = img.decodeJpg(File(path).readAsBytesSync())!;
  final short = min(decoded.width, decoded.height);
  final scaled = short <= 720
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width * 720 ~/ short,
          height: decoded.height * 720 ~/ short,
          interpolation: img.Interpolation.average,
        );
  final rgba = scaled.convert(numChannels: 4, alpha: 255);
  return (
    width: rgba.width,
    height: rgba.height,
    rgba: rgba.getBytes(order: img.ChannelOrder.rgba),
  );
}

/// A decoder of [photo] that captures nothing else, to cross to the data
/// isolate.
Decode _decoding(String photo) =>
    (_) async => _decode(photo);

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

double _iou(List<double> a, List<double> b) {
  final w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]);
  final h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]);
  final both = max(w, 0) * max(h, 0);
  return both / (a[2] * a[3] + b[2] * b[3] - both);
}

void main() {
  final kernel = buildKernel();
  final files = _fetch([
    _runtime,
    'yunet',
    'sface',
    'face-photo-armstrong-a',
    'face-photo-armstrong-b',
    'face-photo-magnus',
  ]);
  final pool = WorkerPool(const [
    prepareFaceDetection,
    readFaces,
    alignFaces,
    normalizeEmbeddings,
  ], size: 1);
  tearDownAll(pool.close);
  final yunet = registry.firstWhere((m) => m.id == 'yunet');
  final sface = registry.firstWhere((m) => m.id == 'sface');
  late final FaceRunner runner;
  setUpAll(() async {
    runner = await FaceRunner.start(
      files[_runtime],
      detector: yunet,
      detectorPath: files['yunet']!,
      embedder: sface,
      embedderPath: files['sface']!,
      target: 'linux',
    );
  });
  tearDownAll(() => runner.close());

  Future<List<DeviceFace>> find(String photo) async {
    final embed = faceEmbed(
      pool,
      runner,
      (_) async => _decode(files[photo]!),
      FaceModel(model: sface),
      kernel: kernel,
    );
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db, 1);
    final item = (await db.select(db.localAsset).get()).single;
    final [packed] = await embed([item]);
    return unpackFaces(packed!);
  }

  test('finds the face of a portrait where OpenCV does, and describes it as '
      'a unit vector', () async {
    final faces = await find('face-photo-armstrong-a');
    expect(faces, hasLength(1));
    final face = faces.single;
    // FaceDetectorYN (OpenCV 5.0) on the picture: x, y, width, height.
    expect(
      _iou(
        [face.x, face.y, face.width, face.height],
        [.2912, .141, .4017, .4312],
      ),
      greaterThan(.85),
    );
    expect(face.landmarks, hasLength(10));
    expect(face.score, greaterThan(.7));
    expect(face.embedding, hasLength(128));
    expect(_dot(face.embedding, face.embedding), closeTo(1, 1e-2));
  });

  test(
    'describes one person alike in two photographs and another unlike',
    () async {
      final a = (await find('face-photo-armstrong-a')).single.embedding;
      final b = (await find('face-photo-armstrong-b')).single.embedding;
      final magnus = (await find('face-photo-magnus')).single.embedding;
      expect(_dot(a, b), inInclusiveRange(.45, .8));
      expect(_dot(a, magnus), lessThan(.3));
      expect(_dot(b, magnus), lessThan(.3));
    },
  );

  test('the data isolate finds no face until it is told to, and none while '
      'its gates hold it', () async {
    final dir = await Directory.systemTemp.createTemp('faces-');
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
    await _seed(db, 1);
    final photo = files['face-photo-armstrong-a']!;
    // Nothing runs on its own: a user who has not agreed has no setup to start.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await db.select(db.localMl).get(), isEmpty);

    final started = Log.records
        .firstWhere((r) => r.message == 'finding faces started')
        .timeout(const Duration(minutes: 2));
    holdMl(db, held: true);
    startFaces(
      db,
      FacesSetup(
        runtime: files[_runtime],
        detector: yunet,
        detectorPath: files['yunet']!,
        embedder: sface,
        embedderPath: files['sface']!,
        target: 'linux',
        decode: _decoding(photo),
        decoder: 'test',
        kernel: kernel,
      ),
    );
    final record = await started;
    expect(record.fields['model'], 'faces:yunet@2026may+sface@2021dec');
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await db.select(db.localMl).get(), isEmpty, reason: 'held');
    holdMl(db, held: false);
    final row = await db
        .select(db.localMl)
        .watchSingleOrNull()
        .firstWhere((r) => r != null);
    expect(unpackFaces(halfFloatsToFloats(row!.vec!)), hasLength(1));
    stopFaces(db);
  });

  test('keeps the faces of a photo in local_ml, a photo without a face as a '
      'row with none, and one that does not decode as failed', () async {
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db, 3);
    final model = FaceModel(model: sface);
    await MlIndexer(
      db,
      model: model.indexName(yunet),
      rtFlags: runner.rtFlags,
      embed: faceEmbed(
        pool,
        runner,
        (item) async {
          return switch (item.sourceId) {
            '0' => _decode(files['face-photo-armstrong-a']!),
            '1' => (width: 64, height: 64, rgba: Uint8List(64 * 64 * 4)),
            _ => null,
          };
        },
        model,
        kernel: kernel,
      ),
    ).run();
    final rows = {
      for (final r in await db.select(db.localMl).get()) r.localAssetId[15]: r,
    };
    expect(rows[0]!.model, 'faces:yunet@2026may+sface@2021dec');
    final stored = unpackFaces(halfFloatsToFloats(rows[0]!.vec!));
    expect(stored, hasLength(1));
    // Half floats: about three decimals.
    expect(stored.single.x, closeTo(.2912, .02));
    expect(rows[1]!.vec, isNotNull);
    expect(unpackFaces(halfFloatsToFloats(rows[1]!.vec!)), isEmpty);
    expect(rows[2]!.failure, isNotNull);
  });
}

Future<void> _seed(Replica db, int count) async {
  for (var n = 0; n < count; n++) {
    await db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: Uint8List(16)..[15] = n,
            source: 'folder',
            volume: const Value('/r'),
            sourceId: '$n',
            size: 1,
            mtime: 1,
            path: Value('$n.jpg'),
          ),
        );
  }
}
