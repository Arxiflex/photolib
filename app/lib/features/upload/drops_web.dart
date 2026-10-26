// Only the web build resolves this file; analysis reads the stub.
// ignore_for_file: unused-code
import 'dart:js_interop';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Takes files dropped on the window into [onDrop]: the browser would open
/// the first in the tab otherwise.
class UploadDrops extends StatefulWidget {
  /// Drops into [onDrop], around [child].
  const new({required this.onDrop, required this.child, super.key});

  /// Takes the files dropped.
  final void Function(List<XFile> files) onDrop;

  /// What the drops go over.
  final Widget child;

  @override
  State<UploadDrops> createState() => _UploadDropsState();
}

class _UploadDropsState extends State<UploadDrops> {
  late final JSFunction _over = ((web.DragEvent e) {
    if (e.dataTransfer?.types.toDart.contains('Files'.toJS) ?? false) {
      e.preventDefault();
    }
  }).toJS;
  late final JSFunction _drop = ((web.DragEvent e) {
    final files = e.dataTransfer?.files;
    if (files == null || files.length == 0) return;
    e.preventDefault();
    widget.onDrop([
      for (var i = 0; i < files.length; i++)
        if (files.item(i) case final file?) _picked(file),
    ]);
  }).toJS;

  @override
  void initState() {
    super.initState();
    web.document
      ..addEventListener('dragover', _over)
      ..addEventListener('drop', _drop);
  }

  @override
  void dispose() {
    web.document
      ..removeEventListener('dragover', _over)
      ..removeEventListener('drop', _drop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

XFile _picked(web.File file) => XFile(
  web.URL.createObjectURL(file),
  name: file.name,
  length: file.size,
  lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
  mimeType: file.type,
);
