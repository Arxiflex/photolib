/// The model registry, server/crates/photolib-models/registry.json (ADR-0064),
/// compiled in: what devices download, check and run (design 09 §12).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_ml/src/registry.g.dart';

/// A model at one revision.
class RegistryModel {
  new _(Map<String, Object?> json)
    : id = json['id']! as String,
      revision = json['revision']! as String,
      task = json['task']! as String,
      dim = json['dim'] as int?,
      preprocess = switch (json['preprocess']) {
        {
          'size': final int size,
          'mean': final List<Object?> mean,
          'std': final List<Object?> std,
          'crop': final bool crop,
        } =>
          (size: size, mean: _doubles(mean), std: _doubles(std), crop: crop),
        _ => null,
      },
      files = [
        for (final file
            in (json['files']! as List<Object?>).cast<Map<String, Object?>>())
          RegistryFile._(file),
      ];

  /// Its family, size and resolution, such as `siglip2-b16-256`.
  final String id;

  /// Its export build.
  final String revision;

  /// Such as `image_text_embedding`.
  final String task;

  /// The length of an embedding.
  final int? dim;

  /// What the kernel's PrepareImage makes of an image for it, as its own
  /// processor does: the whole image resized to a square of `size` (with
  /// `crop`, the short side, then the centred square), each channel less
  /// `mean` over `std` (design 09 §2.2).
  final ({int size, List<double> mean, List<double> std, bool crop})?
  preprocess;

  /// Its files: each tower, at each precision.
  final List<RegistryFile> files;

  /// `id@revision`, as outputs name it.
  String get name => '$id@$revision';

  /// The file that embeds images on [target], such as `android`.
  RegistryFile? imageFile(String target) => files
      .where((f) => f.targets.contains(target) && f._golden?.picture != null)
      .firstOrNull;
}

/// A file of a model.
class RegistryFile {
  new _(Map<String, Object?> json)
    : name = json['name']! as String,
      sha256 = json['sha256']! as String,
      size = json['size']! as int,
      targets = (json['targets']! as List<Object?>).cast<String>(),
      urls = (json['urls'] as List<Object?>? ?? const []).cast<String>(),
      _golden = switch (json['golden']) {
        {
          'inputs': [
            {
              'name': final String input,
              'shape': final List<Object?> shape,
              'fill': final Map<String, Object?> fill,
            },
          ],
          'outputs': final List<Object?> outputs,
          'sample': final List<Object?> sample,
        } =>
          (
            input: input,
            shape: shape.cast<int>(),
            outputs: outputs.cast<String>(),
            picture: switch (fill) {
              {'picture': [final num scale, final num offset]} => (
                scale.toDouble(),
                offset.toDouble(),
              ),
              _ => null,
            },
            sample: _doubles(sample),
          ),
        _ => null,
      };

  /// The file's name in the model's directory.
  final String name;

  /// Its SHA-256, lowercase hex.
  final String sha256;

  /// Its length in bytes.
  final int size;

  /// Where it runs: server, android, ios, macos, windows, linux, web.
  final List<String> targets;

  /// The mirrors, tried in order.
  final List<String> urls;

  final ({
    String input,
    List<int> shape,
    List<String> outputs,
    (double, double)? picture,
    List<double> sample,
  })?
  _golden;

  ({
    String input,
    List<int> shape,
    List<String> outputs,
    (double, double)? picture,
    List<double> sample,
  })
  get _one => _golden ?? (throw StateError('$name has no golden of one input'));

  /// The name and shape of its one float input.
  (String, List<int>) get input => (_one.input, _one.shape);

  /// The name of its one output.
  String get output => _one.outputs.length == 1
      ? _one.outputs.single
      : throw StateError('$name has ${_one.outputs.length} outputs');

  /// The names of its outputs, in the order the golden concatenates them.
  List<String> get outputs => _one.outputs;

  /// The golden input: [picture] scaled and offset as the golden says.
  Float32List get goldenInput {
    final (scale, offset) =
        _one.picture ?? (throw StateError('$name takes no picture'));
    return Float32List.fromList(picture(_one.shape.last, scale, offset));
  }

  /// What the fp32 model gives on ONNX Runtime's CPU for [goldenInput]: the
  /// whole output when it has at most 1,024 values.
  Float32List get reference => Float32List.fromList(_one.sample);

  /// The precision of its weights, as `rt_flags` name it.
  String get precision => name.contains('fp16') ? 'fp16' : 'fp32';
}

List<double> _doubles(List<Object?> values) => [
  for (final v in values.cast<num>()) v.toDouble(),
];

/// Every model of the registry.
final List<RegistryModel> registry = [
  for (final model in (jsonDecode(
    registryJson,
  ) as List<Object?>).cast<Map<String, Object?>>())
    RegistryModel._(model),
];

/// A synthetic picture: smooth waves with a disc and a bar, so it has the
/// edges and flat areas of a photo. Values are in [0, 1] times [scale] plus
/// [offset], channel-first: the golden input of the registry's image models.
List<double> picture(int size, double scale, double offset) => [
  for (var c = 0; c < 3; c++)
    for (var y = 0; y < size; y++)
      for (var x = 0; x < size; x++)
        offset +
            scale *
                (pow(x - size * .6, 2) + pow(y - size * .4, 2) <
                        pow(size * .2, 2)
                    ? .15 + .3 * c
                    : (x - size * .25).abs() < size * .1 && y > size * .55
                    ? .9 - .3 * c
                    : .5 +
                          .25 *
                              sin(x * 12 / size + 1.3 * c) *
                              cos(y * 9 / size - .7 * c)),
];
