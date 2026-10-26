import 'package:material_ui/material_ui.dart';

/// Design tokens: every spacing, radius and brand colour the UI uses.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    this.xs = 4,
    this.sm = 8,
    this.md = 16,
    this.lg = 24,
    this.xl = 32,
    this.radius = 12,
  });

  static const seed = Color(0xFF2E6F95);

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double radius;

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  @override
  AppTokens copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? radius,
  }) => AppTokens(
    xs: xs ?? this.xs,
    sm: sm ?? this.sm,
    md: md ?? this.md,
    lg: lg ?? this.lg,
    xl: xl ?? this.xl,
    radius: radius ?? this.radius,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) => this;
}
