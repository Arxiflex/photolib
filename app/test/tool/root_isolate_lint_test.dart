import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/root_isolate_lint.dart';

List<String> rules(String source) =>
    lintSource('lib/a.dart', source).map((v) => v.rule).toList();

void main() {
  group('blocking I/O', () {
    test('flags synchronous file and directory calls', () {
      expect(rules("final bytes = File('a').readAsBytesSync();"), ['sync-io']);
      expect(rules('final entries = dir.listSync(recursive: true);'), [
        'sync-io',
      ]);
      expect(rules('final result = Process.runSync("ls", []);'), ['sync-io']);
    });

    test('flags a tear-off of a synchronous call', () {
      expect(rules('final read = file.readAsStringSync;'), ['sync-io']);
    });

    test('flags sleep, which blocks the isolate', () {
      expect(rules('sleep(const Duration(seconds: 1));'), ['sleep']);
    });

    test('accepts the asynchronous calls', () {
      expect(rules('final bytes = await File(path).readAsBytes();'), isEmpty);
      expect(rules('await Future<void>.delayed(Duration.zero);'), isEmpty);
    });
  });

  group('heavy imports', () {
    test('flags FFI and database packages in UI code', () {
      expect(rules("import 'dart:ffi';"), ['heavy-import']);
      expect(rules("import 'package:ffi/ffi.dart';"), ['heavy-import']);
      expect(rules("import 'package:drift/drift.dart';"), ['heavy-import']);
      expect(rules("export 'package:sqlite3/sqlite3.dart';"), ['heavy-import']);
    });

    test('accepts other imports', () {
      expect(rules("import 'dart:async';"), isEmpty);
      expect(rules("import 'package:go_router/go_router.dart';"), isEmpty);
    });
  });

  group('what is not code', () {
    test('ignores comments and string literals', () {
      expect(rules('// never call readAsBytesSync()'), isEmpty);
      expect(rules("final hint = 'avoid file.readAsBytesSync()';"), isEmpty);
      expect(rules('final x = 1; // sleep(1)'), isEmpty);
    });

    test('still flags code after a string on the same line', () {
      expect(rules("log('a'); file.readAsBytesSync();"), ['sync-io']);
    });
  });

  group('the escape hatch', () {
    test('accepts a reason on the same line or the line above', () {
      expect(
        rules(
          'file.readAsBytesSync(); // root-isolate-ok: 40-byte header at startup',
        ),
        isEmpty,
      );
      expect(
        rules(
          '// root-isolate-ok: 40-byte header at startup\n'
          'file.readAsBytesSync();',
        ),
        isEmpty,
      );
    });

    test('requires a reason', () {
      expect(rules('file.readAsBytesSync(); // root-isolate-ok:'), ['sync-io']);
      expect(rules('file.readAsBytesSync(); // root-isolate-ok'), ['sync-io']);
    });

    test('covers only the line below it', () {
      expect(
        rules(
          '// root-isolate-ok: startup only\n'
          'file.existsSync();\n'
          'file.readAsBytesSync();',
        ),
        ['sync-io'],
      );
    });
  });

  test('reports the file, the line and what to do instead', () {
    final found = lintSource('lib/ui/page.dart', 'void f() {}\nsleep(d);\n');
    expect(found.single.toString(), startsWith('lib/ui/page.dart:2: sleep'));
  });

  test('the app has no blocking work on the root isolate', () {
    expect(lintTree(Directory('lib')).map((v) => '$v'), isEmpty);
  });
}
