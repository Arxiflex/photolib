@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  final vectors = jsonDecode(
    File('../../../testdata/photolibignore.json').readAsStringSync(),
  );
  for (final c in vectors['cases']) {
    test(c['name'], () {
      final files = (c['rules'] as Map).cast<String, String>();

      bool ignored(String path) {
        final parts = path.split('/');
        var rules = IgnoreRules.defaults(
          caseSensitive: c['caseSensitive'] ?? true,
        ).add('', files[''] ?? '');
        for (var i = 0; i < parts.length && parts[i].isNotEmpty; i++) {
          final at = parts.take(i + 1).join('/');
          final dir = i < parts.length - 1;
          if (rules.ignores(at, dir: dir)) return true;
          if (dir) rules = rules.add(at, files[at] ?? '');
        }
        return false;
      }

      for (final path in c['ignored']) {
        expect(ignored(path), isTrue, reason: '$path is ignored');
      }
      for (final path in c['kept']) {
        expect(ignored(path), isFalse, reason: '$path is kept');
      }
    });
  }
}
