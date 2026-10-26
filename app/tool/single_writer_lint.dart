/// The single-writer architecture test (docs/10-client-app.md §1.5): one
/// Flutter engine per process, and one database writer, the data isolate of
/// `photolib_data`. Native code, extensions included, never opens a database:
/// it appends to journals that the data isolate merges. Every store opens
/// through the vault, the key provider (ADR-0057): only it calls the openers,
/// and they key what they open, or say why not with `// unkeyed-ok: <reason>`.
/// Run from `app/` by `flutter test`; a new engine host or opener is a design
/// change, made here.
library;

import 'dart:io';

import 'root_isolate_lint.dart' show Violation;

/// The files that host the process's one engine, one per platform.
const _engineHosts = {
  'android/app/src/main/kotlin/org/photolib/photolib/MainActivity.kt',
  'ios/Runner/SceneDelegate.swift',
  'macos/Runner/MainFlutterWindow.swift',
  'windows/runner/flutter_window.cpp',
  'linux/runner/my_application.cc',
};

/// Android's one engine, which the application makes before any activity
/// exists so that WorkManager's jobs run in it too (design 10 §1.5).
const _engineMaker =
    'android/app/src/main/kotlin/org/photolib/photolib/PhotolibApplication.kt';

/// The files that open the replica: the data isolate, and drift's web worker.
const _openers = {
  'packages/photolib_data/lib/src/open_native.dart',
  'packages/photolib_data/lib/src/open_web.dart',
  'packages/photolib_data/web/drift_worker.dart',
};

/// Packages that run Dart in an engine of their own, or bring another engine
/// for the database.
const _enginePackages = {
  'workmanager',
  'flutter_background_service',
  'android_alarm_manager_plus',
  'background_fetch',
  'flutter_isolate',
};
const _databasePackages = {
  'sqflite',
  'sqflite_common_ffi',
  'sqlite3_flutter_libs',
  'sqlcipher_flutter_libs',
  'sqlite_async',
  'isar',
  'hive',
  'objectbox',
  'realm',
};

final _native = RegExp(r'\.(kt|java|swift|m|mm|cc|cpp)$');
final _newEngine = RegExp(
  r'\bFlutterEngine(Group|Cache)?\s*\(|FlutterEngine\s+alloc|FlutterEngineGroup|'
  r'flutter::FlutterEngine\b|fl_engine_new|executeDartCallback|'
  'FlutterCallbackInformation',
);
final _engineHost = RegExp(
  r'\bFlutter(Fragment)?Activity\b|\bFlutterFragment\b|FlutterSceneDelegate|'
  r'FlutterViewController\s*>?\s*\(|fl_view_new',
);
final _nativeDatabase = RegExp(
  r'sqlite3_open|import\s+(SQLite3|SQLite|GRDB|CoreData)\b|SQLiteDatabase|'
  r'SQLiteOpenHelper|androidx\.room|NSPersistentContainer|FMDatabase',
);
final _dartDatabase = RegExp(
  r'\bNativeDatabase\b|\bWasmDatabase\b|DriftIsolate\.(spawn|inCurrent)|'
  r'\bsqlite3\.open|\bWasmSqlite3\b|\bdriftDatabase\(|\bopenDatabase\(',
);

/// The key provider, the one caller of the openers.
const _vault = 'packages/photolib_data/lib/src/vault.dart';
final _storeOpen = RegExp(
  r'\bNativeDatabase\(|\bWasmDatabase(\.open)?\(|\bsqlite3\.open\(',
);
final _keyed = RegExp(r'\bkeying\(|multipleciphers-');
final _unkeyedOk = RegExp(r'//\s*unkeyed-ok:\s*\S');
final _opener = RegExp(r'\b(openKeyed|keyedConnection|rekeyPlaintext)\(');
final _storeInternals = RegExp('package:photolib_data/src/');

