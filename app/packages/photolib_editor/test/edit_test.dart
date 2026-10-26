// The alpha's edits (ADR-0331) through the kernel's C ABI, their copies
// decoded by package:image, a decoder of its own.
@TestOn('vm')
library;

import 'dart:convert' show latin1;
import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib_api/develop.dart' as k;
import 'package:photolib_api/kernel.dart' show CallResponse, Method;
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_editor/edit.dart';
import 'package:photolib_editor/photolib_editor.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_workers/blake3.dart';

Uint8List corpus(String path) =>
    File('../../../testdata/corpus/files/$path').readAsBytesSync();

/// The photo as a viewer shows it, EXIF orientation applied.
img.Image shown(Uint8List jpeg) => img.decodeJpg(jpeg)!;

/// The mean absolute difference of [a] and [b] per channel, and of their
/// means: how far apart the pixels are, and how far the colours shifted.
(double, double) difference(img.Image a, img.Image b) {
  expect((a.width, a.height), (b.width, b.height));
  var (sum, shift) = (0.0, <double>[0, 0, 0]);
  // The iterator moves one pixel along, so each is read before the next.
  for (final p in a) {
    final q = b.getPixel(p.x, p.y);
    for (var c = 0; c < 3; c++) {
      sum += (p[c] - q[c]).abs();
      shift[c] += p[c] - q[c];
    }
  }
  final n = a.width * a.height;
  return (sum / n / 3, shift.map((s) => s.abs() / n).reduce(max));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = Kernel.open(buildKernel());

  /// What the kernel's renderer makes of [image] with [edit]'s geometry.
  img.Image render(Edit edit, img.Image image) {
    final answer = CallResponse.fromBuffer(
      kernel.call(
        Method.METHOD_DEVELOP.value,
        k.DevelopRequest(
          develop: edit.develop(image.width, image.height),
          image: k.Image(
            width: image.width,
            height: image.height,
            rgba: image.getBytes(order: img.ChannelOrder.rgba),
          ),
        ).writeToBuffer(),
      ),
    );
    final out = k.DevelopResponse.fromBuffer(answer.response).image;
    return img.Image.fromBytes(
      width: out.width,
      height: out.height,
      bytes: Uint8List.fromList(out.rgba).buffer,
      numChannels: 4,
    );
  }

  List<num> pixels(img.Image image) => [
    image.width,
    for (final p in image) p.r,
  ];

  test('a rotation or mirror moves what is seen, the crop with it', () {
    final grid = img.Image(width: 4, height: 4, numChannels: 4);
    for (final p in grid) {
      p
        ..r = p.y * 4 + p.x
        ..a = 255;
    }
    const crop = Rect.fromLTRB(0.25, 0, 1, 0.5);
    for (final edit in [
      const Edit(),
      const Edit().flipped(),
      const Edit().rotated().flipped(),
    ].map((e) => e.cropped(crop))) {
      final seen = render(edit, grid);
      expect(
        pixels(render(edit.rotated(), grid)),
        pixels(img.copyRotate(seen, angle: -90)),
      );
      expect(
        pixels(render(edit.flipped(), grid)),
        pixels(img.flipHorizontal(img.Image.from(seen))),
      );
    }
  });

  /// A [width] × [height] image whose sRGB pixels [pixel] gives.
  Uint8List image(int width, int height, List<int> Function(int, int) pixel) =>
      Uint8List.fromList([
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++) ...[...pixel(x, y), 255],
      ]);

  group('auto-enhance', () {
    test('leaves a balanced photo nearly alone', () {
      final grey = autoEnhance(
        image(64, 64, (x, y) => List.filled(3, 30 + 3 * x)),
      );
      expect([grey.temperature, grey.tint, grey.saturation], [0, 0, 0]);
      expect(grey.exposure.abs(), lessThan(0.15));
    });

    test('brightens a dark photo and warms a blue one, as numbers', () {
      final dark = autoEnhance(
        image(64, 64, (x, y) => [10 + x ~/ 2, 12 + x ~/ 2, 40 + x]),
      );
      expect(dark.exposure, greaterThan(0.5));
      expect(dark.temperature, greaterThan(0.2));
      expect(dark.saturation, 0.1);
      for (final v in [dark.exposure, dark.temperature, dark.contrast]) {
        expect(v * 100, (v * 100).roundToDouble());
      }
    });

    test('darkens a bright photo and stops before its highlights clip', () {
      final bright = autoEnhance(
        image(64, 64, (x, y) => List.filled(3, 200 + x % 56)),
      );
      expect(bright.exposure, lessThan(0));
      final lit = autoEnhance(
        image(64, 64, (x, y) => List.filled(3, x < 2 ? 255 : 60)),
      );
      expect(lit.exposure, 0);
    });
  });

  group('a copy', () {
    test('turned keeps the image data: the same pixels, turned', () {
      final original = corpus('stills/gps-sydney.jpg');
      final copy = editCopy(
        kernel.call,
        original,
        const Edit().rotated().rotated().rotated(),
      );
      expect(copy.lossless, isTrue);
      final want = img.copyRotate(shown(original), angle: 90);
      expect(difference(shown(Uint8List.fromList(copy.jpeg)), want).$1, 0);
    });

    test('cropped keeps the pixels of the crop', () {
      final original = corpus('stills/baseline.jpg');
      // 4:2:0 blocks of 16: the corner moves from (40, 24) to (32, 16).
      final edit = const Edit().cropped(
        const Rect.fromLTRB(40 / 640, 24 / 480, 360 / 640, 264 / 480),
      );
      final copy = editCopy(kernel.call, original, edit);
      expect(copy.lossless, isTrue);
      final crop = shown(Uint8List.fromList(copy.jpeg));
      expect((crop.width, crop.height), (328, 248));
      final region = img.copyCrop(
        shown(original),
        x: 32,
        y: 16,
        width: 328,
        height: 248,
      );
      expect(difference(crop, region).$1, lessThan(0.05));
    });

    test('of a turned photo crops what is seen', () {
      final original = corpus('compound/orientation/orientation-6.jpg');
      final edit = const Edit().cropped(const Rect.fromLTRB(0, 0, 0.5, 0.25));
      final copy = editCopy(kernel.call, original, edit);
      final crop = shown(Uint8List.fromList(copy.jpeg));
      expect((crop.width, crop.height, copy.lossless), (240, 160, true));
    });

    test('encoded shifts no colour and keeps date and place', () {
      final original = corpus('stills/progressive.jpg');
      final edit = const Edit().cropped(const Rect.fromLTRB(0, 0, 0.5, 0.5));
      final copy = editCopy(kernel.call, original, edit);
      expect(copy.lossless, isFalse);
      final out = shown(Uint8List.fromList(copy.jpeg));
      final region = img.copyCrop(
        shown(original),
        x: 0,
        y: 0,
        width: 400,
        height: 300,
      );
      final (error, shift) = difference(out, region);
      expect(error, lessThan(1));
      expect(shift, lessThan(0.25));
      final exif = img.decodeJpgExif(Uint8List.fromList(copy.jpeg))!;
      final before = img.decodeJpgExif(original)!;
      expect(
        exif.exifIfd['DateTimeOriginal']?.toString(),
        before.exifIfd['DateTimeOriginal']?.toString(),
      );
    });

    test('names its original by its BLAKE3', () {
      final original = corpus('stills/baseline.jpg');
      final copy = editCopy(kernel.call, original, const Edit().rotated());
      final hash = (Blake3()..add(original)).hex;
      expect(latin1.decode(copy.jpeg), contains('>blake3:$hash<'));
    });

    test('that lost what its original says is no copy', () {
      final original = corpus('stills/gps-sydney.jpg');
      // A kernel whose copy is another photo, of the same time but nowhere.
      Uint8List lying(int method, Uint8List request) =>
          method == Method.METHOD_EDIT_COPY.value
          ? CallResponse(
              response: k.EditCopyResponse(jpeg: corpus('stills/baseline.jpg'))
                  .writeToBuffer(),
            ).writeToBuffer()
          : kernel.call(method, request);
      expect(
        () => editCopy(lying, original, const Edit().rotated()),
        throwsA(isA<EditFailed>()),
      );
    });

    test('that lost its colour profile is no copy', () {
      // A Display P3 photo's profile, in short: its header.
      final profile = [
        ...'ICC_PROFILE'.codeUnits,
        0,
        1,
        1,
        ...List.filled(16, 0),
        ...'RGB XYZ '.codeUnits,
        ...List.filled(104, 0),
      ];
      final segment = [0xff, 0xe2, 0, profile.length + 2, ...profile];
      final jpeg = corpus('stills/baseline.jpg');
      final original = Uint8List.fromList([
        ...jpeg.take(2),
        ...segment,
        ...jpeg.skip(2),
      ]);
      // A kernel whose copy leaves the profile out.
      Uint8List dropping(int method, Uint8List request) {
        final answer = kernel.call(method, request);
        if (method != Method.METHOD_EDIT_COPY.value) return answer;
        final copy = k.EditCopyResponse.fromBuffer(
          CallResponse.fromBuffer(answer).response,
        ).jpeg;
        final at = latin1.decode(copy).indexOf('ICC_PROFILE') - 4;
        return CallResponse(
          response: k.EditCopyResponse(
            jpeg: [...copy.take(at), ...copy.skip(at + segment.length)],
          ).writeToBuffer(),
        ).writeToBuffer();
      }

      final copy = editCopy(kernel.call, original, const Edit().rotated());
      expect(latin1.decode(copy.jpeg), contains(latin1.decode(segment)));
      expect(
        () => editCopy(dropping, original, const Edit().rotated()),
        throwsA(isA<EditFailed>()),
      );
    });

    test('of a photo with GPS and a time keeps them', () {
      final original = corpus('stills/gps-sydney.jpg');
      final edit = const Edit()
          .cropped(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9))
          .enhanced(const Develop(exposure: 0.3));
      final copy = editCopy(kernel.call, original, edit);
      expect(copy.lossless, isFalse);
      final (after, before) = (
        img.decodeJpgExif(Uint8List.fromList(copy.jpeg))!,
        img.decodeJpgExif(original)!,
      );
      for (final tag in ['GPSLatitude', 'GPSLongitude']) {
        expect(after.gpsIfd[tag].toString(), before.gpsIfd[tag].toString());
      }
      expect(
        after.exifIfd['DateTimeOriginal'].toString(),
        before.exifIfd['DateTimeOriginal'].toString(),
      );
    });
  });

  group('as a recipe (ADR-0391)', () {
    img.Image renderRecipe(r.EditRecipe recipe, img.Image image) {
      final answer = CallResponse.fromBuffer(
        kernel.call(
          Method.METHOD_RENDER_RECIPE.value,
          r.RenderRecipeRequest(
            recipe: recipe,
            image: k.Image(
              width: image.width,
              height: image.height,
              rgba: image.getBytes(order: img.ChannelOrder.rgba),
            ),
          ).writeToBuffer(),
        ),
      );
      final out = r.RenderRecipeResponse.fromBuffer(answer.response).image;
      return img.Image.fromBytes(
        width: out.width,
        height: out.height,
        bytes: Uint8List.fromList(out.rgba).buffer,
        numChannels: 4,
      );
    }

    final grid = img.Image(width: 16, height: 12, numChannels: 4);
    for (final p in grid) {
      p
        ..r = p.x * 15
        ..g = p.y * 20
        ..b = (p.x * 7 + p.y * 3) % 256
        ..a = 255;
    }
    const crop = Rect.fromLTRB(0.25, 0.1, 0.9, 0.8);
    final edits = {
      'nothing': const Edit(),
      'a turn': const Edit().rotated(),
      'a mirror and a turn': const Edit().flipped().rotated(),
      'a crop': const Edit().cropped(crop),
      'everything': const Edit()
          .rotated()
          .flipped()
          .cropped(crop)
          .enhanced(
            const Develop(
              temperature: 0.1,
              exposure: 0.4,
              contrast: 0.2,
              saturation: -0.1,
            ),
          ),
    };

    test('renders as the develop it replaces, for every edit', () {
      for (final MapEntry(:key, value: edit) in edits.entries) {
        expect(
          pixels(renderRecipe(edit.recipe(tool: 'test'), grid)),
          pixels(render(edit, grid)),
          reason: key,
        );
      }
    });

    test('has the operations the editor makes, in order, and the tool', () {
      final recipe = edits['everything']!.recipe(tool: 'photolib/1 (test)');
      expect(
        [for (final o in recipe.operations) o.whichKind().name],
        ['turn', 'flip', 'crop', 'adjust'],
      );
      expect(recipe.provenance.tool, 'photolib/1 (test)');
      expect(recipe.schemaVersion, 1);
      expect(const Edit().recipe().operations, isEmpty);
      expect(
        const Edit()
            .enhanced(const Develop(clarity: 0.4))
            .recipe()
            .operations
            .single
            .adjust
            .clarity,
        closeTo(0.4, 1e-6),
        reason: 'the recipe carries what a Develop request leaves out',
      );
    });

    test('reads back through the kernel as the edit it was made from', () {
      for (final MapEntry(:key, value: edit) in edits.entries) {
        final back = Edit.fromRecipe(
          kernel.call,
          edit.recipe(),
          grid.width,
          grid.height,
        );
        expect(back.quarterTurns % 4, edit.quarterTurns % 4, reason: key);
        expect(back.flip, edit.flip, reason: key);
        final (w, h) = edit.quarterTurns.isOdd
            ? (grid.height, grid.width)
            : (grid.width, grid.height);
        for (final (a, b, size) in [
          (back.crop.left, edit.crop.left, w),
          (back.crop.right, edit.crop.right, w),
          (back.crop.top, edit.crop.top, h),
          (back.crop.bottom, edit.crop.bottom, h),
        ]) {
          expect(a, closeTo(b, 0.5 / size), reason: key);
        }
        expect(back.enhance == null, edit.enhance == null, reason: key);
        expect(
          back.enhance?.exposure ?? 0,
          closeTo(edit.enhance?.exposure ?? 0, 1e-6),
          reason: key,
        );
      }
    });

    test('reads a recipe of several crops and turns as one geometry', () {
      final recipe = r.EditRecipe(
        schemaVersion: 1,
        operations: [
          r.Operation(
            operationId: 'a',
            crop: r.CropOperation(x: 0, y: 0, width: 0.5, height: 1),
          ),
          r.Operation(operationId: 'b', turn: r.TurnOperation(quarterTurns: 1)),
          r.Operation(
            operationId: 'c',
            crop: r.CropOperation(x: 0, y: 0.5, width: 1, height: 0.5),
          ),
          r.Operation(
            operationId: 'd',
            adjust: r.AdjustOperation(exposure: 0.5),
          ),
          r.Operation(
            operationId: 'e',
            adjust: r.AdjustOperation(exposure: 0.25),
          ),
        ],
      );
      final edit = Edit.fromRecipe(kernel.call, recipe, 16, 12);
      expect(edit.quarterTurns, 1);
      // Half the width, turned (the whole photo turned is 12 × 16; the half is
      // its top 8 rows), then that half's bottom half: rows 4 to 8 of 16.
      expect(edit.crop, const Rect.fromLTRB(0, 0.25, 1, 0.5));
      expect(edit.enhance?.exposure, closeTo(0.75, 1e-6));
      expect(
        pixels(render(edit, grid)),
        pixels(renderRecipe(recipe, grid)),
        reason: 'the same picture either way',
      );
    });

    test('continues the recipe of the version it edits', () {
      // Cropped and turned already; this edit mirrors what is seen and crops.
      final parent = const Edit()
          .rotated()
          .cropped(const Rect.fromLTRB(0, 0, 1, 0.5))
          .recipe(tool: 'before');
      final more = const Edit().flipped().cropped(
        const Rect.fromLTRB(0.25, 0, 1, 1),
      );
      final composed = more.appendedTo(parent, tool: 'after');
      expect(
        [for (final o in composed.operations) o.operationId],
        ['turn', 'crop', 'flip', 'crop-2'],
        reason: 'the ids stay unique, the first steps stay as they were',
      );
      expect(composed.operations.take(2).toList(), parent.operations);
      expect(composed.provenance.tool, 'after');
      final seen = renderRecipe(parent, grid);
      expect(
        pixels(renderRecipe(composed, grid)),
        pixels(render(more, seen)),
        reason: 'the new edit is made on the picture the user sees',
      );
      expect(more.appendedTo(null).operations, hasLength(2));
    });

    test('is refused when the kernel refuses it', () {
      final bad = r.EditRecipe(schemaVersion: 9);
      expect(
        () => Edit.fromRecipe(kernel.call, bad, 16, 12),
        throwsA(isA<EditFailed>()),
      );
    });
  });
}
