import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// [player]'s 360° video, of [sphere] through [view], over what [frame]
/// shows of the poster (ADR-0146): libmpv projects it itself; a player of
/// textures is filtered by the panorama shader, which Impeller can do. Where
/// neither can, the poster says that the video cannot play.
Widget sphereVideo(
  VideoPlayerController player,
  Sphere sphere,
  ValueNotifier<SphereView> view,
  Widget Function(ui.Image? image, Widget? over) frame,
) => frame(
  null,
  VideoPlayerPlatform.instance is ProjectingPlayers
      ? _Projected(player, sphere, view)
      : ui.ImageFilter.isShaderFilterSupported
      ? IgnorePointer(
          child: SphereFilter(
            picture: VideoPlayer(player),
            frame: player.value.size,
            sphere: sphere,
            view: view,
          ),
        )
      : Builder(
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppLocalizations.of(context).viewerCannotPlay),
              ),
            ),
          ),
        ),
);

/// libmpv's [player] projecting [view] of [sphere] to the viewport's pixels,
/// within the 1,920 × 1,080 of media_kit_video's software output.
class _Projected extends StatelessWidget {
  const new(this.player, this.sphere, this.view);

  final VideoPlayerController player;
  final Sphere sphere;
  final ValueNotifier<SphereView> view;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest * MediaQuery.devicePixelRatioOf(context);
      final pixels = size * min(1, min(1920 / size.width, 1080 / size.height));
      return ValueListenableBuilder(
        valueListenable: view,
        builder: (context, v, _) => SphereProjection(
          filter: v.clamp(sphere, pixels).v360(sphere, pixels),
          child: VideoPlayer(player),
        ),
      );
    },
  );
}

/// A player's pictures, of [sphere] through [view], filtered by the panorama
/// shader (ImageFilter.shader, Impeller's): the filter's input is what the
/// viewport holds, so the [picture], the player's view, is laid out once for
/// each slot of the cells in view that [SpherePacking] packs, each clipped to
/// its slot.
class SphereFilter extends StatefulWidget {
  /// [picture] through the shader.
  const new({
    required this.picture,
    required this.frame,
    required this.sphere,
    required this.view,
    super.key,
  });

  /// The frame, stretched to its box: a player's view.
  final Widget picture;

  /// The frame's size in pixels.
  final Size frame;

  /// Where its pictures lie on the sphere.
  final Sphere sphere;

  /// Where they are seen from.
  final ValueNotifier<SphereView> view;

  @override
  State<SphereFilter> createState() => _SphereFilterState();
}

class _SphereFilterState extends State<SphereFilter> {
  ui.FragmentShader? _shader;
  ui.Image? _cells;

  @override
  void initState() {
    super.initState();
    unawaited(
      sphereProgram.then((p) {
        if (mounted) setState(() => _shader = p.fragmentShader());
      }),
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    _cells?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final viewport = size * MediaQuery.devicePixelRatioOf(context);
        return ValueListenableBuilder(
          valueListenable: widget.view,
          builder: (context, asked, _) {
            final (sphere, frame) = (widget.sphere, widget.frame);
            final view = asked.clamp(sphere, viewport);
            final packing = SpherePacking.of(sphere, view, viewport, frame);
            final cells = packing.cells();
            _cells?.dispose();
            _cells = cells;
            sphereUniforms(
              shader,
              sphere,
              view,
              viewport,
              frame.width.round(),
              frame.height.round(),
              2,
              packing,
            );
            shader.setImageSampler(1, cells);
            // The input is exactly the viewport.
            return ImageFiltered(
              imageFilter: ui.ImageFilter.shader(shader),
              child: Stack(
                children: [
                  for (final (part, slot) in packing.regions(sphere.eye))
                    Positioned.fromRect(
                      rect: Rect.fromLTWH(
                        slot.left * size.width,
                        slot.top * size.height,
                        slot.width * size.width,
                        slot.height * size.height,
                      ),
                      child: ClipRect(
                        child: OverflowBox(
                          // i18n-ok: the frame lies as its picture does
                          alignment: Alignment.topLeft,
                          minWidth: slot.width * size.width / part.width,
                          maxWidth: slot.width * size.width / part.width,
                          minHeight: slot.height * size.height / part.height,
                          maxHeight: slot.height * size.height / part.height,
                          child: Transform.translate(
                            offset: Offset(
                              -part.left * slot.width * size.width / part.width,
                              -part.top *
                                  slot.height *
                                  size.height /
                                  part.height,
                            ),
                            child: widget.picture,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