/// The one place that opens the replica; every other isolate uses its
/// connection, since a second call from another isolate spawns a second writer.
const _replicaProvider = 'lib/core/replica.dart';
final _openReplica = RegExp(r'\bopenReplica\(');
final _lockEntry = RegExp(r'^  ([a-z0-9_]+):$');
final _sqlite3mc = RegExp(
  r'^hooks:\s*\n\s+user_defines:\s*\n\s+sqlite3:\s*\n\s+source:\s*sqlite3mc\s*$',
  multiLine: true,
);

/// The violations in one file at [path], relative to `app/`. A pubspec.lock is
/// checked with the [pubspec] next to it.
List<Violation> lintFile(String path, String source, {String pubspec = ''}) {
  final segments = path.split('/');
  final lines = source.split('\n');
  final found = <Violation>[];
  void flag(int i, String rule, String advice) =>
      found.add(Violation(path, i + 1, rule, advice));

  if (segments.last == 'pubspec.lock') {
    for (var i = 0; i < lines.length; i++) {
      final name = _lockEntry.firstMatch(lines[i])?.group(1);
      if (_enginePackages.contains(name)) {
        flag(i, 'second-engine', '$name runs Dart in an engine of its own');
      } else if (_databasePackages.contains(name)) {
        flag(i, 'second-writer', '$name opens databases outside photolib_data');
      } else if (name == 'sqlite3' && !_sqlite3mc.hasMatch(pubspec)) {
        flag(
          i,
          'second-engine',
          'SQLite must be SQLite3MultipleCiphers: set '
              'hooks.user_defines.sqlite3.source to sqlite3mc in pubspec.yaml',
        );
      }
    }
    return found;
  }
  final native = _native.hasMatch(path);
  final dartSource =
      path.endsWith('.dart') &&
      (segments.contains('lib') || segments.contains('web')) &&
      !segments.any(const {'test', 'integration_test'}.contains);
  final opener = _openers.contains(path);
  final dart = dartSource && !opener;
  final ownLib = path.startsWith('packages/photolib_data/');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (opener && _storeOpen.hasMatch(line)) {
      final end = lines.indexWhere((l) => l.contains(';'), i);
      final statement = lines.sublist(i, end < 0 ? null : end + 1).join('\n');
      if (!_keyed.hasMatch(statement) &&
          !_unkeyedOk.hasMatch(line) &&
          !(i > 0 && _unkeyedOk.hasMatch(lines[i - 1]))) {
        flag(i, 'unkeyed-store', 'key it from the vault: keying(key)');
      }
    } else if (dart && !ownLib && _storeInternals.hasMatch(line)) {
      flag(i, 'unkeyed-store', 'open stores through the Vault');
    } else if (dart && path != _vault && _opener.hasMatch(line)) {
      flag(i, 'unkeyed-store', 'open stores through the Vault');
    } else if (native && path != _engineMaker && _newEngine.hasMatch(line)) {
      flag(i, 'second-engine', 'attach to the process engine instead');
    } else if (native &&
        _engineHost.hasMatch(line) &&
        !_engineHosts.contains(path)) {
      flag(i, 'second-engine', 'only the runner hosts the Flutter engine');
    } else if (native && _nativeDatabase.hasMatch(line)) {
      flag(i, 'second-writer', 'append to a journal for the data isolate');
    } else if (dart && _dartDatabase.hasMatch(line)) {
      flag(i, 'second-writer', 'use the replica from openReplica');
    } else if (dart &&
        _openReplica.hasMatch(line) &&
        path != _replicaProvider &&
        path != _vault) {
      flag(i, 'second-writer', 'use replicaProvider or computeWithDatabase');
    }
  }
  return found;
}

/// The violations under [root], the app, skipping build output and caches.
List<Violation> lintTree(Directory root) {
  final prefix = root.path.length + 1;
  return [
    for (final file in _files(root))
      if (_native.hasMatch(file.path) ||
          file.path.endsWith('.dart') ||
          file.path.endsWith('/pubspec.lock'))
        ...lintFile(
          file.path.substring(prefix),
          file.readAsStringSync(),
          pubspec: file.path.endsWith('/pubspec.lock')
              ? File('${file.parent.path}/pubspec.yaml').readAsStringSync()
              : '',
        ),
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
