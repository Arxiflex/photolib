import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/collections/collections.dart';
import 'package:photolib/features/collections/other_files.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib/ui/tokens.dart';

extension on CollectionKind {
  String label(AppLocalizations s) => switch (this) {
    CollectionKind.albums => s.collectionAlbums,
    CollectionKind.folders => s.settingsFolders,
    CollectionKind.favourites => s.searchFavourites,
    CollectionKind.people => s.collectionPeople,
    CollectionKind.places => s.collectionPlaces,
    CollectionKind.tags => s.collectionTags,
  };

  IconData get icon => switch (this) {
    CollectionKind.albums => Icons.photo_album_outlined,
    CollectionKind.folders => Icons.folder_outlined,
    CollectionKind.favourites => Icons.favorite_border,
    CollectionKind.people => Icons.people_outline,
    CollectionKind.places => Icons.place_outlined,
    CollectionKind.tags => Icons.sell_outlined,
  };
}

class CollectionsPage extends ConsumerStatefulWidget {
  const CollectionsPage({super.key});

  @override
  ConsumerState<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends ConsumerState<CollectionsPage> {
  var _customising = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final layout = ref.watch(collectionsProvider);
    final notifier = ref.read(collectionsProvider.notifier);
    final visible = layout.visible;
    final hidden = layout.hidden;

    Widget row(CollectionEntry entry, {required int index, required int of}) {
      final name = entry.kind.label(strings);
      final first = index == 0 || visible[index - 1].pinned != entry.pinned;
      final last = index == of - 1 || visible[index + 1].pinned != entry.pinned;
      final path = switch (entry.kind) {
        CollectionKind.albums ||
        CollectionKind.folders ||
        CollectionKind.favourites => '/collections/${entry.kind.name}',
        _ => null,
      };
      return ListTile(
        leading: Icon(entry.kind.icon),
        title: Text(name),
        onTap: path == null || _customising ? null : () => context.go(path),
        trailing: !_customising
            ? (entry.pinned ? const Icon(Icons.push_pin, size: 16) : null)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    tooltip: entry.pinned
                        ? strings.collectionUnpin(name)
                        : strings.collectionPin(name),
                    onPressed: () => notifier.togglePin(entry.kind),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: strings.collectionMoveUp(name),
                    onPressed: first
                        ? null
                        : () => notifier.move(entry.kind, -1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    tooltip: strings.collectionMoveDown(name),
                    onPressed: last ? null : () => notifier.move(entry.kind, 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.visibility_off_outlined),
                    tooltip: strings.collectionHide(name),
                    onPressed: () => notifier.toggleHidden(entry.kind),
                  ),
                ],
              ),
      );
    }

    return ContentWidth(
      child: ListView(
        padding: EdgeInsets.all(AppTokens.of(context).sm),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => setState(() => _customising = !_customising),
              child: Text(
                _customising
                    ? strings.collectionsDone
                    : strings.collectionsCustomise,
              ),
            ),
          ),
          for (final (i, entry) in visible.indexed)
            row(entry, index: i, of: visible.length),
          if (!_customising)
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(strings.mapTitle),
              onTap: () => context.go('/collections/map'),
            ),
          if (ref.watch(otherFilesProvider).value?.length case final n?
              when n > 0)
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(strings.otherFiles),
              trailing: Text(Formats(strings).number(n)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const OtherFilesPage()),
              ),
            ),
          if (_customising && hidden.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.all(AppTokens.of(context).md),
              child: Text(
                strings.hiddenCollections(hidden.length),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final entry in hidden)
              ListTile(
                leading: Icon(entry.kind.icon),
                title: Text(entry.kind.label(strings)),
                trailing: IconButton(
                  icon: const Icon(Icons.visibility_outlined),
                  tooltip: strings.collectionShow(entry.kind.label(strings)),
                  onPressed: () => notifier.toggleHidden(entry.kind),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
