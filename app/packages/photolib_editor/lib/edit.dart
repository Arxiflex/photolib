/// The alpha's edits (ADR-0331): crop, quarter turns, a mirror and a one-tap
/// auto-enhance of a photo as shown, written by the kernel into a copy that
/// never touches the original.
library;

import 'dart:convert' show latin1;
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:photolib_api/develop.dart' as k;
import 'package:photolib_api/kernel.dart';
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_editor/photolib_editor.dart';
import 'package:photolib_workers/blake3.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;

/// A kernel call: a method id and its request to its `CallResponse`.
typedef KernelCall = Uint8List Function(int method, Uint8List request);

/// An edit of a photo as shown, in the kernel's order.
@immutable
class Edit {
  /// No edit, or the one given.
  const new({
    this.quarterTurns = 0,
    this.flip = false,
    this.crop = whole,
    this.enhance,
  });

  /// The edit that [recipe] makes of a photo of [width] × [height] as shown,
  /// by the kernel's [call]: its steps composed into the turns, the mirror and
  /// the one crop of this class, its global adjustments summed. Local
  /// operations (masks, patches) are the recipe's, not an [Edit]'s, and are
  /// left out. Throws [EditFailed] for a recipe the kernel refuses.
  factory fromRecipe(
    KernelCall call,
    r.EditRecipe recipe,
    int width,
    int height,
  ) {
    final answer = CallResponse.fromBuffer(
      call(
        Method.METHOD_RESOLVE_RECIPE.value,
        r.ResolveRecipeRequest(
          recipe: recipe,
          width: width,
          height: height,
        ).writeToBuffer(),
      ),
    );
    if (!answer.hasResponse()) throw EditFailed(answer.error);
    final resolved = r.ResolveRecipeResponse.fromBuffer(answer.response);
    final d = resolved.develop;
    final (w, h) = d.quarterTurns.isOdd ? (height, width) : (width, height);
    final c = d.hasCrop() ? d.crop : null;
    final adjusted =
        d.temperature != 0 ||
        d.tint != 0 ||
        d.exposure != 0 ||
        d.contrast != 0 ||
        d.clarity != 0 ||
        d.saturation != 0;
    return Edit(
      quarterTurns: d.quarterTurns,
      flip: d.flip,
      crop: c == null
          ? whole
          : Rect.fromLTWH(c.x / w, c.y / h, c.width / w, c.height / h),
      enhance: adjusted
          ? Develop(
              temperature: d.temperature,
              tint: d.tint,
              exposure: d.exposure,
              contrast: d.contrast,
              clarity: d.clarity,
              saturation: d.saturation,
            )
          : null,
    );
  }

  /// The crop of the whole photo.
  static const whole = Rect.fromLTRB(0, 0, 1, 1);

  /// Clockwise quarter turns, first.
  final int quarterTurns;

  /// A mirror left to right, after the turns.
  final bool flip;

  /// What is kept of the turned and mirrored photo, in [0, 1]².
  final Rect crop;

  /// Adjustments, last.
  final Develop? enhance;

  /// Whether the edit changes nothing.
  bool get isEmpty =>
      quarterTurns % 4 == 0 && !flip && crop == whole && enhance == null;

  /// Turned a quarter counter-clockwise as seen, the crop with it.
  Edit rotated() => Edit(
    // Seen mirrored, the turn under the mirror goes the other way.
    quarterTurns: (quarterTurns + (flip ? 1 : 3)) % 4,
    flip: flip,
    crop: Rect.fromLTRB(crop.top, 1 - crop.right, crop.bottom, 1 - crop.left),
    enhance: enhance,
  );

  /// Mirrored left to right as seen, the crop with it.
  Edit flipped() => Edit(
    quarterTurns: quarterTurns,
    flip: !flip,
    crop: Rect.fromLTRB(1 - crop.right, crop.top, 1 - crop.left, crop.bottom),
    enhance: enhance,
  );

  /// Cropped to [crop] of the photo as seen, within it.
  Edit cropped(Rect crop) => Edit(
    quarterTurns: quarterTurns,
    flip: flip,
    crop: crop.intersect(whole),
    enhance: enhance,
  );

  /// With [enhance]'s adjustments, or none.
  Edit enhanced(Develop? enhance) => Edit(
    quarterTurns: quarterTurns,
    flip: flip,
    crop: crop,
    enhance: enhance,
  );

