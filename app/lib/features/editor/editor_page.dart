import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/features/editor/save_copy.dart';
import 'package:photolib/features/editor/versions.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib_api/kernel.dart' show CaptureTime;
import 'package:photolib_editor/edit.dart';
import 'package:photolib_editor/photolib_editor.dart';

const _log = Logger('photolib.editor');

/// The shaders that preview an edit's adjustments (ADR-0054).
final shaderRendererProvider = FutureProvider<ShaderRenderer>(
  (ref) => ShaderRenderer.load(),
);

/// The alpha's editor (ADR-0331, design 11 §3): crops, rotates, mirrors and
/// auto-enhances [image], the screen-size picture of [item] as shown, which
/// it disposes, and saves the edit as a copy beside [item], which its route
/// returns.
class EditorPage extends ConsumerStatefulWidget {
  /// The editor of [item], showing [image].
  const new({
    required this.item,
    required this.image,
    this.time,
    this.asVersion = false,
    super.key,
  });

  /// The photo edited, which stays as it is.
  final ThumbnailItem item;

  /// The photo as shown, at screen size.
  final ui.Image image;

  /// The capture time of [item] as the device index has it.
  final CaptureTime? time;

  /// Whether the edit is saved as a new version of [item], a photo only the
  /// server has (ADR-0391), and the route returns [item]; else as a copy.
  final bool asVersion;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  var _edit = const Edit();
  // The picture with the auto-enhance, as the shaders render it.
  ui.Image? _enhanced;
  var _saving = false;

  @override
  void dispose() {
    _enhanced?.dispose();
    widget.image.dispose();
    super.dispose();
  }

  void _change(Edit edit) => setState(() => _edit = edit);

  Future<void> _autoEnhance() async {
    if (_edit.enhance != null) return _change(_edit.enhanced(null));
    final image = widget.image;
    final pixels = await image.toByteData();
    if (pixels == null) return;
    final develop = autoEnhance(pixels.buffer.asUint8List());
    final renderer = await ref.read(shaderRendererProvider.future);
    final guide = renderer.guide(image);
    final enhanced = await renderer.render(develop, image, guide);
    guide.dispose();
    if (!mounted) return enhanced.dispose();
    _enhanced?.dispose();
    _enhanced = enhanced;
    _change(_edit.enhanced(develop));
  }

  /// Crops to the largest centred rectangle of [aspect] (width over height),
  /// or to the whole photo.
  void _aspect(double? aspect) {
    if (aspect == null) return _change(_edit.cropped(Edit.whole));
    final (w, h) = _seen;
    final (cw, ch) = w / h > aspect
        ? (aspect * h / w, 1.0)
        : (1.0, w / h / aspect);
    _change(
      _edit.cropped(
        Rect.fromCenter(center: const Offset(0.5, 0.5), width: cw, height: ch),
      ),
    );
  }

  (int, int) get _seen => _edit.quarterTurns.isOdd
      ? (widget.image.height, widget.image.width)
      : (widget.image.width, widget.image.height);

  Future<void> _save() async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (widget.asVersion) {
        final version = await ref.read(saveVersionProvider)(widget.item, _edit);
        if (!mounted) return;
        if (version == null) {
          setState(() => _saving = false);
          messenger.showSnackBar(
            SnackBar(content: Text(strings.editorVersionsUnsupported)),
          );
          return;
        }
        _log.info('version saved', fields: {'file': '${widget.item}'});
        return Navigator.pop(context, widget.item);
      }
      final copy = await ref.read(saveCopyProvider)(
        widget.item,
        _edit,
        widget.time,
      );
      if (!mounted) return;
      if (copy == null) return setState(() => _saving = false);
      _log.info('copy saved', fields: {'file': '${widget.item}'});
      Navigator.pop(context, copy);
    } on Object catch (error) {
      _log.warning(
        'copy not saved',
        fields: {'file': '${widget.item}'},
        error: error,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.asVersion
                ? strings.editorVersionFailed
                : strings.editorSaveFailed,
          ),
        ),
      );
    }
  }

  Widget _preview() {
    final strings = AppLocalizations.of(context);
    final (w, h) = _seen;
    final image = _edit.enhance == null ? widget.image : _enhanced;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: AspectRatio(
          aspectRatio: w / h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.flip(
                flipX: _edit.flip,
                child: RotatedBox(
                  quarterTurns: _edit.quarterTurns,
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
              _CropFrame(
                crop: _edit.crop,
                label: strings.editorCrop,
                onChanged: (crop) => _change(_edit.cropped(crop)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tools() {
    final strings = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.rotate_left),
              tooltip: strings.editorRotate,
              onPressed: _saving ? null : () => _change(_edit.rotated()),
            ),
            IconButton(
              icon: const Icon(Icons.flip),
              tooltip: strings.editorFlip,
              onPressed: _saving ? null : () => _change(_edit.flipped()),
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => _aspect(null),
                  child: Text(strings.editorCropOriginal),
                ),
                MenuItemButton(
                  onPressed: () => _aspect(1),
                  child: Text(strings.editorCropSquare),
                ),
              ],
              builder: (context, menu, _) => IconButton(
                icon: const Icon(Icons.crop),
                tooltip: strings.editorCrop,
                onPressed: _saving
                    ? null
                    : () => menu.isOpen ? menu.close() : menu.open(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.auto_fix_high),
              isSelected: _edit.enhance != null,
              tooltip: strings.editorAutoEnhance,
              onPressed: _saving ? null : () => unawaited(_autoEnhance()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Theme(
      data: appTheme(
        Brightness.dark,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(strings.editorEdit),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(),
                ),
              )
            else
              TextButton(
                onPressed: _edit.isEmpty ? null : _save,
                child: Text(
                  widget.asVersion
                      ? strings.editorSaveVersion
                      : strings.editorSaveCopy,
                ),
              ),
          ],
        ),
        body: _preview(),
        bottomNavigationBar: _tools(),
      ),
    );
  }
}

