import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_library.dart';
import 'package:photolib/core/errors.dart';
import 'package:photolib/core/kept.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/core/share_inbox.dart';
import 'package:photolib/features/backup/backup_page.dart';
import 'package:photolib/features/desktop/file_drag.dart';
import 'package:photolib/features/download/download_action.dart';
import 'package:photolib/features/folders/device_folders.dart';
import 'package:photolib/features/folders/folders.dart';
import 'package:photolib/features/library/deletion.dart';
import 'package:photolib/features/library/library.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/features/library/timeline/thumbnail_at.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/library/timeline/warmup.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/trash/trash.dart';
import 'package:photolib/features/trash/trash_page.dart';
import 'package:photolib/features/upload/upload_ui.dart';
import 'package:photolib/features/viewer/animated.dart';
import 'package:photolib/features/viewer/slideshow.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/empty_state.dart';
import 'package:photolib/ui/selection_bar.dart';
import 'package:photolib_data/photolib_data.dart'
    show MediaAccess, extractFirst, saveThumbHashes;

// Why photolibd refused an edit (photolib.api.v1.MutationResult).
const _forbidden = 'mutation.forbidden';
const _gone = 'mutation.not_found';

/// The device index as a timeline (docs/10 §3), with the banners that say
/// what keeps items out of it.
class LibraryPage extends ConsumerStatefulWidget {
  /// The page, which reads everything it shows from providers.
  const new({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _selection = ValueNotifier<Selection>(Selection.none);
  final _view = GlobalKey<TimelineViewState>();
  late final _thumbnails = Thumbnails(
    (item, tier, tile) => ref
        .read(thumbnailPipelineProvider.future)
        .then((pipeline) => pipeline.load(item as ThumbnailItem, tier, tile)),
    video: (item) => (item as ThumbnailItem).video,
    // The viewer's filmstrip still holds requests when the page goes, and
    // clear() asks this of each.
    cached: (item, tier) =>
        ref.context.mounted &&
        (ref
                .read(thumbnailPipelineProvider)
                .value
                ?.cached(item as ThumbnailItem, tier) ??
            false),
    // Each tile's stages, so that a slow one says which stage was slow.
    onTile: (item, tier, tile) => ref
        .read(loggerProvider)
        .debug('tile', fields: {..._fields(item, tier), ...tile.stages}),
  );

  static Map<String, Object> _fields(Object item, int tier) {
    final uri = (item as ThumbnailItem).uri;
    return {
      'file': uri.isScheme('file') ? uri.toFilePath() : '$uri',
      'tier': tier,
    };
  }

  (TimelineBuckets, TimelinePages)? _shown;
  var _selecting = false;
  // Whether what a restart kept has been restored, which nothing overwrites
  // before (VIEW-36).
  bool? _restored;
  // Built anew for each account (AccountScope), which keeps its own.
  late final String _kept = keptKey(
    ref.read(replicaNameProvider).value,
    'library',
  );
  Warmup? _warmup;
  StreamSubscription<void>? _scans;

  @override
  void initState() {
    super.initState();
    unawaited(_warm());
    _selection.addListener(() {
      _keep('selection', _selection.value.toJson());
      if (_selection.value.isEmpty == _selecting) {
        setState(() => _selecting = !_selecting);
      }
    });
  }

  /// Keeps [value] as [what] of the timeline shown, for a restart.
  void _keep(String what, Object? value) {
    if (_restored != true) return;
    final kept = ref.read(keptProvider)[_kept];
    ref.read(keptProvider.notifier).put(_kept, {
      if (kept is Map<String, Object?>) ...kept,
      'assets': _shown?.$1.assets,
      what: value,
    });
  }

  /// Restores the scroll position, selection and viewer a restart kept,
  /// when the library still has as many items.
  Future<void> _restore(TimelineBuckets buckets, TimelinePages pages) async {
    await ref.read(keptProvider.notifier).loaded;
    if (!mounted) return;
    final kept = ref.read(keptProvider)[_kept];
    if (kept is Map<String, Object?> && kept['assets'] == buckets.assets) {
      _selection.value = Selection.fromJson(kept['selection']);
      if (kept['top'] case final int top) _view.currentState?.scrollTo(top);
      if (kept['viewer'] case final int at) {
        _open(pages, buckets.assets, at, Rect.zero);
      }
    }
    _restored = true;
  }

  // Desktops warm their disk cache with each folder a scan ends, and keep
  // the ThumbHashes of its items; browsers keep only posters there
  // (ADR-0116), phones only the server's tiles, which nothing here makes.
  Future<void> _warm() async {
    try {
      final pipeline = await ref.read(thumbnailPipelineProvider.future);
      final db = await ref.read(replicaProvider.future);
      if (!mounted || kIsWeb || pipeline.decoders.isEmpty) return;
      final warmup = Warmup(
        (item) => pipeline.warm(item, _thumbnails.tier),
        _thumbnails.busy,
        workers: pipeline.workers,
        save: (hashes) => saveThumbHashes(db, hashes),
        report: (summary) => ref
            .read(loggerProvider)
            .info('warm-up', fields: {'summary': summary}),
      );
      setState(() => _warmup = warmup);
      _scans = warmScans(db, warmup.add);
    } on Object {
      // No replica or cache: nothing to warm.
    }
  }

  @override
  void dispose() {
    unawaited(_scans?.cancel());
    _warmup?.dispose();
    _selection.dispose();
    _thumbnails.clear();
    super.dispose();
  }

  /// Opens the viewer at [asset]; the timeline follows it there, so that
  /// closing shrinks it back into the cell of the item it shows.
  void _open(TimelinePages pages, int count, int asset, Rect cell) {
    final position = ValueNotifier(asset);
    _keep('viewer', asset);
    position.addListener(() {
      _view.currentState?.reveal(position.value);
      _keep('viewer', position.value);
    });
    unawaited(
      Navigator.of(context, rootNavigator: true)
          .push(
            ViewerPage.route(
              () => _view.currentState?.cellOf(position.value) ?? cell,
              ViewerPage(
                pages: pages,
                count: count,
                position: position,
                thumbnails: _thumbnails,
              ),
            ),
          )
          .then((_) => _keep('viewer', null)),
    );
  }

  /// Starts decoding [asset] at screen size as a finger touches its cell,
  /// for the viewer a tap opens (docs/10 §4.6).
  void _decode(TimelinePages pages, int asset) {
    if (_selection.value.isEmpty) decodeOnTouch(context, ref, pages, asset);
  }

  // The visible items' metadata is read first (ADR-0072).
  void _visible(TimelinePages pages, int first, int last) {
    _keep('top', first);
    final db = ref.read(replicaProvider).value;
    if (db == null) return;
    extractFirst(db, [
      for (var a = first; a <= last; a++) ?(pages[a] as ThumbnailItem?)?.id,
    ]);
  }

  // The items of [selection], a page at a time.
  static Stream<ThumbnailItem> _items(
    TimelinePages pages,
    Selection selection,
  ) async* {
    for (final (start, end) in selection.ranges) {
      for (var first = start; first < end; first += pages.size) {
        final page = await pages.fetch(first, min(pages.size, end - first));
        yield* Stream.fromIterable(page.cast<ThumbnailItem>());
      }
    }
  }

  Future<void> _download(TimelinePages pages) {
    final selection = _selection.value;
    return download(
      context,
      ref,
      count: selection.count,
      items: () => _items(pages, selection),
    );
  }

  Future<void> _slideshow(TimelinePages pages) {
    final selection = _selection.value;
    return SlideshowPage.show(
      context,
      SlideshowPage(
        pages: pages,
        count: selection.count,
        at: (slide) => selection[slide],
      ),
    );
  }

  // The item's file, or every selected file if it is selected.
  Future<void> _dragOut(TimelinePages pages, int asset) async {
    final selection = _selection.value;
    final items = selection.contains(asset)
        ? await _items(pages, selection).toList()
        : [?pages[asset] as ThumbnailItem?];
    final files = [
      for (final item in items)
        if (item.uri.isScheme('file')) item.uri.toFilePath(),
    ];
    if (files.isNotEmpty) await ref.read(fileDragProvider)?.call(files);
  }

  // The folders of the selected device items leave the library.
  Future<void> _exclude(TimelinePages pages) async {
    final folders = await _items(
      pages,
      _selection.value,
    ).map((item) => item.folder).where((folder) => folder != 0).toSet();
    _selection.value = Selection.none;
    if (mounted) await excludeFolders(context, ref, folders);
  }

  Future<void> _review(TimelinePages pages) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => _Review(_selection, pages, _thumbnails),
    ),
  );

