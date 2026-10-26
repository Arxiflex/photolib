// On-device ML against the server (ADR-0254): the device's path, from decoded
// pixels through the kernel's preprocessing on the worker pool and the runner
// on the ML isolate into local_ml, gives what the server computes, the kernel
// preparing the same pixels and the fp32 model running on the CPU (ADR-0050),
// within design 09 §3.2's cosine 0.99. The gate runs SFace;
// PHOTOLIB_ML_MODELS=all adds SigLIP 2's vision tower, fp16 on the device.
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:photolib_api/kernel.dart';
import 'package:photolib_api/photolib_api.dart' show halfFloats;
import 'package:photolib_data/ml.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/keys.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/runner.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:test/test.dart';

final String _runtime = {
  Abi.linuxX64: 'ort-linux-x64',
  Abi.linuxArm64: 'ort-linux-arm64',
  Abi.macosArm64: 'ort-macos-arm64',
  Abi.windowsX64: 'ort-windows-x64',
}[Abi.current()]!;

/// A model the device runs, the server's file of it, and its input.
typedef _Case = ({
  String device,
  String server,
  String input,
  String output,
  ImageInput image,
});

final _cases = <_Case>[
  (
    device: 'sface',
    server: 'sface',
    input: 'data',
    output: 'fc1',
    image: (
      size: 112,
      mean: [0, 0, 0],
      std: [1 / 255, 1 / 255, 1 / 255],
      crop: false,
    ),
  ),
  if (Platform.environment['PHOTOLIB_ML_MODELS'] == 'all')
    (
      device: 'siglip2-vision-fp16',
      server: 'siglip2-vision',
      input: 'pixel_values',
      output: 'pooler_output',
      image: (size: 256, mean: [.5, .5, .5], std: [.5, .5, .5], crop: false),
    ),
];

/// The local files of pinned artefacts, downloaded on first use.
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

/// A photo-like picture, [width] × [height] RGBA: waves, a disc and a bar,
/// placed by [seed].
Rgba _picture(int width, int height, int seed) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final disc =
          pow(x - width * (.3 + seed * .1), 2) + pow(y - height * .4, 2) <
          pow(height * .2, 2);
      final bar = (x - width * .7).abs() < width * .05 && y > height * .5;
      for (var c = 0; c < 3; c++) {
        final v = disc
            ? .15 + .3 * c
            : bar
            ? .9 - .3 * c
            : .5 + .25 * sin(x * 9 / width + c + seed) * cos(y * 7 / height);
        rgba[(y * width + x) * 4 + c] = (v * 255).round();
      }
      rgba[(y * width + x) * 4 + 3] = 255;
    }
  }
  return (width: width, height: height, rgba: rgba);
}

/// What `local_ml` keeps, finite IEEE 754 binary16 little-endian, as floats.
Float32List _floats(Uint8List halves) {
  final data = ByteData.sublistView(halves);
  return Float32List.fromList([
    for (var i = 0; i < halves.length; i += 2)
      if (data.getUint16(i, Endian.little) case final h)
        (h >> 15 == 1 ? -1 : 1) *
            (h & 0x3ff | (h & 0x7c00 == 0 ? 0 : 0x400)) *
            pow(2, max(h >> 10 & 0x1f, 1) - 25).toDouble(),
  ]);
}

