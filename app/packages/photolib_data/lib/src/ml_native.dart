import 'dart:typed_data';

import 'package:photolib_api/kernel.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_workers/photolib_workers.dart';

/// Upright 8-bit sRGB pixels, row by row.
typedef Rgba = ({int width, int height, Uint8List rgba});

/// Decodes an item, null when it cannot be read.
typedef Decode = Future<Rgba?> Function(LocalAssetData item);

/// What on-device OCR runs in the data isolate (ADR-0388); see
/// [MlIndexer.text].
class OcrSetup {
  /// A setup reading with the models at [files].
  const OcrSetup({
    required this.runtime,
    required this.files,
    required this.decode,
    required this.decoder,
    this.backlog = true,
    this.chunk = 2,
  }) : recognise = null,
       engine = '';

  /// A setup reading with the platform's own text recognition, [recognise]
  /// (Google ML Kit, Apple Vision), which needs no models; [engine] names it.
  const OcrSetup.platform({
    required this.recognise,
    required this.engine,
    this.backlog = false,
    this.chunk = 2,
  }) : runtime = null,
       files = const {},
       decode = _unread,
       decoder = engine;

  /// The ONNX Runtime library; null for the bundled one.
  final String? runtime;

  /// The model files by id (`ocrModels` of `photolib_ml/ocr.dart`).
  final Map<String, String> files;

  /// The platform's decoder, giving the picture the models read.
  final Decode decode;

  /// What [decode] is, such as `vips 8.15`.
  final String decoder;

  /// Whether it reads past the new captures.
  final bool backlog;

  /// Photos per chunk.
  final int chunk;

  /// What reads an item's text where the platform does, else null.
  final Recognise? recognise;

  /// The platform's recognition, such as `mlkit`; empty for PP-OCR.
  final String engine;
}

/// Reads an item's text with the platform, null when it cannot be read. The
/// text is the platform's, so untrusted like any other OCR output.
typedef Recognise = Future<String?> Function(LocalAssetData item);

Future<Rgba?> _unread(LocalAssetData item) async => null;

/// What an image model takes (design 09 §2.2), as its own processor makes
/// it: the whole image resized to a square of `size` pixels (with `crop`, the
/// short side, then the centred square), each channel scaled to 0–1, less its
/// `mean` and over its `std`.
typedef ImageInput = ({
  int size,
  List<double> mean,
  List<double> std,
  bool crop,
});

/// An image model's [run] over what [decode] gives, prepared by the kernel
/// (the library at [kernel], or the bundled one) on [pool]'s workers as the
/// server prepares it (ADR-0254). Items that do not decode do not run.
Embed imageEmbed(
  WorkerPool pool,
  Future<List<Float32List>> Function(List<Float32List> inputs) run,
  Decode decode,
  ImageInput input, {
  String? kernel,
}) => (items) async {
  Future<Float32List?> prepare(LocalAssetData item) async {
    final image = await decode(item);
    if (image == null) return null;
    return await pool.run(prepareImage, (
      kernel,
      image,
      input,
    ), priority: Priority.background).result;
  }

  final inputs = await Future.wait(items.map(prepare));
  final ready = inputs.nonNulls.toList();
  final outputs = ready.isEmpty ? const <Float32List>[] : await run(ready);
  var next = 0;
  return [
    for (final i in inputs)
      if (i == null) null else outputs[next++],
  ];
};

/// The kernel's PrepareImage on a worker: the model's input tensor.
const prepareImage = Task<(String?, Rgba, ImageInput), Float32List>(
  'prepareImage',
  _prepare,
);

final _kernels = <String?, Kernel>{};

Float32List _prepare((String?, Rgba, ImageInput) job, TaskContext _) {
  final (library, image, input) = job;
  final kernel = _kernels[library] ??= library == null
      ? Kernel()
      : Kernel.open(library);
  final response = CallResponse.fromBuffer(
    kernel.call(
      Method.METHOD_PREPARE_IMAGE.value,
      (PrepareImageRequest()
            ..width = image.width
            ..height = image.height
            ..rgba = image.rgba
            ..size = input.size
            ..mean.addAll(input.mean)
            ..std.addAll(input.std)
            ..crop = input.crop)
          .writeToBuffer(),
    ),
  );
  if (response.hasError()) {
    throw FormatException('kernel error ${response.error.code.name}');
  }
  // Copied, to align the floats.
  return Uint8List.fromList(
    PrepareImageResponse.fromBuffer(response.response).tensor,
  ).buffer.asFloat32List();
}
