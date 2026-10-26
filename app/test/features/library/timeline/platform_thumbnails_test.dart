import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/platform_thumbnails.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <List<Object?>>[];
  Object? reply;
  final platformThumbnail = platformThumbnails(const {'content', 'ph'});
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.photolib/thumbnails'),
          (call) async {
            calls.add([call.method, call.arguments]);
            if (call.method != 'load') return null;
            if (reply case final PlatformException error) throw error;
            return reply;
          },
        );
  });

  final photo = ThumbnailItem(
    'p',
    Uri.parse('content://media/external_primary/images/media/42'),
  );

  test('MediaStore hands over RGBA at the tier', () async {
    reply = [
      2,
      1,
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
    ];
    final pixels = await platformThumbnail(photo, 256, Completer().future);
    expect((pixels!.width, pixels.height), (2, 1));
    expect(pixels.bytes, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(pixels.format, ui.PixelFormat.rgba8888);
    expect(calls.single.first, 'load');
    expect((calls.single.last! as List).take(2), [photo.uri.toString(), 256]);
    reply = null;
    await expectLater(
      platformThumbnail(photo, 256, Completer().future),
      throwsA(isA<Declined>().having((e) => e.reason, 'reason', 'nil reply')),
    );
  });

  test('a cancelled request is cancelled by its id, and says so', () async {
    reply = PlatformException(code: 'cancelled', message: '42');
    final cancel = Completer<void>();
    final load = platformThumbnail(photo, 128, cancel.future);
    cancel.complete();
    await expectLater(
      load,
      throwsA(
        isA<Declined>().having((e) => e.reason, 'reason', 'cancelled 42'),
      ),
    );
    await pumpEventQueue();
    final id = (calls.first.last! as List).last;
    expect(calls.last, ['cancel', id]);
  });

  test('PhotoKit hands over BGRA, CoreGraphics\' order, by local '
      'identifier', () async {
    reply = [
      1,
      1,
      Uint8List.fromList([1, 2, 3, 4]),
    ];
    final asset = ThumbnailItem('a', Uri.parse('ph:A1B2/L0/001'));
    final pixels = await platformThumbnail(asset, 256, Completer().future);
    expect(pixels!.bytes, [1, 2, 3, 4]);
    expect(pixels.format, ui.PixelFormat.bgra8888);
    expect((calls.single.last! as List).first, 'ph:A1B2/L0/001');
  });

  test('only the items of its schemes: phones have no files', () async {
    final file = ThumbnailItem('f', Uri.file('/a.jpg'));
    await expectLater(
      platformThumbnail(file, 128, Completer().future),
      throwsA(isA<Declined>().having((e) => e.reason, 'reason', 'no scheme')),
    );
    expect(calls, isEmpty);
  });

  test('macOS and Windows decode files: a refused format is no thumbnail, '
      'a video one without a poster', () async {
    final desktop = platformThumbnails(const {'file'});
    reply = [
      1,
      1,
      Uint8List.fromList([1, 2, 3, 4]),
    ];
    final file = ThumbnailItem('f', Uri.file('/a.jpg'));
    expect((await desktop(file, 256, Completer().future))!.width, 1);
    expect((calls.single.last! as List).first, 'file:///a.jpg');
    reply = PlatformException(code: 'refused', message: 'no HEIC codec');
    await expectLater(
      desktop(file, 256, Completer().future),
      throwsA(
        isA<NoThumbnail>()
            .having((e) => e.video, 'video', false)
            .having((e) => e.cause, 'cause', 'no HEIC codec'),
      ),
    );
    final movie = ThumbnailItem('m', Uri.file('/a.mov'), video: true);
    await expectLater(
      desktop(movie, 256, Completer().future),
      throwsA(isA<NoThumbnail>().having((e) => e.video, 'video', true)),
    );
    reply = PlatformException(
      code: 'unreadable-url',
      message: 'file:///a%ZZ.jpg',
    );
    await expectLater(
      desktop(file, 256, Completer().future),
      throwsA(
        isA<Declined>().having(
          (e) => e.reason,
          'reason',
          'unreadable-url file:///a%ZZ.jpg',
        ),
      ),
    );
    reply = PlatformException(code: 'io', message: 'unreadable');
    await expectLater(
      desktop(file, 256, Completer().future),
      throwsA(isA<PlatformException>()),
    );
  });
}
