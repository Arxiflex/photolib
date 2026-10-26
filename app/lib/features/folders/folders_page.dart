import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/folders/file_dialogs.dart';
import 'package:photolib/features/folders/items_page.dart';
import 'package:photolib/features/folders/views.dart';
import 'package:photolib/features/library/library.dart' show veiledProvider;
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnail_at.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/search/search.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib/ui/empty_state.dart';
import 'package:photolib_data/photolib_data.dart' hide Stack;

/// The key of the device folder [f] among the views.
String folderKey(LocalFolder f) => '${f.source}|${f.volume}|${f.dir}';

/// [id] in hex.
String hexOf(Uint8List id) =>
    [for (final b in id) b.toRadixString(16).padLeft(2, '0')].join();

/// Thumbnails for a page of its own, from the platform's pipeline.
Thumbnails pageThumbnails(WidgetRef ref) =>
    Thumbnails((item, tier, tile) async {
      final pipeline = await ref.read(thumbnailPipelineProvider.future);
      return await pipeline.load(item as ThumbnailItem, tier, tile);
    }, video: (item) => (item as ThumbnailItem).video);

/// The device's folders that hold items, the excluded too, as they change;
/// hidden items only while they show.
final StreamProvider<List<FolderEntry>> folderEntriesProvider =
    StreamProvider.autoDispose<List<FolderEntry>>((ref) async* {
      yield* folderEntries(
        await ref.watch(replicaProvider.future),
        veiled: ref.watch(veiledProvider),
      );
    });

/// The album folders and albums in the album folder of this hex id, or at the
/// top for an empty one, as they change.
final StreamProviderFamily<List<AlbumEntry>, String> albumChildrenProvider =
    StreamProvider.autoDispose.family<List<AlbumEntry>, String>((
      ref,
      parent,
    ) async* {
      final db = await ref.watch(replicaProvider.future);
      yield* albumChildren(
        db,
        parent.isEmpty ? null : _id(parent),
        veiled: ref.watch(veiledProvider),
      );
    });

Uint8List _id(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// The device's folders and the albums (VIEW-34's Collections), as two tabs,
/// on [tab] first.
class FoldersPage extends ConsumerWidget {
  /// The page, on the folders' tab (0) or the albums' (1).
  const new({required this.tab, super.key});

  /// The tab shown first.
  final int tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      initialIndex: tab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.tabCollections),
          bottom: TabBar(
            tabs: [
              Tab(text: strings.settingsFolders),
              Tab(text: strings.collectionAlbums),
            ],
          ),
        ),
        body: const TabBarView(
          children: [DeviceFolderList(), AlbumList(parent: null)],
        ),
      ),
    );
  }
}

/// The device's folders that hold items in the order the user dragged them,
/// the pinned first; those the user keeps out and the default junk folders
/// only on request.
class DeviceFolderList extends ConsumerStatefulWidget {
  /// The list; with [onTap], a chooser of a folder.
  const new({super.key, this.onTap});

  /// Called with the folder tapped instead of opening it.
  final ValueChanged<FolderEntry>? onTap;

  @override
  ConsumerState<DeviceFolderList> createState() => _DeviceFolderListState();
}

class _DeviceFolderListState extends ConsumerState<DeviceFolderList> {
  late final Thumbnails _thumbnails = pageThumbnails(ref);
  var _excluded = false;

  @override
  void dispose() {
    _thumbnails.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final folders = ref.watch(folderEntriesProvider).value;
    if (folders == null) return const SizedBox.shrink();
    if (folders.isEmpty) {
      return EmptyState(
        icon: Icons.folder_outlined,
        message: strings.libraryEmpty,
      );
    }
    ref.watch(folderViewsProvider);
    final views = ref.read(folderViewsProvider.notifier);
    final byKey = {for (final f in folders) folderKey(f.folder): f};
    final out = {
      for (final f in folders)
        if (f.excluded || isJunk(f.folder.dir)) folderKey(f.folder),
    };
    final keys = views.arrange('folders', [
      for (final f in [...folders]..sort(_byName)) folderKey(f.folder),
    ]);
    final shown = [
      for (final k in keys)
        if (_excluded || !out.contains(k)) k,
    ];
    return ReorderableListView(
      buildDefaultDragHandles: widget.onTap == null,
      onReorderItem: (from, to) => views.reorder('folders', shown, from, to),
      footer: out.isEmpty
          ? null
          : TextButton(
              onPressed: () => setState(() => _excluded = !_excluded),
              child: Text(
                _excluded
                    ? strings.foldersHideExcluded
                    : strings.foldersShowExcluded(out.length),
              ),
            ),
      children: [
        for (final k in shown)
          if (byKey[k] case final folder?)
            _FolderTile(
              folder,
              _thumbnails,
              key: ValueKey(k),
              onTap: widget.onTap,
            ),
      ],
    );
  }

