import 'package:material_ui/material_ui.dart';

/// Durations and curves of every animation. Under the system's reduce motion
/// they are instant (docs/17-i18n-and-accessibility.md §5).
abstract final class Motion {
  static const short = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 300);
  static const curve = Easing.standard;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, [Duration duration = medium]) =>
      reduced(context) ? Duration.zero : duration;
}

/// The platform's page transitions, or none under reduce motion.
class MotionPageTransitions extends PageTransitionsBuilder {
  const MotionPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => Motion.reduced(context)
      ? child
      : const PageTransitionsTheme().buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}
