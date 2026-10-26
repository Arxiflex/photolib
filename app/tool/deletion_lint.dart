/// One deletion path (docs/10-client-app.md §5.4, ADR-0245): every device item
/// is deleted by photolib_data's DeletionService, which calls the platform's
/// trash or delete through the files below and nowhere else. A call that
/// deletes a file the app made itself (a cache tile, a temporary file) says so
/// with `// deletion-ok: <reason>` in or just above its statement. Run from
/// `app/` by `flutter test`.
library;

import 'dart:io';

import 'root_isolate_lint.dart' show Violation;

/// The DeletionService and its platform halves.
const _service = {
  'packages/photolib_data/lib/src/deletion.dart',
  'packages/photolib_data/lib/src/trash_native.dart',
  'packages/photolib_data/lib/src/trash_web.dart',
  'android/app/src/main/kotlin/org/photolib/photolib/MediaRequests.kt',
  'ios/Runner/MediaRequests.swift',
  'macos/Runner/MediaRequests.swift',
};

final _dart = RegExp(
  r'\.delete\(\s*(\)|recursive)|\.deleteSync\(|\bremoveEntry\(|'
  r'\.remove\(\)\.toDart|'
  r"""Process\.(run|start)\(\s*['"](rm|gio|trash-put|kioclient5?)['"]""",
);
final _kotlin = RegExp(
  r'\bcreate(Delete|Trash)Request\(|\b(contentR|r)esolver\.delete\(|'
  r'\.delete(Recursively)?\(\)',
);
final _swift = RegExp(
  r'\bdeleteAssets\(|\btrashItem\(|\brecycle\(|removeItem\(',
);
final _c = RegExp(
  r'SHFileOperation|IFileOperation|\bDeleteFile[AW]?\(|'
  r'\bRemoveDirectory[AW]?\(|\bg_file_(trash|delete)\b|\bunlink\(|'
  'filesystem::remove',
);
final _source = RegExp(r'\.(dart|kt|java|swift|m|mm|c|cc|cpp|h)$');
final _ok = RegExp(r'//\s*deletion-ok:\s*\S');
final _comment = RegExp(r'(^|\s)//.*$');
final _end = RegExp(r'[;{}]\s*$');

/// The violations in one file at [path], relative to `app/`.
List<Violation> lintFile(String path, String source) {
  final segments = path.split('/');
  if (_service.contains(path) ||
      segments.any(
        (s) =>
            const {
              'test',
              'integration_test',
              'benchmark',
              'tool',
            }.contains(s) ||
            s.endsWith('Tests'),
      )) {
    return const [];
  }
  final rule = switch (path.split('.').last) {
    'dart' when segments.contains('lib') || segments.contains('web') => _dart,
    'kt' || 'java' => _kotlin,
    'swift' || 'm' || 'mm' => _swift,
    'c' || 'cc' || 'cpp' || 'h' => _c,
    _ => null,
  };
  if (rule == null) return const [];
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (rule.hasMatch(lines[i].replaceFirst(_comment, '')) &&
          !_excused(lines, i))
        Violation(
          path,
          i + 1,
          'platform-delete',
          "delete through photolib_data's DeletionService, or say why the "
              "file is the app's own: // deletion-ok: <reason>",
        ),
  ];
}

/// Whether the statement at line [i] says why it may delete, on a line of it
/// or just above it.
bool _excused(List<String> lines, int i) {
  for (var j = i; j >= 0 && j >= i - 3; j--) {
    if (_ok.hasMatch(lines[j])) return true;
    if (j < i && _end.hasMatch(lines[j].replaceFirst(_comment, ''))) {
      return false;
    }
  }
  return false;
}

/// The violations under [root], the app, skipping build output and caches.
List<Violation> lintTree(Directory root) {
  final prefix = root.path.length + 1;
  return [
    for (final file in _files(root))
      if (_source.hasMatch(file.path))
        ...lintFile(file.path.substring(prefix), file.readAsStringSync()),
  ];
}

Iterable<File> _files(Directory dir) sync* {
  for (final entry in dir.listSync(followLinks: false)) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entry is File) {
      yield entry;
    } else if (entry is Directory &&
        !name.startsWith('.') &&
        !const {'build', 'Pods', 'ephemeral'}.contains(name)) {
      yield* _files(entry);
    }
  }
}