  static int _byName(FolderEntry a, FolderEntry b) {
    final c = naturalCompare(folderLabel(a.folder), folderLabel(b.folder));
    return c != 0 ? c : a.folder.volume.compareTo(b.folder.volume);
  }
}

/// A folder's tile: its newest item in a folder's frame, its name, item count
/// and place, its volume on a phone, and its pin.
class _FolderTile extends StatelessWidget {
  const new(this.folder, this.thumbnails, {super.key, this.onTap});

  final FolderEntry folder;
  final Thumbnails thumbnails;
  final ValueChanged<FolderEntry>? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final f = folder.folder;
    final name = folderLabel(f);
    final scheme = Theme.of(context).colorScheme;
    final place = f.source == 'folder' ? '${f.volume}/${f.dir}' : f.dir;
    return ListTile(
      leading: _Framed(Cover(ThumbnailItem.local(folder.cover), thumbnails)),
      title: Text(name),
      subtitle: Text(
        '${strings.folderItems(folder.items)}\n${isolated(place)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.source == 'mediastore')
            Badge(
              label: Text(
                strings.volumeBadge(
                  f.volume == 'external_primary' ? 'internal' : 'sd',
                ),
              ),
              backgroundColor: scheme.secondaryContainer,
              textColor: scheme.onSecondaryContainer,
            ),
          if (onTap == null) _Pin(folderKey(f), name),
        ],
      ),
      onTap: () => switch (onTap) {
        final choose? => choose(folder),
        null => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ItemsPage(ItemsSource.folder(f, name)),
          ),
        ),
      },
    );
  }
}

/// Pins the entry [id], named [name], on top of its list, or unpins it.
class _Pin extends ConsumerWidget {
  const new(this.id, this.name);

  final String id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final pinned = ref.watch(
      folderViewsProvider.select((v) => v.pinned.contains(id)),
    );
    return IconButton(
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      tooltip: pinned
          ? strings.collectionUnpin(name)
          : strings.collectionPin(name),
      onPressed: () => ref.read(folderViewsProvider.notifier).togglePin(id),
    );
  }
}