  // Backup's and a new folder's banners, then what a gallery lacks: it needs
  // every photo, so anything less is said, with the way out; so are the edits
  // the server refused.
  List<Widget> _banners(AppLocalizations strings, {required bool folders}) {
    final access = ref.watch(mediaAccessProvider).value;
    final missing = switch (access) {
      MediaAccess.none => strings.mediaAccessNone,
      MediaAccess.partial => strings.mediaAccessPartial,
      _ => null,
    };
    final select = access == MediaAccess.partial
        ? ref.watch(deviceLibraryProvider)?.select
        : null;
    final lost = ref.watch(lostFoldersProvider).value ?? const [];
    final shared = ref.watch(shareInboxProvider);
    final refused = ref.watch(refusedEditsProvider).value ?? const [];
    final why = {for (final edit in refused) edit.error};
    return [
      const UploadBar(),
      const BackupBanner(),
      if (folders) const FreshFolderBanner(),
      if (refused.isNotEmpty)
        MaterialBanner(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.editsRejected(refused.length)),
              if (why.contains(_forbidden))
                Text(strings.editsRejectedForbidden),
              if (why.contains(_gone)) Text(strings.editsRejectedNotFound),
              if (why.difference({_forbidden, _gone}).isNotEmpty)
                Text(strings.editsRejectedInvalid),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => dismissRefusedEdits(ref),
              child: Text(strings.editsRejectedDismiss),
            ),
          ],
        ),
      if (shared > 0)
        MaterialBanner(
          content: Text(strings.shareInboxWaiting(shared)),
          actions: [
            TextButton(
              onPressed: ref.read(shareInboxProvider.notifier).allow,
              child: Text(strings.mediaAccessAllow),
            ),
          ],
        ),
      if (lost.isNotEmpty)
        MaterialBanner(
          content: Text(strings.foldersLost(lost.length)),
          actions: [
            TextButton(
              onPressed: () => allowFolder(ref, lost.first),
              child: Text(strings.foldersAllow),
            ),
          ],
        ),
      if (missing != null)
        MaterialBanner(
          content: Text(missing),
          forceActionsBelow: true,
          actions: [
            if (select != null)
              TextButton(
                onPressed: select,
                child: Text(strings.mediaAccessSelect),
              ),
            TextButton(
              onPressed: ref.read(mediaAccessProvider.notifier).request,
              child: Text(strings.mediaAccessAllow),
            ),
          ],
        ),
    ];
  }

  // A library without items, or whose store or query [failed].
  Widget _empty(AppLocalizations strings, {required bool failed}) => failed
      ? StoreErrorView(retry: () => ref.invalidate(libraryTimelineProvider))
      : EmptyState(
          icon: Icons.photo_library_outlined,
          message: ref.watch(foldersUnsupportedProvider)
              ? strings.foldersUnsupported
              : strings.libraryEmpty,
          action: !canAddFolders(ref)
              ? null
              : FilledButton.icon(
                  onPressed: () => pickFolder(context, ref),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(strings.libraryAddFolder),
                ),
        );

  /// What a selection's bar does to the items selected (docs/10 §5.4), with
  /// device [folders] excluding theirs too.
  List<Widget> _actions(
    AppLocalizations strings,
    TimelinePages pages, {
    required bool folders,
  }) => selectionActions(
    context,
    ref,
    () async {
      final items = await _items(pages, _selection.value).toList();
      _selection.value = Selection.none;
      return [
        for (final item in items)
          if (item.id case final id?)
            (id: id, favourite: item.marks.contains(Mark.favourite)),
      ];
    },
    trash: () => unawaited(_trash(pages)),
    more: [
      IconButton(
        icon: const Icon(Icons.grid_view),
        tooltip: strings.selectionReview,
        onPressed: () => _review(pages),
      ),
      if (folders)
        IconButton(
          icon: const Icon(Icons.folder_off_outlined),
          tooltip: strings.deviceFolderExcludeThis,
          onPressed: () => _exclude(pages),
        ),
    ],
  );

  Future<void> _trash(TimelinePages pages) async {
    final items = await _items(pages, _selection.value).toList();
    if (!mounted) return;
    await deleteItems(
      context,
      ref,
      items,
      chosen: () {
        _selection.value = Selection.none;
        return context;
      },
    );
  }

  Widget _selectionBar(
    AppLocalizations strings,
    TimelinePages pages, {
    required bool folders,
  }) => ValueListenableBuilder(
    valueListenable: _selection,
    builder: (context, selection, _) => SelectionBar(
      count: selection.count,
      onClear: () => _selection.value = Selection.none,
      onSelectAll: () => _view.currentState?.selectAll(),
      onSlideshow: () => _slideshow(pages),
      onDownload: () => _download(pages),
      actions: _actions(strings, pages, folders: folders),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    // A selection keeps the timeline it was made in, so that its positions
    // stay the items the user chose until it is cleared.
    final timeline = ref.watch(libraryTimelineProvider);
    if (!_selecting || _shown == null) _shown = timeline.value;
    if ((_restored, _shown) case (null, (final buckets, final pages))
        when buckets.assets > 0) {
      _restored = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restore(buckets, pages),
      );
    }
    final view = ref.watch(settingsProvider.select((s) => s.library));
    final folders = hasSources(ref);
    // Without a server nothing is backed up, which no badge need say.
    final server = ref.watch(serverProvider).value?.account != null;
    final toolbar = _Toolbar(
      view: view,
      timeline: _view,
      server: server,
      folders: folders,
    );
    return Column(
      children: [
        ..._banners(strings, folders: hasDeviceFolders(ref)),
        if (_shown case (final buckets, final pages)
            when buckets.assets > 0) ...[
          if (_selecting)
            _selectionBar(strings, pages, folders: folders)
          else
            toolbar,
          if (_warmup case final warmup?) _Warming(warmup.progress),
          Expanded(
            child: TimelineView(
              key: _view,
              buckets: buckets,
              pages: pages,
              thumbnails: _thumbnails,
              selection: _selection,
              duration: (item) => ref
                  .read(thumbnailPipelineProvider)
                  .value
                  ?.duration(item as ThumbnailItem),
              sphere: (item) => (item as ThumbnailItem).sphere,
              grouping: view.grouping,
              animated: (item) => (item as ThumbnailItem).animated,
              animation: ref.watch(settingsProvider).isOn(Toggle.animateGrid)
                  ? (item) => ref.read(animationProvider)(item as ThumbnailItem)
                  : null,
              density: view.density,
              onDensity: (density) => ref
                  .read(settingsProvider.notifier)
                  .setLibraryView(view.copyWith(density: density)),
              placeholder: (item) => (item as ThumbnailItem).thumbHash,
              excluded: (item) => (item as ThumbnailItem).excluded,
              marks: (item) => (item as ThumbnailItem).marks,
              badge: server && view.badges
                  ? (item) => _badge(item, strings)
                  : null,
              onOpen: (asset, cell) =>
                  _open(pages, buckets.assets, asset, cell),
              onPress: (asset) => _decode(pages, asset),
              onVisible: (first, last) => _visible(pages, first, last),
              onDragOut: ref.watch(fileDragProvider) == null
                  ? null
                  : (asset) => _dragOut(pages, asset),
            ),
          ),
        ] else if ((_shown, view.backup) case (_?, final backup?)) ...[
          toolbar,
          Expanded(
            child: EmptyState(
              icon: Icons.filter_list_off,
              message: strings.libraryBackupEmpty(backup.sql),
            ),
          ),
        ] else ...[
          // What is hidden, archived or in the trash stays within reach.
          if (_shown != null) _Toolbar(view: view),
          Expanded(child: _empty(strings, failed: timeline.hasError)),
        ],
      ],
    );
  }
}

