import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib/ui/theme.dart';

void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      reduced
          ? 'under reduce motion animations are instant and a pushed page '
                'appears in place at once'
          : 'animations take their duration and a pushed page moves in',
      (tester) async {
        if (reduced) reduceMotion(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const Text('page')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        final context = tester.element(find.text('open'));
        expect(
          Motion.of(context, Motion.short),
          reduced ? Duration.zero : Motion.short,
        );
        expect(Motion.of(context), reduced ? Duration.zero : Motion.medium);

        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        final first = tester.getRect(find.text('page'));
        await tester.pumpAndSettle();
        expect(first == tester.getRect(find.text('page')), reduced);
      },
    );
  }
}