/// The crop over the picture: the rest shaded, its corners and its inside
/// dragged; [crop] is in [0, 1]² of the picture.
class _CropFrame extends StatefulWidget {
  const new({required this.crop, required this.label, required this.onChanged});

  final Rect crop;
  final String label;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropFrame> createState() => _CropFrameState();
}

class _CropFrameState extends State<_CropFrame> {
  /// The least of each side a crop keeps.
  static const _least = 0.05;

  // Moves can come faster than frames: each starts from the last.
  late Rect _crop = widget.crop;

  @override
  void didUpdateWidget(_CropFrame old) {
    super.didUpdateWidget(old);
    _crop = widget.crop;
  }

  void _set(Rect crop) => widget.onChanged(_crop = crop);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      final crop = widget.crop;
      final frame = Rect.fromLTRB(
        crop.left * size.width,
        crop.top * size.height,
        crop.right * size.width,
        crop.bottom * size.height,
      );
      Offset scaled(Offset delta) =>
          Offset(delta.dx / size.width, delta.dy / size.height);
      void move(Offset delta) {
        final (c, d) = (_crop, scaled(delta));
        final dx = d.dx.clamp(-c.left, 1 - c.right);
        final dy = d.dy.clamp(-c.top, 1 - c.bottom);
        _set(c.shift(Offset(dx, dy)));
      }

      void drag(Offset corner, Offset delta) {
        final d = scaled(delta);
        var (l, t, r, b) = (_crop.left, _crop.top, _crop.right, _crop.bottom);
        if (corner.dx < 0) l = (l + d.dx).clamp(0, r - _least);
        if (corner.dx > 0) r = (r + d.dx).clamp(l + _least, 1);
        if (corner.dy < 0) t = (t + d.dy).clamp(0, b - _least);
        if (corner.dy > 0) b = (b + d.dy).clamp(t + _least, 1);
        _set(Rect.fromLTRB(l, t, r, b));
      }

      return Semantics(
        label: widget.label,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Shade(frame, Theme.of(context).colorScheme.primary),
              ),
            ),
            Positioned.fromRect(
              rect: frame,
              child: GestureDetector(
                key: const ValueKey('crop'),
                // From where the finger went down, so the frame follows it.
                dragStartBehavior: DragStartBehavior.down,
                onPanUpdate: (d) => move(d.delta),
              ),
            ),
            // The picture's own corners, which no reading direction mirrors.
            for (final corner in const [
              Offset(-1, -1),
              Offset(1, -1),
              Offset(-1, 1),
              Offset(1, 1),
            ])
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: Offset(
                    corner.dx < 0 ? frame.left : frame.right,
                    corner.dy < 0 ? frame.top : frame.bottom,
                  ),
                  width: 48,
                  height: 48,
                ),
                child: GestureDetector(
                  key: ValueKey(corner),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanUpdate: (d) => drag(corner, d.delta),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Shades the picture outside [frame] and outlines it.
class _Shade extends CustomPainter {
  new(this.frame, Color line)
    : _outline = Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

  final Rect frame;
  final Paint _outline;
  final _shade = Paint()..color = const Color(0x99000000);

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    canvas
      ..drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(all),
          Path()..addRect(frame),
        ),
        _shade,
      )
      ..drawRect(frame.deflate(1), _outline);
    for (final x in [frame.left, frame.right]) {
      for (final y in [frame.top, frame.bottom]) {
        canvas.drawCircle(Offset(x, y), 6, _outline);
      }
    }
  }

  @override
  bool shouldRepaint(_Shade old) => old.frame != frame;
}
