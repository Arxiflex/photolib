import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/scrubber.dart';
import 'package:photolib/features/library/timeline/selection.dart';

/// A segment's heading, which selects its assets, or clears them when all
/// are selected.
class TimelineHeader extends StatelessWidget {
  /// The heading [label] of the [assets] it selects in [selection].
  const new({
    required this.label,
    required this.style,
    required this.assets,
    required this.selection,
    required this.onTap,
    super.key,
  });

  /// The segment's date or period.
  final String label;

  /// The label's style.
  final TextStyle? style;

  /// The segment's first asset and the one past its last.
  final (int, int) assets;

  /// The selected positions, which show a check while anything is.
  final ValueNotifier<Selection> selection;

  /// Selects the segment, or clears it.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: selection,
    builder: (context, selection, _) {
      final all = selection.containsAll(assets.$1, assets.$2);
      return Semantics(
        button: true,
        selected: all,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // The check stays clear of the scrubber, whose thumb rests there.
            padding: const EdgeInsetsDirectional.only(
              start: 12,
              end: TimelineScrubber.width,
            ),
            child: Row(
              children: [
                Expanded(child: Text(label, style: style)),
                if (!selection.isEmpty)
                  Icon(
                    all ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
