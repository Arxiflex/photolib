import 'dart:typed_data';

import 'package:photolib_api/kernel.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/ml_native.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/faces.dart';
import 'package:photolib_ml/registry.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;

const _log = Logger('photolib.workers');

/// What finding faces on the device runs in the data isolate (ADR-0389); see
/// [MlIndexer] and [faceEmbed]. It is started only once the user has agreed.
class FacesSetup {
  /// A setup of [detector] and [embedder].
  const FacesSetup({
    required this.runtime,
    required this.detector,
    required this.detectorPath,
    required this.embedder,
    required this.embedderPath,
    required this.target,
    required this.decode,
    required this.decoder,
    this.backlog = true,
    this.chunk = 4,
    this.kernel,
  });

  /// The ONNX Runtime library; null for the bundled one.
  final String? runtime;

  /// The detector, YuNet, and its file.
  final RegistryModel detector;

  /// Where the detector's file is.
  final String detectorPath;

  /// The embedder, SFace or AuraFace, and its file.
  final RegistryModel embedder;

  /// Where the embedder's file is.
  final String embedderPath;

  /// The registry's name of this platform.
  final String target;

  /// The platform's decoder.
  final Decode decode;

  /// What [decode] is, such as `vips 8.15`.
  final String decoder;

  /// Whether it reads past the new captures.
  final bool backlog;

  /// Photos per run.
  final int chunk;

  /// The kernel library; null for the bundled one.
  final String? kernel;
}

/// The faces indexer and the runner of [setup] over [db], or null when the
/// models do not start (no runtime, or a model that does not reproduce its
/// golden output).
Future<(MlIndexer, FaceRunner)?> startFaceModels(
  FacesSetup setup,
  Replica db,
  WorkerPool pool,
) async {
  try {
    final runner = await FaceRunner.start(
      setup.runtime,
      detector: setup.detector,
      detectorPath: setup.detectorPath,
      embedder: setup.embedder,
      embedderPath: setup.embedderPath,
      target: setup.target,
    );
    final model = FaceModel(model: setup.embedder);
    _log.info(
      'finding faces started',
      fields: {
        'model': model.indexName(setup.detector),
        'rt_flags': runner.rtFlags,
      },
    );
    return (
      MlIndexer(
        db,
        model: model.indexName(setup.detector),
        rtFlags: runner.rtFlags,
        embed: faceEmbed(
          pool,
          runner,
          setup.decode,
          model,
          kernel: setup.kernel,
        ),
        decoder: setup.decoder,
        chunk: setup.chunk,
        backlog: setup.backlog,
      ),
      runner,
    );
  } on Object catch (error) {
    _log.error('finding faces did not start', error: error);
    return null;
  }
}

/// The models that find and describe faces (ADR-0389).
class FaceModel {
  /// The detector's names and the embedder [model], whose registry entry says
  /// how its input is scaled.
  const FaceModel({required this.model});

  /// The embedding model, such as SFace.
  final RegistryModel model;

  /// The length of an embedding.
  int get dim => model.dim ?? (throw StateError('${model.name} has no dim'));

  /// `local_ml`'s model for the faces [detector] and [model] find and
  /// describe.
  String indexName(RegistryModel detector) =>
      'faces:${detector.name}+${model.name}';
}

/// Finds and describes the faces of what [decode] gives, on [runner] and
/// [pool]'s workers, as the server does (ADR-0389): the kernel prepares
/// YuNet's input, reads its outputs, aligns each face for the embedder and
/// normalises what it gives. Each item's output is [packFaces]' of its faces,
/// none for a photo without any; an item that does not decode gives null.
Embed faceEmbed(
  WorkerPool pool,
  FaceRunner runner,
  Decode decode,
  FaceModel model, {
  String? kernel,
}) => (items) async {
  Future<Float32List?> one(LocalAssetData item) async {
    final image = await decode(item);
    if (image == null) return null;
    Future<R> work<I, R>(Task<I, R> task, I input) =>
        pool.run(task, input, priority: Priority.background).result;
    final (width, height, tensor) = await work(prepareFaceDetection, (
      kernel,
      image,
    ));
    final outputs = await runner.detect(tensor, width, height);
    final boxes = await work(readFaces, (kernel, width, height, outputs));
    if (boxes.isEmpty) return packFaces(model.dim, const []);
    final scale = model.model.preprocess;
    if (scale == null) throw StateError('${model.model.name} has no scale');
    final aligned = await work(alignFaces, (
      kernel,
      image,
      boxes,
      scale.mean,
      scale.std,
    ));
    final raw = [for (final tensor in aligned) await runner.embed(tensor)];
    final unit = await work(normalizeEmbeddings, (kernel, raw));
    return packFaces(model.dim, [
      for (final (i, b) in boxes.indexed)
        DeviceFace(
          score: b[4],
          x: b[0],
          y: b[1],
          width: b[2],
          height: b[3],
          landmarks: b.sublist(5),
          embedding: unit[i],
        ),
    ]);
  }

  return [for (final item in items) await one(item)];
};

