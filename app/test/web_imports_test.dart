import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The `dart.library.<name>` conditions the web compilers hold true.
const _web = {'js_interop', 'js_interop_unsafe', 'js_util', 'js', 'html', 'ui'};
final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]([^;]*);''',
  multiLine: true,
);
final _condition = RegExp(
  r'''if\s*\(\s*dart\.library\.(\w+)\s*\)\s*['"]([^'"]+)['"]''',
);

void main() {
  // dart:ffi fails dart2js and dart2wasm, which only tools/web_requests.py
  // runs: native code stays behind conditional imports (core/kernel.dart).
  test('the web build of lib/main.dart reaches no dart:ffi', () {
    final config = File('.dart_tool/package_config.json').absolute;
    final {'packages': packages as List<Object?>} =
        jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    final roots = {
      for (final {
            'name': name as String,
            'rootUri': root as String,
            'packageUri': lib as String,
          }
          in packages.cast<Map<String, Object?>>())
        name: config.uri
            .resolve(root.endsWith('/') ? root : '$root/')
            .resolve(lib),
    };
    final main = Uri.parse('package:photolib/main.dart');
    final by = <Uri, Uri?>{main: null};
    final queue = [main];
    for (var i = 0; i < queue.length; i++) {
      final library = queue[i];
      if (library.isScheme('dart')) continue;
      final [name, ...path] = library.pathSegments;
      final source = File.fromUri(roots[name]!.resolve(path.join('/')));
      for (final d in _directive.allMatches(source.readAsStringSync())) {
        final web = _condition
            .allMatches(d[2]!)
            .where((c) => _web.contains(c[1]))
            .firstOrNull;
        final next = library.resolve(web?[2] ?? d[1]!);
        if (by.containsKey(next)) continue;
        by[next] = library;
        queue.add(next);
      }
    }
    expect(by, contains(Uri.parse('package:photolib/core/kernel_web.dart')));
    expect([
      for (Uri? at = Uri.parse('dart:ffi'); by.containsKey(at); at = by[at])
        '$at',
    ], isEmpty);
  });
}