/// A tile's badge (ADR-0200 proposal 1): none for a backed-up photo, the
/// normal state.
(IconData, String)? _badge(Object item, AppLocalizations strings) {
  final backup = (item as ThumbnailItem).backup;
  final icon = switch (backup) {
    Availability.notBackedUp => Icons.cloud_off_outlined,
    Availability.cloudOnly => Icons.cloud_outlined,
    Availability.backedUp => null,
  };
  return icon == null ? null : (icon, strings.libraryBackup(backup.sql));
}

/// How far the thumbnail warm-up is, while it runs; the timeline stays usable.
class _Warming extends StatelessWidget {
  const new(this.progress);

  final ValueListenable<(int, int)> progress;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: progress,
    builder: (context, progress, _) => switch (progress) {
      (_, 0) => const SizedBox.shrink(),
      (final done, final total) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).libraryWarming(done, total),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: done / total),
          ],
        ),
      ),
    },
  );
}

/// Zoom buttons, the single-pointer alternative to a pinch (I18N-16), the
/// sort and grouping of the library, with a [server] the backup state it
/// shows and its badges (VIEW-05), hidden and archived items shown for a
/// while, the trash, and with device [folders] a while with the excluded ones.
class _Toolbar extends ConsumerWidget {
  const new({
    required this.view,
    this.timeline,
    this.server = false,
    this.folders = false,
  });