  /// The edit as a recipe (ADR-0391), made by [tool]: a turn, a mirror, a crop
  /// and the adjustments, in the order this class applies them, each only if
  /// it changes the photo.
  r.EditRecipe recipe({String tool = ''}) {
    final e = enhance;
    return r.EditRecipe(
      schemaVersion: 1,
      operations: [
        if (quarterTurns % 4 != 0)
          r.Operation(
            operationId: 'turn',
            turn: r.TurnOperation(quarterTurns: quarterTurns % 4),
          ),
        if (flip) r.Operation(operationId: 'flip', flip: r.FlipOperation()),
        if (crop != whole)
          r.Operation(
            operationId: 'crop',
            crop: r.CropOperation(
              x: crop.left,
              y: crop.top,
              width: crop.width,
              height: crop.height,
            ),
          ),
        if (e != null)
          r.Operation(
            operationId: 'adjust',
            adjust: r.AdjustOperation(
              temperature: e.temperature,
              tint: e.tint,
              exposure: e.exposure,
              contrast: e.contrast,
              clarity: e.clarity,
              saturation: e.saturation,
            ),
          ),
      ],
      provenance: r.Provenance(tool: tool),
    );
  }

  /// The recipe of the version that continues [parent], the recipe of the
  /// version this edit was made on: its steps, then this edit's, whose crop is
  /// of the photo as that version shows it, and whose adjustments add to the
  /// version's. Step ids stay unique, and [parent]'s stored outputs stay.
  r.EditRecipe appendedTo(r.EditRecipe? parent, {String tool = ''}) {
    final taken = <String>{
      for (final o in parent?.operations ?? <r.Operation>[]) o.operationId,
    };
    final next = [
      for (final o in recipe().operations)
        o.deepCopy()..operationId = _unique(o.operationId, taken),
    ];
    return r.EditRecipe(
      schemaVersion: 1,
      operations: [...?parent?.operations, ...next],
      outputs: parent?.outputs,
      provenance: r.Provenance(tool: tool),
    );
  }

  static String _unique(String id, Set<String> taken) {
    var candidate = id;
    for (var n = 2; !taken.add(candidate); n++) {
      candidate = '$id-$n';
    }
    return candidate;
  }

  /// The kernel's develop of this edit, for a photo of [width] × [height] as
  /// shown.
  k.Develop develop(int width, int height) {
    final (w, h) = quarterTurns.isOdd ? (height, width) : (width, height);
    final (x, y) = ((crop.left * w).round(), (crop.top * h).round());
    final e = enhance ?? const Develop();
    return k.Develop(
      quarterTurns: quarterTurns,
      flip: flip,
      crop: crop == whole
          ? null
          : k.Rect(
              x: x,
              y: y,
              width: math.max(1, (crop.right * w).round() - x),
              height: math.max(1, (crop.bottom * h).round() - y),
            ),
      temperature: e.temperature,
      tint: e.tint,
      exposure: e.exposure,
      contrast: e.contrast,
      saturation: e.saturation,
    );
  }
}

/// One-tap auto-enhance (design 11 §3): adjustments of [rgba], a proxy's
/// sRGB pixels, as numbers the edit keeps (§2.1 rule 5). Grey-world white
/// balance and exposure toward mid grey, both halfway and the exposure
/// within the highlights, contrast for a narrow tonal range and a little
/// saturation for colour photos.
Develop autoEnhance(Uint8List rgba) {
  final linear = List.generate(256, (v) {
    final c = v / 255;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4);
  });
  final count = rgba.length ~/ 4;
  // At most 65,536 pixels, spread over the image.
  final step = math.max(1, count ~/ 65536);
  var (r, g, b, logs, chroma, n) = (0.0, 0.0, 0.0, 0.0, 0.0, 0);
  final lumas = <double>[];
  for (var i = 0; i < count; i += step) {
    final [pr, pg, pb] = [for (var c = 0; c < 3; c++) rgba[i * 4 + c]];
    final luma =
        0.2126 * linear[pr] + 0.7152 * linear[pg] + 0.0722 * linear[pb];
    lumas.add(luma);
    logs += math.log(math.max(luma, 1e-4)) / math.ln2;
    chroma +=
        (math.max(pr, math.max(pg, pb)) - math.min(pr, math.min(pg, pb))) / 255;
    n++;
    // Clipped and black pixels say nothing of the light.
    if (math.max(pr, math.max(pg, pb)) < 250 && pr + pg + pb > 15) {
      (r, g, b) = (r + linear[pr], g + linear[pg], b + linear[pb]);
    }
  }
  if (n == 0) return const Develop();
  lumas.sort();
  double at(double p) => lumas[((lumas.length - 1) * p).round()];
  double log2(double v) => math.log(v) / math.ln2;
  double round(double v, double limit) =>
      (v.clamp(-limit, limit) * 100).roundToDouble() / 100;
  final white = r > 0 && g > 0 && b > 0;
  var exposure = 0.5 * log2(0.18) - 0.5 * logs / n;
  // Brightening stops before the brightest percent clips.
  exposure = math.min(exposure, math.max(0, -log2(math.max(at(0.99), 1e-4))));
  double encode(double l) =>
      l <= 0.0031308 ? 12.92 * l : 1.055 * math.pow(l, 1 / 2.4) - 0.055;
  final spread = encode(at(0.95)) - encode(at(0.05));
  return Develop(
    temperature: white ? round(0.5 * log2(b / r), 0.4) : 0,
    tint: white ? round(0.5 * log2(g * g / (r * b)), 0.4) : 0,
    exposure: round(exposure, 1),
    contrast: round(math.max(0, 0.6 * (0.75 - spread)), 0.3),
    saturation: chroma / n < 0.02 ? 0 : 0.1,
  );
}

