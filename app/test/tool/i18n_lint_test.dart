import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/i18n_lint.dart';

List<String> rules(String source) =>
    lintSource('lib/a.dart', source).map((v) => v.rule).toList();

void main() {
  group('hard-coded UI strings', () {
    test('flags text given to a text widget', () {
      expect(rules("Text('Hello')"), ['ui-string']);
      expect(rules('const Text("Hello")'), ['ui-string']);
      expect(rules("SelectableText('Hello')"), ['ui-string']);
      expect(rules("Text(\n  '''Hello''',\n)"), ['ui-string']);
      expect(rules("Text(r'Hello')"), ['ui-string']);
    });

    test('flags text given to a label, tooltip or title', () {
      for (final name in [
        'label',
        'labelText',
        'hintText',
        'semanticLabel',
        'semanticsLabel',
        'tooltip',
        'message',
        'title',
        'text',
      ]) {
        expect(rules("Widget($name: 'Hello')"), ['ui-string'], reason: name);
      }
    });

    test('flags every branch of an expression in that position', () {
      expect(rules("Text(on ? 'On' : 'Off')"), ['ui-string', 'ui-string']);
      expect(rules("Text(name ?? 'Unknown')"), ['ui-string']);
      expect(rules(r"Text('${n} photos')"), ['ui-string']);
      expect(rules(r"Text('${on ? 'On' : n}')"), ['ui-string']);
      expect(rules("Text('Café')"), ['ui-string']);
      expect(rules("Text('Фото')"), ['ui-string']);
    });

    test('accepts localised text and text without words', () {
      expect(rules('Text(strings.appTitle)'), isEmpty);
      expect(rules("Text(strings.pin('x'))"), isEmpty);
      expect(
        rules(r"Text('${r.level.name} ${r.logger}: ${r.message}')"),
        isEmpty,
      );
      expect(rules(r"Text('$count')"), isEmpty);
      expect(rules("Text('—')"), isEmpty);
      expect(rules(r"Text('\n')"), isEmpty);
    });

    test('accepts strings that are not shown', () {
      expect(rules("GoRoute(path: '/settings')"), isEmpty);
      expect(rules("logger.info('starting')"), isEmpty);
      expect(rules("final m = {'title': 1};"), isEmpty);
      expect(rules("import 'package:a/text.dart';"), isEmpty);
      expect(rules("Text(f('a'), key: Key('b'))"), isEmpty);
    });

    test('ignores comments, including quotes in them', () {
      expect(rules("// Text('Hello')"), isEmpty);
      expect(rules("/* Text('Hello') /* nested */ */"), isEmpty);
      expect(rules("/// The user's title: 'x'\nText(s.a)"), isEmpty);
    });
  });

  group('directional layout', () {
    test('flags physical left and right', () {
      expect(rules('EdgeInsets.only(left: 8)'), ['directional']);
      expect(rules('EdgeInsets.fromLTRB(1, 2, 3, 4)'), ['directional']);
      expect(rules('Positioned(top: 0, right: 0, child: c)'), ['directional']);
      expect(rules('BorderRadius.only(topLeft: r)'), ['directional']);
      expect(rules('Alignment.centerRight'), ['directional']);
      expect(rules('FractionalOffset.topLeft'), ['directional']);
      expect(rules('TextAlign.left'), ['directional']);
      expect(rules('TextDirection.rtl'), ['directional']);
    });

    test('accepts the directional and the symmetric forms', () {
      expect(rules('EdgeInsetsDirectional.only(start: 8)'), isEmpty);
      expect(rules('EdgeInsetsDirectional.fromSTEB(1, 2, 3, 4)'), isEmpty);
      expect(rules('EdgeInsets.only(top: 8)'), isEmpty);
      expect(rules('EdgeInsets.symmetric(horizontal: 8)'), isEmpty);
      expect(rules('AlignmentDirectional.centerEnd'), isEmpty);
      expect(rules('Alignment.topCenter'), isEmpty);
      expect(rules('TextAlign.start'), isEmpty);
      expect(rules('final x = wide ? left : right;'), isEmpty);
      expect(
        rules("Text(s.a, textAlign: TextAlign.end) // left: 'x'"),
        isEmpty,
      );
    });
  });

  group('the escape hatch', () {
    test('accepts a reason on the same line or the line above', () {
      expect(rules("Text('Photolib') // i18n-ok: brand name"), isEmpty);
      expect(rules('// i18n-ok: a map pin\nAlignment.bottomLeft'), isEmpty);
    });

    test('requires a reason', () {
      expect(rules("Text('Photolib') // i18n-ok:"), ['ui-string']);
    });
  });

  test('reports the file, the line and what to do instead', () {
    final found = lintSource('lib/ui/page.dart', "f();\nText('Hello');\n");
    expect(
      found.single.toString(),
      startsWith('lib/ui/page.dart:2: ui-string: '),
    );
  });

  test('the app has no hard-coded UI string or physical direction', () {
    expect(lintTree(Directory('lib')).map((v) => '$v'), isEmpty);
  });
}
