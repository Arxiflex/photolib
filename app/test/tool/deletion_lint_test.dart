import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/deletion_lint.dart';

List<String> rules(String path, String source) =>
    lintFile(path, source).map((v) => v.rule).toList();

void main() {
  test('platform delete calls outside the DeletionService are flagged', () {
    for (final (path, line) in [
      ('lib/features/viewer/viewer_page.dart', 'await File(p).delete();'),
      ('lib/core/a.dart', 'await dir.delete(recursive: true);'),
      ('packages/photolib_data/lib/src/a.dart', 'File(p).deleteSync();'),
      ('lib/a.dart', 'await handle.removeEntry(name).toDart;'),
      ('lib/a.dart', 'await handle.remove().toDart;'),
      ('lib/a.dart', "await Process.run('rm', [path]);"),
      ('lib/a.dart', "await Process.run('gio', ['trash', path]);"),
      (
        'android/app/src/main/kotlin/a/Gallery.kt',
        'MediaStore.createDeleteRequest(resolver, uris)',
      ),
      (
        'android/app/src/main/kotlin/a/Gallery.kt',
        'MediaStore.createTrashRequest(resolver, uris, true)',
      ),
      ('android/app/src/main/kotlin/a/G.kt', 'resolver.delete(uri, null)'),
      ('android/app/src/main/kotlin/a/G.kt', 'File(path).delete()'),
      ('ios/Runner/A.swift', 'PHAssetChangeRequest.deleteAssets(assets)'),
      (
        'macos/Runner/A.swift',
        'try files.trashItem(at: url, resultingItemURL: nil)',
      ),
      ('macos/Runner/A.swift', 'NSWorkspace.shared.recycle(urls)'),
      ('ios/Runner/A.swift', 'try? FileManager.default.removeItem(at: url)'),
      ('windows/runner/a.cpp', 'SHFileOperationW(&op);'),
      ('windows/runner/a.cpp', 'DeleteFileW(path.c_str());'),
      ('linux/runner/a.cc', 'g_file_trash(file, nullptr, &error);'),
      ('linux/runner/a.cc', 'unlink(path);'),
    ]) {
      expect(rules(path, line), ['platform-delete'], reason: '$path: $line');
    }
  });

  test('the DeletionService and its platform halves may delete', () {
    for (final (path, line) in [
      ('packages/photolib_data/lib/src/deletion.dart', 'File(p).delete();'),
      ('packages/photolib_data/lib/src/trash_native.dart', 'f.delete();'),
      (
        'packages/photolib_data/lib/src/trash_web.dart',
        'await dir.removeEntry(name).toDart;',
      ),
      (
        'android/app/src/main/kotlin/org/photolib/photolib/MediaRequests.kt',
        'MediaStore.createDeleteRequest(resolver, uris)',
      ),
      (
        'ios/Runner/MediaRequests.swift',
        'PHAssetChangeRequest.deleteAssets(a)',
      ),
      ('macos/Runner/MediaRequests.swift', 'try files.removeItem(atPath: p)'),
    ]) {
      expect(rules(path, line), isEmpty, reason: path);
    }
  });

  test("an app's own file deletes say why, and tests are not checked", () {
    expect(
      rules(
        'lib/features/library/timeline/disk_cache.dart',
        "// deletion-ok: a tile of the cache, which is the app's own\n"
            'await file.delete();',
      ),
      isEmpty,
    );
    expect(
      rules('lib/a.dart', 'await file.delete(); // deletion-ok: a temp file'),
      isEmpty,
    );
    expect(rules('lib/a.dart', 'await file.delete(); // deletion-ok:'), [
      'platform-delete',
    ], reason: 'a reason is needed');
    expect(
      rules(
        'lib/a.dart',
        '// deletion-ok: the cache\nawait root\n    .removeEntry(n).toDart;',
      ),
      isEmpty,
    );
    expect(
      rules('lib/a.dart', '// deletion-ok: no\nf();\nawait file.delete();'),
      ['platform-delete'],
      reason: 'only for its own statement',
    );
    expect(rules('test/a_test.dart', 'await file.delete();'), isEmpty);
    expect(
      rules('ios/RunnerTests/A.swift', 'try fm.removeItem(at: u)'),
      isEmpty,
    );
  });

  test('what is not a delete call is not flagged', () {
    for (final (path, line) in [
      ('lib/a.dart', 'await (db.delete(db.localAsset)..where(w)).go();'),
      ('lib/a.dart', 'map.remove(key);'),
      ('android/app/src/main/kotlin/a/V.kt', 'bitmap.recycle()'),
      ('android/app/src/main/kotlin/a/V.kt', 'signals.remove(id)'),
    ]) {
      expect(rules(path, line), isEmpty, reason: line);
    }
  });

  test('reports the file, the line and what to do instead', () {
    expect(
      lintFile(
        'lib/a.dart',
        'void f() {}\nFile(p).deleteSync();\n',
      ).single.toString(),
      startsWith('lib/a.dart:2: platform-delete'),
    );
  });

  test('every deletion of the app goes through the DeletionService', () {
    expect(lintTree(Directory('.')).map((v) => '$v'), isEmpty);
  });
}
