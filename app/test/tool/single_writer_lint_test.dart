import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/single_writer_lint.dart';

List<String> rules(String path, String source) =>
    lintFile(path, source).map((v) => v.rule).toList();

void main() {
  group('a second Flutter engine', () {
    test('is flagged when native code starts one', () {
      for (final (path, line) in [
        ('android/app/src/main/kotlin/a/Job.kt', 'val e = FlutterEngine(ctx)'),
        ('android/app/src/main/java/a/Job.java', 'new FlutterEngineGroup(c);'),
        ('ios/Runner/Bg.swift', 'let e = FlutterEngine(name: "bg")'),
        ('ios/Runner/Bg.m', 'e = [[FlutterEngine alloc] initWithName:@"b"];'),
        (
          'android/app/src/main/kotlin/a/B.kt',
          'executor.executeDartCallback(cb)',
        ),
        ('windows/runner/b.cpp', 'auto e = flutter::FlutterEngine(project);'),
        ('linux/runner/b.cc', 'FlEngine* e = fl_engine_new(project);'),
      ]) {
        expect(rules(path, line), ['second-engine'], reason: path);
      }
    });

    test('is flagged when another screen hosts one', () {
      expect(
        rules(
          'android/app/src/main/kotlin/a/ShareActivity.kt',
          'class ShareActivity : FlutterActivity()',
        ),
        ['second-engine'],
      );
      expect(
        rules('macos/Runner/Other.swift', 'let c = FlutterViewController()'),
        ['second-engine'],
      );
    });

    test("is not Android's one engine, which the application makes before any "
        'activity, to run in the background too (design 10 §1.5)', () {
      expect(
        rules(
          'android/app/src/main/kotlin/org/photolib/photolib/'
              'PhotolibApplication.kt',
          'val engine = FlutterEngine(application)',
        ),
        isEmpty,
      );
    });

    test('is not the runners that host the one engine', () {
      expect(
        rules(
          'android/app/src/main/kotlin/org/photolib/photolib/MainActivity.kt',
          'class MainActivity : FlutterActivity()',
        ),
        isEmpty,
      );
      expect(
        rules(
          'windows/runner/flutter_window.cpp',
          'c = std::make_unique<flutter::FlutterViewController>(w, h, p);',
        ),
        isEmpty,
      );
    });

    test('is flagged when a plugin brings its own background engine', () {
      expect(rules('pubspec.lock', '  workmanager:\n'), ['second-engine']);
      expect(
        rules('packages/a/pubspec.lock', '  flutter_background_service:\n'),
        ['second-engine'],
      );
    });
  });

  group('a second database writer', () {
    test(
      'is flagged when Dart code opens a database outside the data isolate',
      () {
        for (final line in [
          'final db = NativeDatabase(file);',
          'final db = NativeDatabase.createInBackground(file);',
          'final i = await DriftIsolate.spawn(open);',
          'final db = sqlite3.open(path);',
          'final r = await WasmDatabase.open(databaseName: n);',
        ]) {
          expect(rules('lib/core/db.dart', line), [
            'second-writer',
          ], reason: line);
        }
        expect(
          rules('packages/photolib_ui/lib/a.dart', 'NativeDatabase.memory()'),
          ['second-writer'],
        );
      },
    );

    test('is flagged when the replica is opened outside its provider', () {
      const call = 'final db = await openReplica(dir);';
      expect(rules('lib/features/a.dart', call), ['second-writer']);
      expect(rules('packages/photolib_ui/lib/a.dart', call), ['second-writer']);
      expect(rules('lib/core/replica.dart', call), isEmpty);
    });

    test('is not the data isolate that opens the replica, nor a test', () {
      const opener = 'packages/photolib_data/lib/src/open_native.dart';
      expect(
        rules(opener, 'NativeDatabase(File(p)).interceptWith(keying(k))'),
        isEmpty,
      );
      expect(
        rules(
          'packages/photolib_data/test/a_test.dart',
          'NativeDatabase.memory()',
        ),
        isEmpty,
      );
    });

    test(
      'is flagged when native code, extensions included, opens a database',
      () {
        for (final (path, line) in [
          ('ios/ShareExtension/Store.swift', 'import GRDB'),
          ('ios/ShareExtension/Store.m', 'sqlite3_open(path, &db);'),
          (
            'android/app/src/main/kotlin/a/Db.kt',
            'class Db : SQLiteOpenHelper(c, n, null, 1)',
          ),
          ('android/app/src/main/kotlin/a/Dao.kt', 'import androidx.room.Dao'),
        ]) {
          expect(rules(path, line), ['second-writer'], reason: path);
        }
      },
    );

    test('is flagged when a package brings another database engine', () {
      expect(rules('pubspec.lock', '  sqflite:\n'), ['second-writer']);
    });

    test('is flagged when SQLite is not SQLite3MultipleCiphers', () {
      const lock = '  sqlite3:\n    dependency: transitive\n';
      expect(rules('pubspec.lock', lock), ['second-engine']);
      expect(
        lintFile(
          'pubspec.lock',
          lock,
          pubspec:
              'hooks:\n  user_defines:\n    sqlite3:\n'
              '      source: sqlite3mc\n',
        ),
        isEmpty,
      );
    });
  });

  group('a store opened without the key provider', () {
    const native = 'packages/photolib_data/lib/src/open_native.dart';
    const worker = 'packages/photolib_data/web/drift_worker.dart';

    test('is flagged when an opener does not key what it opens', () {
      expect(rules(native, 'final e = NativeDatabase(File(p));'), [
        'unkeyed-store',
      ]);
      expect(rules(worker, "final db = sqlite3.open('/database');"), [
        'unkeyed-store',
      ]);
      expect(
        rules(
          native,
          'NativeDatabase(\n  File(p),\n).interceptWith(keying(k));',
        ),
        isEmpty,
      );
      expect(
        rules(worker, r"sqlite3.open('/d', vfs: 'multipleciphers-${v.name}');"),
        isEmpty,
      );
      expect(
        rules(native, '// unkeyed-ok: a plaintext copy\nsqlite3.open(p);'),
        isEmpty,
      );
    });

    test('is flagged when anything but the vault calls an opener', () {
      for (final line in [
        'final db = await openKeyed(dir, name, key);',
        'Replica(keyedConnection(url, name, key));',
        'await rekeyPlaintext(a, b, c, k);',
      ]) {
        expect(rules('lib/core/replica.dart', line), [
          'unkeyed-store',
        ], reason: line);
      }
      expect(
        rules(
          'packages/photolib_data/lib/src/vault.dart',
          'final db = await openKeyed(location, name, key);',
        ),
        isEmpty,
      );
    });

    test('is flagged when code reaches into the store past the vault', () {
      const line = "import 'package:photolib_data/src/open_native.dart';";
      expect(rules('lib/core/replica.dart', line), ['unkeyed-store']);
      expect(rules('packages/photolib_ui/lib/a.dart', line), ['unkeyed-store']);
      expect(rules('integration_test/app_test.dart', line), isEmpty);
      // Its own files and workers, whose analysis options require package
      // imports.
      expect(rules('packages/photolib_data/lib/src/sync.dart', line), isEmpty);
      expect(rules('packages/photolib_data/lib/testing.dart', line), isEmpty);
      expect(rules('packages/photolib_data/web/a_worker.dart', line), isEmpty);
    });
  });

  test('reports the file, the line and what to do instead', () {
    final found = lintFile(
      'lib/a.dart',
      'void f() {}\nNativeDatabase.memory();\n',
    );
    expect(found.single.toString(), startsWith('lib/a.dart:2: second-writer'));
  });

  test('the app has one engine per process and one database writer', () {
    expect(lintTree(Directory('.')).map((v) => '$v'), isEmpty);
  });
}
