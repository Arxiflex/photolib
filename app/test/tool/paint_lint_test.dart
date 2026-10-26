import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/paint_lint.dart';

List<String> rules(String source) =>
    lintSource('lib/a.dart', source).map((v) => v.rule).toList();

void main() {
  test('flags a static Paint, however it is declared', () {
    expect(rules('static final _paint = Paint()..color = c;'), [
      'static-paint',
    ]);
    expect(rules('static final Paint _p = Paint();'), ['static-paint']);
    expect(rules('static late final _p =\n    Paint();'), ['static-paint']);
  });

  test('flags a Paint changed after it is made', () {
    expect(
      rules(
        'final _paint = Paint();\n'
        'void f() => canvas.drawRect(r, _paint..color = c);',
      ),
      ['changed-paint'],
    );
    expect(rules('final paint = Paint();\npaint.strokeWidth = 2;'), [
      'changed-paint',
    ]);
    expect(rules('late final Paint stroke;\nx(stroke\n  ..color = c);'), [
      'changed-paint',
    ]);
  });

  test('accepts a Paint per purpose, set up as it is made', () {
    expect(
      rules(
        'late final _scrim = Paint()..color = Colors.black54;\n'
        'final paint = Paint()\n  ..color = color\n  ..strokeWidth = 1;\n'
        'static Paint _line(Color color) => Paint()..color = color;\n'
        'canvas.drawRect(r, _scrim);\n'
        'style.color = c;',
      ),
      isEmpty,
    );
    expect(rules('// static final _p = Paint();'), isEmpty);
  });

  test('reports the file, the line and what to do instead', () {
    final found = lintSource(
      'lib/a.dart',
      'void f() {}\nstatic var p = Paint();',
    );
    expect(found.single.toString(), startsWith('lib/a.dart:2: static-paint'));
  });

  test('the app and its packages share no Paint and change none', () {
    expect(
      [
        ...lintTree(Directory('lib')),
        for (final package in Directory('packages').listSync())
          if (Directory('${package.path}/lib').existsSync())
            ...lintTree(Directory('${package.path}/lib')),
      ].map((v) => '$v'),
      isEmpty,
    );
  });
}
