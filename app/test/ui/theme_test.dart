import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib/ui/tokens.dart';

void main() {
  group('WindowSize.of', () {
    test('splits phone, tablet and desktop widths at 600 and 840', () {
      expect(WindowSize.of(320), WindowSize.compact);
      expect(WindowSize.of(599.9), WindowSize.compact);
      expect(WindowSize.of(600), WindowSize.medium);
      expect(WindowSize.of(839.9), WindowSize.medium);
      expect(WindowSize.of(840), WindowSize.expanded);
      expect(WindowSize.of(2560), WindowSize.expanded);
    });
  });

  group('appTheme', () {
    test('is made once for each brightness and contrast, as the viewer '
        'builds it on every page it swipes to', () {
      expect(appTheme(Brightness.dark), same(appTheme(Brightness.dark)));
      expect(
        appTheme(Brightness.dark, highContrast: true),
        isNot(same(appTheme(Brightness.dark))),
      );
    });

    for (final brightness in Brightness.values) {
      test('${brightness.name} carries the tokens and its brightness', () {
        final theme = appTheme(brightness);
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.extension<AppTokens>(), isNotNull);
      });
    }

    double contrast(Color a, Color b) {
      final [dark, light] = [a.computeLuminance(), b.computeLuminance()]
        ..sort();
      return (light + 0.05) / (dark + 0.05);
    }

    for (final brightness in Brightness.values) {
      test('${brightness.name} high contrast keeps text and controls at 7:1 '
          'or more', () {
        final normal = appTheme(brightness).colorScheme;
        final high = appTheme(brightness, highContrast: true).colorScheme;
        expect(high.brightness, brightness);
        for (final (fg, bg) in [
          ((ColorScheme s) => s.onSurfaceVariant, (ColorScheme s) => s.surface),
          ((ColorScheme s) => s.primary, (ColorScheme s) => s.surface),
          ((ColorScheme s) => s.outline, (ColorScheme s) => s.surface),
        ]) {
          expect(contrast(fg(high), bg(high)), greaterThanOrEqualTo(7));
          expect(
            contrast(fg(high), bg(high)),
            greaterThan(contrast(fg(normal), bg(normal))),
          );
        }
      });
    }

    test('the colours come from the seed and differ per brightness', () {
      expect(
        appTheme(Brightness.light).colorScheme.primary,
        isNot(appTheme(Brightness.dark).colorScheme.primary),
      );
      expect(
        appTheme(Brightness.light).colorScheme.primary,
        ColorScheme.fromSeed(seedColor: AppTokens.seed).primary,
      );
    });
  });

  group('AppTokens', () {
    const tokens = AppTokens();

    test('spacing grows with each step', () {
      final steps = [tokens.xs, tokens.sm, tokens.md, tokens.lg, tokens.xl];
      expect(steps, orderedEquals([...steps]..sort()));
      expect(steps.toSet().length, steps.length);
    });

    test('a theme extension has a copy and an interpolation', () {
      expect(tokens.copyWith(md: 20).md, 20);
      expect(tokens.copyWith(md: 20).sm, tokens.sm);
      expect(tokens.lerp(null, 0.5), tokens);
    });
  });
}
