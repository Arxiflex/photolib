import 'package:material_ui/material_ui.dart';

import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/adaptive.dart';

/// Takes the app bar's place while items are selected: how many, a way out,
/// select all, a slideshow, download (share on phones) and the bulk
/// [actions].
class SelectionBar extends StatelessWidget implements PreferredSizeWidget {
  /// The bar of [count] selected items.
  const new({
    required this.count,
    required this.onClear,
    required this.onDownload,
    this.onSelectAll,
    this.onSlideshow,
    this.actions = const [],
    super.key,
  });

  /// How many items are selected.
  final int count;

  /// Clears the selection.
  final VoidCallback onClear;

  /// Selects every item, when the bar offers it.
  final VoidCallback? onSelectAll;

  /// Plays the selected items as a slideshow, when the bar offers it.
  final VoidCallback? onSlideshow;

  /// Downloads, or on phones shares, the selected items.
  final VoidCallback onDownload;

  /// The bulk actions after these.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: strings.selectionClear,
        onPressed: onClear,
      ),
      // Large text shrinks to fit rather than losing the count to an ellipsis.
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(strings.selectionCount(count)),
      ),
      actions: [
        if (onSelectAll != null)
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: strings.selectAll,
            onPressed: onSelectAll,
          ),
        if (onSlideshow != null)
          IconButton(
            icon: const Icon(Icons.slideshow_outlined),
            tooltip: strings.slideshow,
            onPressed: onSlideshow,
          ),
        IconButton(
          icon: Icon(
            sharesDownloads ? Icons.share_outlined : Icons.download_outlined,
          ),
          tooltip: sharesDownloads ? strings.actionShare : strings.download,
          onPressed: onDownload,
        ),
        ...actions,
      ],
    );
  }
}