void main() {
  final kernel = buildKernel();
  final files = _fetch([
    _runtime,
    for (final c in _cases) ...{c.device, c.server},
  ]);
  final pool = WorkerPool(const [prepareImage], size: 1);
  tearDownAll(pool.close);
  final ort = Ort.open(files[_runtime]!);

  /// What the server computes for [image]: the kernel's preprocessing, the
  /// fp32 model on the CPU.
  Float32List server(_Case c, Rgba image) {
    final response = CallResponse.fromBuffer(
      Kernel.open(kernel).call(
        Method.METHOD_PREPARE_IMAGE.value,
        (PrepareImageRequest()
              ..width = image.width
              ..height = image.height
              ..rgba = image.rgba
              ..size = c.image.size
              ..mean.addAll(c.image.mean)
              ..std.addAll(c.image.std)
              ..crop = c.image.crop)
            .writeToBuffer(),
      ),
    );
    final values = Uint8List.fromList(
      PrepareImageResponse.fromBuffer(response.response).tensor,
    ).buffer.asFloat32List();
    final size = c.image.size;
    final tensor = Tensor.float32([1, 3, size, size])..values.setAll(0, values);
    final session = Session(ort, files[c.server]!);
    try {
      return session.run({c.input: tensor}, [c.output]).single;
    } finally {
      session.close();
      tensor.free();
    }
  }

  test('a worker prepares the whole image, or its centre square for a model '
      'whose processor crops', () async {
    // The columns of a 2:1 image alternate black and white, as in
    // kernel/tests/ml.rs.
    final stripes = (
      width: 8,
      height: 4,
      rgba: Uint8List.fromList([
        for (var i = 0; i < 32; i++) ...[if (i.isOdd) 255 else 0, 0, 0, 0],
      ]),
    );
    Future<List<double>> row({required bool crop}) async =>
        (await pool.run(prepareImage, (
          kernel,
          stripes,
          (size: 4, mean: [.5, .0, .0], std: [.5, 1.0, 1.0], crop: crop),
        )).result).sublist(0, 4);
    expect(await row(crop: false), [
      for (final v in [-1 / 7, 0, 0, 1 / 7]) closeTo(v, 1e-6),
    ]);
    expect(await row(crop: true), [-1, 1, -1, 1]);
  });

  for (final c in _cases) {
    test('${c.device} indexes a photo on the device as the server embeds it, '
        'within cosine 0.99', () async {
      final golden = _picture(640, 480, 0);
      final photo = _picture(720, 540, 1);
      final goldenInput = await pool.run(prepareImage, (
        kernel,
        golden,
        c.image,
      )).result;
      final state = await Directory.systemTemp.createTemp('ml-');
      addTearDown(() => state.delete(recursive: true));
      final runner = await Runner.start(
        files[_runtime],
        RunnerModel(
          name: c.device,
          path: files[c.device]!,
          input: c.input,
          shape: [1, 3, c.image.size, c.image.size],
          output: c.output,
          golden: goldenInput,
          reference: server(c, golden),
          precision: c.device.endsWith('fp16') ? 'fp16' : 'fp32',
        ),
        state: state.path,
      );
      addTearDown(runner.close);
      final db = await _replica(1);

      await MlIndexer(
        db,
        model: c.device,
        rtFlags: runner.rtFlags,
        embed: imageEmbed(
          pool,
          runner.run,
          (_) async => photo,
          c.image,
          kernel: kernel,
        ),
      ).run();

      final row = await db.select(db.localMl).getSingle();
      final vec = _floats(row.vec!);
      final similarity = cosine(vec, server(c, photo));
      expect(similarity, greaterThanOrEqualTo(.99), reason: row.rtFlags);
      expect(row.rtFlags, startsWith('onnxruntime 1.31.0 CPU'));
    });
  }

  test('the data isolate runs the model on the photos of the device index '
      'while neither its gates nor an upload batch hold it back', () async {
    final c = _cases.first;
    final golden = await pool.run(prepareImage, (
      kernel,
      _picture(640, 480, 0),
      c.image,
    )).result;
    final dir = await Directory.systemTemp.createTemp('ml-');
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
    final started = Log.records
        .firstWhere((r) => r.message == 'on-device ML started')
        .timeout(const Duration(minutes: 2));

    reportUploads(db, active: true);
    startMl(
      db,
      MlSetup(
        runtime: files[_runtime],
        model: RunnerModel(
          name: 'sface@2021dec',
          path: files[c.device]!,
          input: c.input,
          shape: [1, 3, c.image.size, c.image.size],
          output: c.output,
          golden: golden,
          reference: server(c, _picture(640, 480, 0)),
        ),
        input: c.image,
        decode: _decodePhoto,
        decoder: 'test',
        state: dir.path,
        kernel: kernel,
      ),
    );
    final record = await started;
    expect(record.fields['rt_flags'], startsWith('onnxruntime 1.31.0 CPU'));
    Future<void> nothingIndexed() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(await db.select(db.localMl).get(), isEmpty);
    }

    await nothingIndexed();
    holdMl(db, held: true);
    reportUploads(db, active: false);
    await nothingIndexed();

    holdMl(db, held: false);
    final row = await db
        .select(db.localMl)
        .watchSingleOrNull()
        .firstWhere((r) => r != null);
    final vec = _floats(row!.vec!);
    expect(cosine(vec, server(c, _picture(720, 540, 1))), greaterThan(.99));
    expect(row.model, 'sface@2021dec');
  });

  test("a private library's section is the vector as half floats with its "
      "model and runtime, sealed padded under the file's EmbedKey", () {
    final keyring = Kernel.open(kernel).keyring();
    int import(int fill) =>
        Keys(keyring).import(Uint8List(32)..fillRange(0, 32, fill));
    final fileKey = import(7);
    final vector = halfFloats(Float32List.fromList([1, -2, .5]));
    final sealed = sealMlSection(
      keyring,
      fileKey,
      model: 'm@1',
      rtFlags: 'onnxruntime 1.31.0 CPU fp16',
      vector: vector,
      salt: Uint8List(32),
    );
    // PLB, content kind 5 (embedding), padded.
    expect(sealed.sublist(0, 8), [0x50, 0x4c, 0x42, 1, 1, 5, 16, 1]);
    expect(jsonDecode(utf8.decode(openMlSection(keyring, fileKey, sealed))), {
      'model': 'm@1',
      'rt_flags': 'onnxruntime 1.31.0 CPU fp16',
      'vec': 'ADwAwAA4',
    });
    expect(
      () => openMlSection(keyring, import(8), sealed),
      throwsA(isA<KernelError>()),
    );
  });

  test(
    'only the photos that decode run, each output going to its own',
    () async {
      final db = await _replica(3);
      final items = await db.select(db.localAsset).get();
      final ran = <int>[];
      final embed = imageEmbed(
        pool,
        (inputs) async {
          ran.add(inputs.length);
          return [
            for (final i in inputs) Float32List.fromList([i.length.toDouble()]),
          ];
        },
        (a) async => a.sourceId == '1' ? null : _picture(4, 2, 0),
        (size: 2, mean: [0, 0, 0], std: [1, 1, 1], crop: false),
        kernel: kernel,
      );
      expect([for (final o in await embed(items)) o?.single], [12, null, 12]);
      expect(ran, [2]);

      expect(await embed([items[1]]), [null]);
      expect(ran, [2]);
    },
  );
}

/// What the data isolate's decoder gives for every photo.
Future<Rgba?> _decodePhoto(LocalAssetData _) async => _picture(720, 540, 1);

/// A replica of [count] photos.
Future<Replica> _replica(int count) async {
  final db = Replica(NativeDatabase.memory());
  addTearDown(db.close);
  await _seed(db, count);
  return db;
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
