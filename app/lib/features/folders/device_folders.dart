import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_library.dart';
import 'package:photolib/core/errors.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/folders/folders.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/source_tree.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_data/photolib_data.dart';

/// Whether this device's library is in folders the user can show or keep
/// out: Android's MediaStore buckets (ADR-0210).
bool hasDeviceFolders(WidgetRef ref) =>
    ref.watch(deviceLibraryProvider) is MediaStore;

/// Whether the library has sources the user can show or keep out: device
/// folders, or folders a desktop or Chromium adds (ADR-0290).
bool hasSources(WidgetRef ref) => hasDeviceFolders(ref) || canAddFolders(ref);

/// The first device folder new since the first index, while shown.
final StreamProvider<FreshFolderResult?> freshFolderProvider =
    StreamProvider.autoDispose((ref) async* {
      yield* (await ref.watch(replicaProvider.future))
          .freshFolder()
          .watchSingleOrNull();
    });

/// How long the library shows the excluded folders when asked to.
const revealFor = Duration(minutes: 5);

/// Whether the library shows the excluded device folders for now, their
/// items marked, until [revealFor] has passed.
class RevealNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  /// Shows the excluded folders [on], or no more.
  Future<void> reveal({required bool on}) async {
    _timer?.cancel();
    state = on;
    final db = await ref.read(replicaProvider.future);
    if (on) _timer = Timer(revealFor, () => reveal(on: false));
    await revealExcluded(db, on ? DateTime.now().add(revealFor) : null);
  }
}

/// See [RevealNotifier].
final revealProvider = NotifierProvider<RevealNotifier, bool>(
  RevealNotifier.new,
);

/// Keeps the device folders [ids] out of the library, and says so with a way
/// back to their visibilities before.
Future<void> excludeFolders(
  BuildContext context,
  WidgetRef ref,
  Set<int> ids,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);
  final db = await ref.read(replicaProvider.future);
  final before = await (db.select(
    db.deviceFolder,
  )..where((f) => f.id.isIn(ids))).get();
  for (final id in ids) {
    await showFolder(db, id, shown: false);
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(strings.deviceFoldersExcludedNow),
      action: SnackBarAction(
        label: strings.actionUndo,
        onPressed: () async {
          for (final f in before) {
            await setVisibility(
              db,
              f.volume,
              f.path,
              SourceVisibility.values.byName(f.visibility),
            );
          }
        },
      ),
    ),
  );
}

/// Opens the device item [id] as another app asks: in the viewer, its folder
/// the swipe context whether the library shows it or not, saying so once
/// when not. M1-18's open-with and share targets call it.
Future<void> openInFolder(
  BuildContext context,
  WidgetRef ref,
  Uint8List id,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final notice = AppLocalizations.of(context).deviceFolderExcludedNotice;
  final db = await ref.read(replicaProvider.future);
  final excluded = await excludedFolders(db);
  final items = [
    for (final item in await folderContextOf(db, id))
      ThumbnailItem.local(item, excluded: excluded.contains(item.folder)),
  ];
  final at = items.indexWhere((item) => listEquals(item.id, id));
  if (at < 0 || !context.mounted) return;
  if (items[at].excluded) {
    messenger.showSnackBar(SnackBar(content: Text(notice)));
  }
  await openInViewer(context, ref, items, at: at);
}

/// Says which device folder came after the first index, to keep it in the
/// library or exclude it.
class FreshFolderBanner extends ConsumerWidget {
  /// A banner while a folder is new.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final fresh = ref.watch(freshFolderProvider).value;
    if (fresh == null) return const SizedBox.shrink();
    Future<void> answer({required bool keep}) async {
      await showFolder(
        await ref.read(replicaProvider.future),
        fresh.id,
        shown: keep,
      );
    }

    return MaterialBanner(
      leading: const Icon(Icons.create_new_folder_outlined),
      content: Text(
        strings.deviceFolderNew(fresh.name, strings.folderItems(fresh.items)),
      ),
      actions: [
        TextButton(
          onPressed: () => answer(keep: true),
          child: Text(strings.deviceFolderKeep),
        ),
        TextButton(
          onPressed: () => answer(keep: false),
          child: Text(strings.deviceFolderExclude),
        ),
      ],
    );
  }
}