final _kernels = <String?, Kernel>{};

Kernel _kernel(String? library) =>
    _kernels[library] ??= library == null ? Kernel() : Kernel.open(library);

Uint8List _call(String? library, Method method, GeneratedMessage request) {
  final response = CallResponse.fromBuffer(
    _kernel(library).call(method.value, request.writeToBuffer()),
  );
  if (response.hasError()) {
    throw FormatException('kernel error ${response.error.code.name}');
  }
  return Uint8List.fromList(response.response);
}

Float32List _floats(List<int> bytes) =>
    Uint8List.fromList(bytes).buffer.asFloat32List();

/// The kernel's PrepareFaceDetection on a worker: YuNet's input tensor and
/// its size.
const prepareFaceDetection = Task<(String?, Rgba), (int, int, Float32List)>(
  'prepareFaceDetection',
  _prepareDetection,
);

(int, int, Float32List) _prepareDetection((String?, Rgba) job, TaskContext _) {
  final (library, image) = job;
  final response = PrepareFaceDetectionResponse.fromBuffer(
    _call(
      library,
      Method.METHOD_PREPARE_FACE_DETECTION,
      PrepareFaceDetectionRequest()
        ..width = image.width
        ..height = image.height
        ..rgba = image.rgba,
    ),
  );
  return (response.width, response.height, _floats(response.tensor));
}

/// The kernel's DecodeFaces on a worker: each face as its box (x, y, width,
/// height), score and ten landmark values.
const readFaces =
    Task<(String?, int, int, List<Float32List>), List<List<double>>>(
      'readFaces',
      _read,
    );

List<List<double>> _read(
  (String?, int, int, List<Float32List>) job,
  TaskContext _,
) {
  final (library, width, height, outputs) = job;
  final response = DecodeFacesResponse.fromBuffer(
    _call(
      library,
      Method.METHOD_DECODE_FACES,
      DecodeFacesRequest()
        ..width = width
        ..height = height
        ..outputs.addAll([for (final o in outputs) o.buffer.asUint8List()]),
    ),
  );
  return [
    for (final f in response.faces)
      [f.x, f.y, f.width, f.height, f.score, ...f.landmarks],
  ];
}

/// The kernel's AlignFace on a worker: the embedder's input of each face.
const alignFaces =
    Task<
      (String?, Rgba, List<List<double>>, List<double>, List<double>),
      List<Float32List>
    >('alignFaces', _align);

List<Float32List> _align(
  (String?, Rgba, List<List<double>>, List<double>, List<double>) job,
  TaskContext _,
) {
  final (library, image, faces, mean, std) = job;
  return [
    for (final face in faces)
      _floats(
        AlignFaceResponse.fromBuffer(
          _call(
            library,
            Method.METHOD_ALIGN_FACE,
            AlignFaceRequest()
              ..width = image.width
              ..height = image.height
              ..rgba = image.rgba
              ..landmarks.addAll(face.sublist(5))
              ..mean.addAll(mean)
              ..std.addAll(std),
          ),
        ).tensor,
      ),
  ];
}

/// The kernel's NormalizeFaceEmbedding on a worker: each embedding as a unit
/// vector.
const normalizeEmbeddings =
    Task<(String?, List<Float32List>), List<List<double>>>(
      'normalizeEmbeddings',
      _normalize,
    );

List<List<double>> _normalize((String?, List<Float32List>) job, TaskContext _) {
  final (library, embeddings) = job;
  return [
    for (final e in embeddings)
      NormalizeFaceEmbeddingResponse.fromBuffer(
        _call(
          library,
          Method.METHOD_NORMALIZE_FACE_EMBEDDING,
          NormalizeFaceEmbeddingRequest()..values.addAll(e),
        ),
      ).values,
  ];
}
