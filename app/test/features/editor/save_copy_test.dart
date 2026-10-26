import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/core/kernel.dart';
import 'package:photolib/features/editor/save_copy.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib_api/kernel.dart' show CaptureTime;
import 'package:photolib_editor/edit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('edit'));
  tearDown(() => folder.deleteSync(recursive: true));

  File photo(String corpus, String name) =>
      File('../testdata/corpus/files/$corpus').copySync('${folder.path}/$name');

  ThumbnailItem item(File file) => ThumbnailItem(file.path, file.uri);

  test('a copy goes beside its original, which stays byte for byte, and '
      'never over another file', () async {
    final original = photo('stills/gps-sydney.jpg', 'IMG_0001.jpg');
    final bytes = original.readAsBytesSync();
    final first = await saveCopy(item(original), const Edit().rotated(), null);
    final second = await saveCopy(
      item(original),
      const Edit().cropped(const Rect.fromLTRB(0, 0, 0.5, 0.5)),
      null,
    );
    expect(original.readAsBytesSync(), bytes);
    expect(
      [first?.uri.pathSegments.last, second?.uri.pathSegments.last],
      ['IMG_0001_edit.jpg', 'IMG_0001_edit-2.jpg'],
    );
    expect(folder.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      'IMG_0001.jpg',
      'IMG_0001_edit.jpg',
      'IMG_0001_edit-2.jpg',
    });
    // The turn is the copy's EXIF orientation; date and place stay.
    final copy = File.fromUri(first!.uri).readAsBytesSync();
    final (exif, before) = (
      img.decodeJpgExif(copy)!,
      img.decodeJpgExif(bytes)!,
    );
    expect(exif.imageIfd.orientation, 8);
    expect(
      exif.exifIfd['DateTimeOriginal'].toString(),
      before.exifIfd['DateTimeOriginal'].toString(),
    );
    expect(exif.gpsIfd.data.keys, before.gpsIfd.data.keys);
  });

  test(
    'a copy keeps the capture time that only the device index knew',
    () async {
      final original = photo('stills/mpf-secondary.jpg', 'scan.jpg');
      final time = CaptureTime(
        localDatetime: '2021-06-01T09:30:00',
        offsetMinutes: 120,
      );
      final copy = await saveCopy(item(original), const Edit().flipped(), time);
      expect(
        String.fromCharCodes(File.fromUri(copy!.uri).readAsBytesSync()),
        contains('exif:DateTimeOriginal="2021-06-01T09:30:00+02:00"'),
      );
    },
  );

  test('edits JPEG photos in folders and MediaStore', () {
    for (final (item, mime, editable) in [
      (ThumbnailItem('a', Uri.file('/p/a.JPG')), null, true),
      (
        ThumbnailItem('b', Uri.parse('content://media/x/images/media/1')),
        'image/jpeg',
        true,
      ),
      (ThumbnailItem('c', Uri.file('/p/c.png')), 'image/png', false),
      (ThumbnailItem('d', Uri.file('/p/d.jpg'), video: true), null, false),
      (
        ThumbnailItem('e', Uri(scheme: 'ph', path: 'X/L0/001')),
        'image/jpeg',
        false,
      ),
    ]) {
      expect(canEdit(item, mime), editable, reason: item.key);
    }
  });

  test('a folder it cannot write asks where the copy goes, never over the '
      'original', () async {
    final shut = Directory('${folder.path}/shut')..createSync();
    final original = photo('stills/gps-sydney.jpg', 'shut/IMG_0002.jpg');
    final bytes = original.readAsBytesSync();
    Process.runSync('chmod', ['555', shut.path]);
    addTearDown(() => Process.runSync('chmod', ['755', shut.path]));
    final asked = <(String, String)>[];
    Future<ThumbnailItem?> save(String? answer) => saveCopy(
      item(original),
      const Edit().rotated(),
      null,
      ask: (name, folder) async {
        asked.add((name, folder));
        return answer;
      },
    );
    final copy = await save('${folder.path}/mine.jpg');
    expect(asked, [('IMG_0002_edit.jpg', shut.path)]);
    expect(copy?.uri, Uri.file('${folder.path}/mine.jpg'));
    final exif = img.decodeJpgExif(File.fromUri(copy!.uri).readAsBytesSync());
    expect(exif!.imageIfd.orientation, 8);
    expect(await save(null), isNull);
    await expectLater(save(original.path), throwsA(isA<FileSystemException>()));
    expect(original.readAsBytesSync(), bytes);
    expect(shut.listSync().map((f) => f.uri.pathSegments.last), [
      'IMG_0002.jpg',
    ]);
  });

  test('what the copy shows is told, which a lossless crop moves onto the '
      'JPEG block grid (ADR-0389)', () async {
    final original = photo('stills/gps-sydney.jpg', 'IMG_0005.jpg');
    final told = <(String, Rect?)>[];
    Future<void> save(Edit edit) => saveCopy(
      item(original),
      edit,
      null,
      written: (copy, crop) async =>
          told.add((copy.uri.pathSegments.last, crop)),
    ).then((_) {});
    // gps-sydney is 640 x 480 in 16-pixel blocks: a crop from (21, 37) of
    // 300 x 200 shows from (16, 32), 305 x 205.
    await save(
      const Edit().cropped(
        const Rect.fromLTWH(21 / 640, 37 / 480, 300 / 640, 200 / 480),
      ),
    );
    await save(const Edit().rotated());
    expect(told, [
      ('IMG_0005_edit.jpg', const Rect.fromLTWH(16, 32, 305, 205)),
      ('IMG_0005_edit-2.jpg', null),
    ]);
  });

  test('a copy that cannot be written leaves nothing behind', () async {
    final original = photo('stills/gps-sydney.jpg', 'IMG_0003.jpg');
    // Where the copy is written first, taken.
    Directory('${folder.path}/.IMG_0003_edit.jpg.part').createSync();
    await expectLater(
      saveCopy(item(original), const Edit().rotated(), null),
      throwsA(isA<FileSystemException>()),
    );
    expect(folder.listSync().map((f) => f.path.split('/').last).toSet(), {
      'IMG_0003.jpg',
      '.IMG_0003_edit.jpg.part',
    });
  });

  test('a copy that does not decode is not saved', () async {
    final original = photo('stills/gps-sydney.jpg', 'IMG_0004.jpg');
    final copy = await editCopyOf(
      original.readAsBytesSync(),
      const Edit().rotated(),
      null,
    );
    // Its metadata whole, half its image data.
    final cut = copy.sublist(0, copy.length - (copy.length - _scan(copy)) ~/ 2);
    final media = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('org.photolib/viewer'), (
          call,
        ) async {
          media.add(call);
          return 'content://media/external/images/media/8';
        });
    final stored = ThumbnailItem('m', Uri.parse('content://media/x/7'));
    for (final item in [item(original), stored]) {
      await expectLater(writeCopy(item, cut), throwsA(anything));
    }
    expect(folder.listSync().map((f) => f.uri.pathSegments.last), [
      'IMG_0004.jpg',
    ]);
    expect(media, isEmpty);
    expect(await writeCopy(item(original), copy), isNotNull);
    expect(await writeCopy(stored, copy), isNotNull);
    expect(media.single.arguments, ['content://media/x/7', copy]);
  });

  test('a failed edit leaves nothing behind', () async {
    final broken = File('${folder.path}/broken.jpg')
      ..writeAsBytesSync(Uint8List.fromList([0xff, 0xd8, 0, 0]));
    await expectLater(
      saveCopy(item(broken), const Edit().rotated(), null),
      throwsA(anything),
    );
    expect(folder.listSync().map((f) => f.uri.pathSegments.last), [
      'broken.jpg',
    ]);
  });
}

/// Where [jpeg]'s image data starts.
int _scan(Uint8List jpeg) {
  for (var i = 2; ; i++) {
    if (jpeg[i] == 0xff && jpeg[i + 1] == 0xda) return i;
  }
}