/// Settings' Library section, where the device has sources: the way to
/// [SourcesPage].
class LibrarySection extends ConsumerWidget {
  /// The section.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    if (!hasSources(ref)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: AppTokens.of(context).lg),
        Text(
          strings.settingsLibrary,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_special_outlined),
          title: Text(_title(strings, ref)),
          onTap: () => context.push('/settings/folders'),
        ),
      ],
    );
  }
}

String _title(AppLocalizations strings, WidgetRef ref) =>
    hasDeviceFolders(ref) ? strings.deviceFolders : strings.settingsFolders;

/// Settings › Library › Device folders, or Folders on desktops and in
/// Chromium: the device's sources as one tree, a root added from here.
class SourcesPage extends ConsumerWidget {
  /// The page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(strings, ref)),
        actions: [
          if (canAddFolders(ref))
            IconButton(
              onPressed: () => pickFolder(context, ref),
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: strings.libraryAddFolder,
            ),
        ],
      ),
      body: const Sources(),
    );
  }
}

/// The device's sources while shown, anew on a change to them but at most
/// once a second, as a scan commits a directory at a time.
final StreamProvider<SourceNode> sourceTreeProvider =
    StreamProvider.autoDispose((ref) async* {
      // The replica first: a rebuild the lost folders caused while it opened
      // would cancel this at the await, and its failure would go uncaught.
      final db = await ref.watch(replicaProvider.future);
      final lost = {...?ref.watch(lostFoldersProvider).value};
      yield* everySecond(watchSourceTree(db, lost: lost));
    });

/// The [SourceTree] of the replica: its eyes and menus write the folders'
/// visibilities, its rows offer what their state allows; [onPick] picks one.
class Sources extends ConsumerWidget {
  /// The tree.
  const new({super.key, this.onPick});

  /// Picks a node, as search's folder filter does.
  final void Function(SourceNode node)? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(sourceTreeProvider);
    // A failed check of the lost folders too: else they would show readable.
    if (tree is AsyncError || ref.watch(lostFoldersProvider) is AsyncError) {
      return StoreErrorView(
        retry: () => ref
          ..invalidate(lostFoldersProvider)
          ..invalidate(sourceTreeProvider),
      );
    }
    final root = tree.value;
    if (root == null) return const SizedBox.shrink();
    Future<Replica> db() => ref.read(replicaProvider.future);
    return SourceTree(
      root: root,
      onPick: onPick,
      onShow: (node, {required shown}) async {
        await show(await db(), node.volume, node.key, shown: shown);
      },
      onAction: (node, action) async {
        final replica = await db();
        await switch (action) {
          SourceAction.showOnly => hideOthers(replica, node, everywhere: true),
          SourceAction.showEverything => showEverything(replica, node),
          SourceAction.hideOthers => hideOthers(replica, node),
        };
      },
      actions: (node) => _actions(context, ref, node),
    );
  }

  /// What [node]'s state offers: a scan's progress, access again, removing
  /// a root, forgetting a folder that is gone.
  List<Widget> _actions(BuildContext context, WidgetRef ref, SourceNode node) {
    final strings = AppLocalizations.of(context);
    final browser = ref.read(browserFoldersProvider);
    final root = node.kind == SourceKind.root;
    Future<Replica> db() => ref.read(replicaProvider.future);
    return [
      if (node.state == SourceState.scanning && root)
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      if (root &&
          (node.state == SourceState.lost ||
              (browser != null && node.state == SourceState.offline)))
        IconButton(
          icon: const Icon(Icons.lock_open_outlined),
          tooltip: strings.folderAllow,
          onPressed: () async {
            await (browser == null
                ? allowFolder(ref, node.volume)
                : browser.allow(await db(), node.volume));
          },
        ),
      if (root)
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: strings.folderRemove,
          onPressed: () => removeFolderOnceConfirmed(context, ref, node.volume),
        ),
      if (node.id case final id? when node.state == SourceState.gone)
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: strings.deviceFolderForget,
          onPressed: () async {
            await forgetFolder(await db(), id);
          },
        ),
    ];
  }
}