/// A folder's look: its cover with a folder's tab, unlike any photo.
class _Framed extends StatelessWidget {
  const new(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 56,
      child: Stack(
        children: [
          Positioned.fill(
            top: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: child,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            child: Icon(Icons.folder, size: 18, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

/// The thumbnail of [item], or a folder's icon without one.
class Cover extends StatefulWidget {
  /// The cover.
  const new(this.item, this.thumbnails, {super.key});

  /// What it shows.
  final ThumbnailItem? item;

  /// Where its thumbnail comes from.
  final Thumbnails thumbnails;

  @override
  State<Cover> createState() => _CoverState();
}

class _CoverState extends State<Cover> {
  late TimelinePages _pages = _of(widget.item);

  static TimelinePages _of(ThumbnailItem? item) =>
      TimelinePages((first, count) async => [?item]);

  @override
  void didUpdateWidget(Cover old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) {
      _pages.dispose();
      _pages = _of(widget.item);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.item == null
      ? const Icon(Icons.folder_outlined)
      : ThumbnailAt(0, _pages, widget.thumbnails, key: ObjectKey(_pages));
}

/// The album folders, then the albums, in the album folder [parent] or at
/// the top, in the order the user dragged them, the pinned first.
class AlbumList extends ConsumerStatefulWidget {
  /// The list.
  const new({required this.parent, super.key});

  /// The album folder, or null at the top.
  final Uint8List? parent;

  @override
  ConsumerState<AlbumList> createState() => _AlbumListState();
}

class _AlbumListState extends ConsumerState<AlbumList> {
  late final Thumbnails _thumbnails = pageThumbnails(ref);

  String get _list => 'albums:${_parent()}';

  String _parent() => switch (widget.parent) {
    final parent? => hexOf(parent),
    null => '',
  };

  @override
  void dispose() {
    _thumbnails.clear();
    super.dispose();
  }

  Future<void> _create({required bool folder}) async {
    final strings = AppLocalizations.of(context);
    final name = await nameDialog(
      context,
      folder ? strings.folderNew : strings.albumNew,
    );
    if (name == null) return;
    final db = await ref.read(replicaProvider.future);
    folder
        ? await createAlbumFolder(db, name, parent: widget.parent)
        : await createAlbum(db, name, folder: widget.parent);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final entries = ref.watch(albumChildrenProvider(_parent())).value ?? [];
    ref.watch(folderViewsProvider);
    final views = ref.read(folderViewsProvider.notifier);
    final byKey = {for (final e in entries) hexOf(e.id): e};
    final shown = views.arrange(_list, [for (final e in entries) hexOf(e.id)]);
    return ReorderableListView(
      onReorderItem: (from, to) => views.reorder(_list, shown, from, to),
      header: Wrap(
        children: [
          TextButton.icon(
            onPressed: () => _create(folder: false),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(strings.albumNew),
          ),
          TextButton.icon(
            onPressed: () => _create(folder: true),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(strings.folderNew),
          ),
        ],
      ),
      children: [
        for (final k in shown)
          if (byKey[k] case final entry?)
            _AlbumTile(entry, _thumbnails, key: ValueKey(k)),
      ],
    );
  }
}

class _AlbumTile extends ConsumerWidget {
  const new(this.entry, this.thumbnails, {super.key});

  final AlbumEntry entry;
  final Thumbnails thumbnails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final cover = entry.cover;
    return ListTile(
      leading: entry.folder
          ? const _Framed(Icon(Icons.photo_album_outlined))
          : SizedBox.square(
              dimension: 56,
              child: Cover(
                cover == null ? null : ThumbnailItem.local(cover),
                thumbnails,
              ),
            ),
      title: Text(entry.name),
      subtitle: Text(strings.folderItems(entry.items)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pin(hexOf(entry.id), entry.name),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: strings.actionMoveTo,
            onPressed: () => moveAlbumEntryDialog(context, ref, entry.id),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => entry.folder
              ? Scaffold(
                  appBar: AppBar(title: Text(entry.name)),
                  body: AlbumList(parent: entry.id),
                )
              : ItemsPage(ItemsSource.album(entry.id, entry.name)),
        ),
      ),
    );
  }
}

/// Lets the user choose a device folder, then items of it in its own sort and
/// layout, and adds them to the album [album].
Future<void> addFromFolder(
  BuildContext context,
  WidgetRef ref,
  Uint8List album,
) async {
  final folder = await showModalBottomSheet<FolderEntry>(
    context: context,
    showDragHandle: true,
    builder: (context) =>
        DeviceFolderList(onTap: (f) => Navigator.pop(context, f)),
  );
  if (folder == null || !context.mounted) return;
  final ids = await Navigator.of(context).push(
    MaterialPageRoute<List<Uint8List>>(
      builder: (_) => ItemsPage(
        ItemsSource.folder(folder.folder, folderLabel(folder.folder)),
        pick: true,
      ),
    ),
  );
  if (ids != null) {
    await addToAlbum(await ref.read(replicaProvider.future), album, ids);
  }
}

/// Lets the user choose an album, or make one, and adds the items [ids] to it.
Future<void> addToChosenAlbum(
  BuildContext context,
  WidgetRef ref,
  List<Uint8List> ids,
) async {
  final strings = AppLocalizations.of(context);
  final db = await ref.read(replicaProvider.future);
  final albums = await allAlbums(db);
  if (!context.mounted) return;
  final chosen = await showModalBottomSheet<Uint8List>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(strings.albumNew),
          onTap: () async {
            final name = await nameDialog(context, strings.albumNew);
            final id = name == null ? null : await createAlbum(db, name);
            if (context.mounted) Navigator.pop(context, id);
          },
        ),
        for (final a in albums)
          ListTile(
            leading: const Icon(Icons.photo_album_outlined),
            title: Text(a.title),
            subtitle: a.path.isEmpty ? null : Text(a.path.join(' › ')),
            onTap: () => Navigator.pop(context, a.id),
          ),
      ],
    ),
  );
  if (chosen != null) await addToAlbum(db, chosen, ids);
}

/// Lets the user choose the album folder, or the top, that the album or album
/// folder [id] moves into.
Future<void> moveAlbumEntryDialog(
  BuildContext context,
  WidgetRef ref,
  Uint8List id,
) async {
  final db = await ref.read(replicaProvider.future);
  final folders = <(Uint8List?, String, int)>[(null, '', 0)];
  Future<void> walk(Uint8List? parent, int depth) async {
    for (final e in await albumChildren(db, parent).first) {
      if (!e.folder) continue;
      folders.add((e.id, e.name, depth));
      await walk(e.id, depth + 1);
    }
  }

  await walk(null, 1);
  if (!context.mounted) return;
  final strings = AppLocalizations.of(context);
  final to = await showModalBottomSheet<(Uint8List?,)>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListView(
      children: [
        for (final (folder, name, depth) in folders)
          ListTile(
            contentPadding: EdgeInsetsDirectional.only(
              start: 16.0 * depth + 16,
            ),
            leading: const Icon(Icons.folder_outlined),
            title: Text(depth == 0 ? strings.collectionAlbums : name),
            onTap: () => Navigator.pop(context, (folder,)),
          ),
      ],
    ),
  );
  if (to != null) await moveAlbumEntry(db, id, to.$1);
}
