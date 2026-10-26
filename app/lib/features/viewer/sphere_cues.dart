import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/commands.dart';
import 'package:photolib/ui/motion.dart';

/// How long a sphere's slow turn takes, and how far it turns.
const slowTurn = Duration(seconds: 9);
const double _slowYaw = 30 * pi / 180;

/// What says a sphere shown in the viewer turns, rather than words on it
/// (docs/10 §4.6, VIEW-42): a 96 dp ring with 360° that fades in and out
/// once, a slow turn of [view] that stops at the first of [touches] or a key
/// (none while the device's motion turns it, unless [turning]), and, with
/// the [chrome], a 48 dp compass dial at the bottom end, [raised] over a
/// video's controls, that shows where it looks and faces front when clicked;
/// a long press or right click on it offers its [lenses], and the [turns]
/// (the device's motion, the compass lock) are buttons above it.
class SphereCues extends StatefulWidget {
  /// The cues of a sphere seen through [view].
  const new({
    required this.view,
    required this.sphere,
    required this.chrome,
    required this.touches,
    required this.turning,
    required this.lenses,
    required this.turns,
    required this.raised,
    required this.menu,
    super.key,
  });

  /// Where the sphere is seen from.
  final ValueNotifier<SphereView> view;

  /// Where its picture lies, and which way north is.
  final Sphere sphere;

  /// Whether the bar shows, with which the dial does.
  final bool chrome;

  /// Counts the presses and wheel turns that stop the slow turn.
  final ValueListenable<int> touches;

  /// Whether the slow turn may run.
  final bool turning;

  /// The little planet and the fisheye.
  final List<Command> lenses;

  /// The device's motion and the compass lock.
  final List<Command> turns;

  /// Whether a video's controls take the foot of the picture.
  final bool raised;

  /// Opens and closes the [lenses]' menu.
  final MenuController menu;

  @override
  State<SphereCues> createState() => _SphereCuesState();
}

class _SphereCuesState extends State<SphereCues> with TickerProviderStateMixin {
  late final _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final _turn = AnimationController(vsync: this, duration: slowTurn)
    ..addListener(_turned);
  // The yaw the slow turn started from.
  var _from = 0.0;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _ring.forward();
    widget.touches.addListener(_stop);
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && widget.turning && !Motion.reduced(context)) {
      _started = true;
      _from = widget.view.value.yaw;
      _turn.forward();
    }
  }

  @override
  void didUpdateWidget(SphereCues old) {
    super.didUpdateWidget(old);
    if (!widget.turning) _stop();
  }

  void _turned() => widget.view.value = widget.view.value.copyWith(
    yaw: _from + _slowYaw * Curves.easeInOut.transform(_turn.value),
  );

  void _stop() => _turn.stop();

  bool _key(KeyEvent event) {
    _stop();
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    widget.touches.removeListener(_stop);
    _ring.dispose();
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Stack(
      children: [
        IgnorePointer(
          child: Center(
            child: FadeTransition(
              opacity: TweenSequence<double>([
                TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 3),
                TweenSequenceItem(tween: ConstantTween(1), weight: 10),
                TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 3),
              ]).animate(_ring),
              child: Container(
                key: const ValueKey('sphere-ring'),
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 2),
                ),
                // i18n-ok: the degree sign reads the same in every language
                child: const Text(
                  '360°',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
          ),
        ),
        if (widget.chrome)
          Align(
            alignment: AlignmentDirectional.bottomEnd,
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                16,
                16,
                16,
                widget.raised ? 112 : 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  for (final c in widget.turns)
                    IconButton.filledTonal(
                      icon: Icon(c.icon),
                      tooltip: c.label,
                      onPressed: c.run,
                    ),
                  _dial(strings),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The compass dial, whose needle points where the picture's front, or
  /// north where it is known, lies from where it is looked at.
  Widget _dial(AppLocalizations strings) => MenuAnchor(
    controller: widget.menu,
    menuChildren: [
      for (final c in widget.lenses)
        MenuItemButton(
          leadingIcon: Icon(c.icon),
          onPressed: c.run,
          child: Text(c.label),
        ),
    ],
    child: Tooltip(
      message: strings.viewerDial,
      child: Semantics(
        button: true,
        onLongPressHint: strings.viewerLenses,
        child: GestureDetector(
          onLongPress: widget.menu.open,
          onSecondaryTap: widget.menu.open,
          child: SizedBox.square(
            dimension: 48,
            child: RawMaterialButton(
              key: const ValueKey('sphere-dial'),
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white38),
              ),
              fillColor: const Color(0x9E14181C),
              onPressed: () => widget.view.value = const SphereView(),
              child: ValueListenableBuilder(
                valueListenable: widget.view,
                builder: (context, view, _) => Transform.rotate(
                  key: const ValueKey('sphere-needle'),
                  angle: -(view.yaw + (widget.sphere.heading ?? 0)),
                  child: const Icon(Icons.navigation, color: Color(0xFFE9B949)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
