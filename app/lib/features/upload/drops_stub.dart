import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/widgets.dart';

/// Takes files dropped on the window into [onDrop], in a browser; elsewhere
/// the platform's own drops do (features/desktop/file_drag.dart).
class UploadDrops extends StatelessWidget {
  /// Drops into [onDrop], around [child].
  const new({required this.onDrop, required this.child, super.key});

  /// Takes the files dropped.
  final void Function(List<XFile> files) onDrop;

  /// What the drops go over.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
