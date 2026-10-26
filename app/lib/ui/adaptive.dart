import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Phones share what desktops and browsers download: whatever they show is in
/// their gallery already (ADR-0128).
bool get sharesDownloads =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
    }.contains(defaultTargetPlatform);

enum WindowSize {
  compact,
  medium,
  expanded;

  /// Material window size classes: phone, tablet, desktop.
  static WindowSize of(double width) => width < 600
      ? compact
      : width < 840
      ? medium
      : expanded;
}

/// Keeps a page at reading width instead of stretching across a desktop window.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}
