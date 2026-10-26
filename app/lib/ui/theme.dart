import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';

import 'motion.dart';
import 'tokens.dart';

final _themes = <(Brightness, bool, TargetPlatform), ThemeData>{};

/// The app's theme, built once per platform: the seed's scheme takes most of
/// a frame, and the viewer asks for its dark theme on every page.
ThemeData appTheme(Brightness brightness, {bool highContrast = false}) =>
    _themes[(brightness, highContrast, defaultTargetPlatform)] ??= ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.seed,
        brightness: brightness,
        contrastLevel: highContrast ? 1 : 0,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const MotionPageTransitions(),
        },
      ),
      extensions: const [AppTokens()],
    );