/// The copy of [original], a JPEG, that [edit] makes (ADR-0331), written by
/// the kernel's [call]: with the original's image data when the edit allows,
/// else from the original decoded here, and refused unless it reads back as a
/// JPEG of the same time and place. [time] is the original's capture time,
/// which the copy keeps if the original's metadata lacks it.
k.EditCopyResponse editCopy(
  KernelCall call,
  Uint8List original,
  Edit edit, {
  CaptureTime? time,
}) {
  Uint8List kernel(Method method, GeneratedMessage request) {
    final answer = CallResponse.fromBuffer(
      call(method.value, request.writeToBuffer()),
    );
    if (answer.hasResponse()) return Uint8List.fromList(answer.response);
    throw EditFailed(answer.error);
  }

  ReadMetadataResponse read(List<int> file) => ReadMetadataResponse.fromBuffer(
    kernel(
      Method.METHOD_READ_METADATA,
      ReadMetadataRequest(
        ranges: [FileRange(data: file)],
        size: Int64(file.length),
      ),
    ),
  );
  final meta = read(original);
  final turned = meta.orientation >= 5;
  final develop = edit.develop(
    turned ? meta.height : meta.width,
    turned ? meta.width : meta.height,
  );
  final hash = (Blake3()..add(original)).hex;
  k.EditCopyRequest request([k.Image? image]) => k.EditCopyRequest(
    original: original,
    develop: develop,
    image: image,
    captureTime: time,
    originalBlake3: hash,
  );
  k.EditCopyResponse copy;
  try {
    copy = k.EditCopyResponse.fromBuffer(
      kernel(Method.METHOD_EDIT_COPY, request()),
    );
  } on EditFailed catch (e) {
    if (e.error.params['field'] != 'image') rethrow;
    // As shown: the decoder applies the EXIF orientation.
    final decoded =
        img.decodeJpg(original) ?? (throw const FormatException('no JPEG'));
    final rgba = decoded
        .convert(format: img.Format.uint8, numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    final image = k.Image(
      width: decoded.width,
      height: decoded.height,
      rgba: rgba,
    );
    copy = k.EditCopyResponse.fromBuffer(
      kernel(Method.METHOD_EDIT_COPY, request(image)),
    );
  }
  // Every write is verified before it counts (design 11 §5.1): a JPEG with
  // its original's capture time, place and RGB colour profile.
  final after = read(copy.jpeg);
  final profile = _profile(original);
  final rgb = latin1.decode(profile.take(20).skip(16).toList()) == 'RGB ';
  if (after.format != FileFormat.FILE_FORMAT_JPEG ||
      after.width == 0 ||
      after.location != meta.location ||
      meta.times.isNotEmpty && !listEquals(after.times, meta.times) ||
      rgb && !listEquals(_profile(copy.jpeg), profile)) {
    throw EditFailed(
      CallError(
        code: CallErrorCode.CALL_ERROR_CODE_INVALID_INPUT,
        params: {'reason': 'copy'}.entries,
      ),
    );
  }
  return copy;
}

/// The ICC profile in [jpeg]'s APP2 segments, in their order.
List<int> _profile(List<int> jpeg) {
  final profile = <int>[];
  const name = 'ICC_PROFILE\x00';
  for (var at = 2; at + 4 <= jpeg.length && jpeg[at] == 0xff;) {
    final (marker, end) = (
      jpeg[at + 1],
      at + 2 + (jpeg[at + 2] << 8 | jpeg[at + 3]),
    );
    if (marker == 0xda || end > jpeg.length) break;
    if (marker == 0xe2 &&
        end >= at + 18 &&
        latin1.decode(jpeg.sublist(at + 4, at + 16)) == name) {
      profile.addAll(jpeg.sublist(at + 18, end));
    }
    at = end;
  }
  return profile;
}

/// A kernel call that failed.
class EditFailed implements Exception {
  /// The failure of [error].
  const new(this.error);

  /// Why, as the kernel says.
  final CallError error;

  @override
  String toString() => 'EditFailed: $error';
}