  final LibraryView view;

  /// The timeline shown, if any, which zooms.
  final GlobalKey<TimelineViewState>? timeline;
  final bool server;
  final bool folders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final veiled = ref.watch(veiledProvider);
    final views = ref.read(settingsProvider.notifier);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // A filter says so, and goes with a tap; on a narrow screen its name
        // gives way to the buttons.
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: switch (view.backup) {
              final backup? => Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: InputChip(
                  label: Text(
                    strings.libraryBackup(backup.sql),
                    overflow: TextOverflow.ellipsis,
                  ),
                  deleteIcon: const Icon(Icons.clear),
                  onDeleted: () =>
                      views.setLibraryView(view.copyWith(backup: () => null)),
                ),
              ),
              null => null,
            },
          ),
        ),
        IconButton(
          icon: Icon(veiled ? Icons.visibility : Icons.visibility_off_outlined),
          tooltip: veiled
              ? strings.libraryHideVeiled
              : strings.libraryShowVeiled,
          isSelected: veiled,
          onPressed: () =>
              ref.read(veiledProvider.notifier).show(shown: !veiled),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: strings.trashTitle,
          onPressed: () => Navigator.of(context).push(TrashPage.route()),
        ),
        if (timeline case final timeline?) ...[
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: strings.libraryZoomOut,
            onPressed: () => timeline.currentState?.zoom(-1),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: strings.libraryZoomIn,
            onPressed: () => timeline.currentState?.zoom(1),
          ),
          PopupMenuButton<LibraryView>(
            icon: const Icon(Icons.tune),
            tooltip: strings.libraryViewOptions,
            onSelected: views.setLibraryView,
            itemBuilder: (_) => _options(ref, strings),
          ),
        ],
      ],
    );
  }

  // The view menu: sort, grouping, the excluded folders for a while, and with a
  // [server] the backup state shown and the badges.
  List<PopupMenuEntry<LibraryView>> _options(
    WidgetRef ref,
    AppLocalizations strings,
  ) => [
    for (final added in [false, true])
      CheckedPopupMenuItem(
        value: view.copyWith(added: added),
        checked: view.added == added,
        child: Text(strings.librarySort('$added')),
      ),
    const PopupMenuDivider(),
    for (final grouping in Grouping.values)
      CheckedPopupMenuItem(
        value: view.copyWith(grouping: grouping),
        checked: view.grouping == grouping,
        child: Text(strings.libraryGroup(grouping.name)),
      ),
    if (folders) ...[
      const PopupMenuDivider(),
      CheckedPopupMenuItem(
        checked: ref.read(revealProvider),
        onTap: () => ref
            .read(revealProvider.notifier)
            .reveal(on: !ref.read(revealProvider)),
        child: Text(strings.libraryRevealExcluded),
      ),
    ],
    if (server) ...[
      const PopupMenuDivider(),
      for (final backup in [null, ...Availability.values])
        CheckedPopupMenuItem(
          value: view.copyWith(backup: () => backup),
          checked: view.backup == backup,
          child: Text(strings.libraryBackup(backup?.sql ?? 'all')),
        ),
      const PopupMenuDivider(),
      CheckedPopupMenuItem(
        value: view.copyWith(badges: !view.badges),
        checked: view.badges,
        child: Text(strings.libraryBadges),
      ),
    ],
  ];
}

/// What is selected (VIEW-08's "show selected"): a tap deselects an item.
class _Review extends StatelessWidget {
  const new(this.selection, this.pages, this.thumbnails);

  final ValueNotifier<Selection> selection;
  final TimelinePages pages;
  final Thumbnails thumbnails;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: selection,
    builder: (context, selected, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).selectionCount(selected.count),
        ),
      ),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
        ),
        itemCount: selected.count,
        itemBuilder: (context, i) {
          final asset = selected[i];
          return InkWell(
            onTap: () => selection.value = selection.value.toggle(asset),
            child: ThumbnailAt(asset, pages, thumbnails),
          );
        },
      ),
    ),
  );
}
