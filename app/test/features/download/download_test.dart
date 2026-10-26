import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/download/download.dart';
import 'package:photolib/features/download/download_action.dart';
import 'package:photolib/features/download/download_io.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/settings/settings.dart';

import '../../support/pump_app.dart';

Download item(String name, List<List<int>> chunks, {List<int>? edit}) =>
    Download(
      name,
      () async =>
          DownloadFile(Stream.fromIterable(chunks), modified: DateTime(2024)),
      edited: edit == null
          ? null
          : () async =>
                DownloadFile(Stream.value(edit), modified: DateTime(2024)),
    );

/// A save dialog that saves in [folder], whichever it opens in.
class _Dialog extends FileSelectorPlatform {
  new(this.folder);

  final String folder;
  final opened = <String?>[];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    opened.add(options.initialDirectory);
    return FileSaveLocation('$folder/${options.suggestedName}');
  }
}

const _unzip =
    'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); '
    'print([(n, z.read(n).decode()) for n in z.namelist()])';

void main() {
  late Directory dir;
  late FileDestination to;
  final asked = <(String, String?)>[];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('download');
    asked.clear();
    String? last;
    to = FileDestination(
      (name, folder) async {
        asked.add((name, folder));
        return '${dir.path}/$name';
      },
      folder: () async => last,
      chosen: (folder) => last = folder,
    );
  });
  tearDown(() => dir.delete(recursive: true));

  // Each entry of the zip at [path], as python3's zipfile reads it, with its
  // text.
  Future<String> unzip(String path) async =>
      ((await Process.run('python3', ['-c', _unzip, path])).stdout as String)
          .trim();

  List<String> files() =>
      [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();

  test('one item saves under its original name where the user chose, where '
      'the next dialog opens', () async {
    final job = DownloadJob(1);
    expect(
      await job.save(
        to,
        Stream.value(
          item('IMG_0001.JPG', [
            [1, 2],
            [3],
          ]),
        ),
      ),
      'IMG_0001.JPG',
    );
    expect(File('${dir.path}/IMG_0001.JPG').readAsBytesSync(), [1, 2, 3]);
    await DownloadJob(1).save(
      to,
      Stream.value(
        item('b.png', [
          [4],
        ]),
      ),
    );
    expect(asked, [('IMG_0001.JPG', null), ('b.png', dir.path)]);
    expect(files(), ['IMG_0001.JPG', 'b.png']);
  });

  test('a file saved and the entries of a zip carry the time each was '
      'taken as their modified time', () async {
    final taken = DateTime(2019, 7, 14, 9, 30, 12);
    Download dated(String name) => Download(
      name,
      () async => DownloadFile(Stream.value([1]), modified: taken),
    );
    await DownloadJob(1).save(to, Stream.value(dated('a.jpg')));
    expect(File('${dir.path}/a.jpg').lastModifiedSync(), taken);
    await DownloadJob(2).save(
      to,
      Stream.fromIterable([dated('b.jpg'), dated('c.jpg')]),
      archive: 'x.zip',
    );
    const dates =
        'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); '
        'print([i.date_time for i in z.infolist()])';
    final read = await Process.run('python3', [
      '-c',
      dates,
      '${dir.path}/x.zip',
    ]);
    expect(
      (read.stdout as String).trim(),
      '[(2019, 7, 14, 9, 30, 12), (2019, 7, 14, 9, 30, 12)]',
    );
  });

  test("an item's file downloads as of when it was taken, else as of its "
      'last change', () async {
    final file = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    final taken = DateTime.utc(2019, 7, 14);
    for (final (at, modified) in [
      (taken, taken),
      (null, file.lastModifiedSync()),
    ]) {
      final item = ThumbnailItem('k', file.uri, taken: at);
      expect((await downloadOf(item)!.original()).modified, modified);
    }
  });

  test('several items save as one zip of their original names, a repeated '
      'name numbered, none a path out of the folder it unzips into', () async {
    final job = DownloadJob(4);
    final progress = <double?>[];
    job.addListener(() => progress.add(job.value));
    final name = await job.save(
      to,
      Stream.fromIterable([
        item('IMG_0001.JPG', [utf8.encode('a')]),
        item('IMG_0001.JPG', [utf8.encode('b')]),
        item('clip', [utf8.encode('c')]),
        item(r'..\..\x.jpg', [utf8.encode('d')]),
      ]),
      archive: 'Photolib.zip',
    );
    expect(name, 'Photolib.zip');
    expect(
      await unzip('${dir.path}/Photolib.zip'),
      "[('IMG_0001.JPG', 'a'), ('IMG_0001 (2).JPG', 'b'), ('clip', 'c'), "
      "('.._.._x.jpg', 'd')]",
    );
    expect(progress.last, 1);
    expect(progress, orderedEquals([...progress]..sort()));
  });

  test('items of albums zip into a folder each, a repeated name numbered '
      'within its folder, no folder a path out of the archive', () async {
    Download inAlbum(String folder, String name) => Download(
      name,
      () async => DownloadFile(
        Stream.value(utf8.encode(folder)),
        modified: DateTime(2024),
      ),
      folder: folder,
    );
    await DownloadJob(5).save(
      to,
      Stream.fromIterable([
        inAlbum('Trip', 'a.jpg'),
        inAlbum('Trip', 'A.jpg'),
        inAlbum('Home', 'a.jpg'),
        inAlbum('..', 'b.jpg'),
        inAlbum('x/../y', 'c.jpg'),
      ]),
      archive: 'Photolib.zip',
    );
    expect(
      await unzip('${dir.path}/Photolib.zip'),
      "[('Trip/a.jpg', 'Trip'), ('Trip/A (2).jpg', 'Trip'), "
      "('Home/a.jpg', 'Home'), ('_/b.jpg', '..'), "
      "('x_.._y/c.jpg', 'x/../y')]",
    );
  });

  test('the current version by default, the original when asked', () async {
    final edited = item(
      'a.jpg',
      [
        [1],
      ],
      edit: [2],
    );
    await DownloadJob(1).save(to, Stream.value(edited));
    expect(File('${dir.path}/a.jpg').readAsBytesSync(), [2]);
    await DownloadJob(1).save(to, Stream.value(edited), original: true);
    expect(File('${dir.path}/a.jpg').readAsBytesSync(), [1]);
  });

  test('the edited file is saved under its own name, the original under its '
      'own', () async {
    final edited = Download(
      'a.heic',
      () async => DownloadFile(Stream.value([1]), modified: DateTime(2020)),
      edited: () async =>
          DownloadFile(Stream.value([2]), modified: DateTime(2020)),
      editedName: 'a_edit.jpg',
    );
    await DownloadJob(1).save(to, Stream.value(edited));
    expect(File('${dir.path}/a_edit.jpg').readAsBytesSync(), [2]);
    await DownloadJob(1).save(to, Stream.value(edited), original: true);
    expect(File('${dir.path}/a.heic').readAsBytesSync(), [1]);
    await DownloadJob(2).save(to, Stream.value(edited), archive: 'x.zip');
    expect(
      File('${dir.path}/x.zip').readAsBytesSync(),
      containsAll('a_edit.jpg'.codeUnits),
    );
  });

  test('cancelled while its source stalls, a download stops and leaves no '
      'file', () async {
    final source = StreamController<List<int>>();
    final job = DownloadJob(1);
    final saving = job.save(
      to,
      Stream.value(
        Download(
          'big.mov',
          () async => DownloadFile(source.stream, modified: DateTime(2024)),
        ),
      ),
    );
    source.add(List.filled(1000, 7));
    // The file opens on the I/O thread, in its own time.
    while (files().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(files(), ['big.mov'], reason: 'under way');
    job.cancel();
    await expectLater(saving, throwsA(isA<DownloadCancelled>()));
    expect(files(), isEmpty);
    expect(source.hasListener, isFalse, reason: 'the source is let go');
  });

  test('a source that fails leaves no file either', () async {
    await expectLater(
      DownloadJob(2).save(
        to,
        Stream.fromIterable([
          item('a.jpg', [
            [1],
          ]),
          Download(
            'b.jpg',
            () async => throw const FileSystemException('gone'),
          ),
        ]),
        archive: 'x.zip',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(files(), isEmpty);
  });

  test("the folder chosen last persists with the settings: the next run's "
      'dialog opens there', () async {
    final platform = FileSelectorPlatform.instance;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      FileSelectorPlatform.instance = platform;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final dialog = _Dialog(dir.path);
    FileSelectorPlatform.instance = dialog;
    final settings = MemoryStore();
    for (final name in ['a.jpg', 'b.jpg']) {
      final run = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(settings)],
      );
      await run.read(destinationProvider)!.save(name, Stream.value([1]));
      run.dispose();
    }
    expect(dialog.opened, [null, dir.path]);
    expect(files(), ['a.jpg', 'b.jpg']);
  });

  test('a dismissed dialog writes nothing', () async {
    final none = FileDestination(
      (_, _) async => null,
      folder: () async => null,
      chosen: (_) => fail('nothing was chosen'),
    );
    expect(
      await DownloadJob(1).save(
        none,
        Stream.value(
          item('a', [
            [1],
          ]),
        ),
      ),
      isNull,
    );
    expect(files(), isEmpty);
  });

  test('reveals a file in the freedesktop file manager, else its folder, or '
      'in Explorer', () async {
    final ran = <String>[];
    Future<ProcessResult> run(String command, List<String> arguments) async {
      ran.add([command, ...arguments].join(' '));
      return ProcessResult(0, command == 'dbus-send' ? 1 : 0, '', '');
    }

    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await reveal('/p/a,b.jpg', run: run);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await reveal(r'C:\p\a.jpg', run: run);
    expect(ran, [
      'dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 '
          '/org/freedesktop/FileManager1 '
          'org.freedesktop.FileManager1.ShowItems '
          'array:string:file:///p/a%2Cb.jpg string:',
      'xdg-open /p',
      r'explorer.exe /select, C:\p\a.jpg',
    ]);
  });
}
