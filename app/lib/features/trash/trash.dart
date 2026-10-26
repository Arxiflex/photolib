import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/deletion.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/library.dart' show veiledProvider;
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart';

const _log = Logger('photolib.organise');

/// What is in the trash, the soonest to go first, after purging what is past
/// its time; hidden items only while they are shown.
final StreamProviderFamily<List<LocalAssetData>, bool> trashProvider =
    StreamProvider.autoDispose.family((ref, veiled) async* {
      final service = await ref.watch(deletionProvider.future);
      try {
        await service.purgeExpired();
      } on Object catch (error, stack) {
        _log.warning('expired items kept', error: error, stackTrace: stack);
      }
      yield* service.db.trashItems(veiled).watch();
    });

/// How many assets of the signed-in server's libraries are in its trash,
/// which only emptying it deletes for good, or its retention (ADR-0386).
final StreamProvider<int> serverTrashProvider = StreamProvider.autoDispose((
  ref,
) async* {
  final db = await ref.watch(replicaProvider.future);
  yield* db
      .customSelect(
        'SELECT count(*) AS n FROM asset WHERE trashed_at IS NOT NULL',
        readsFrom: {db.asset},
      )
      .watchSingle()
      .map((row) => row.read<int>('n'));
});

/// Moves the device items of [ids] to their trash and the library's [assets]
/// to the library's (ADR-0267), [count] items in all, offering to undo it
/// where Photolib can (docs/10 §5.4): nothing asks first but the platform, at
/// most once for them all.
Future<void> moveToTrash(
  BuildContext context,
  WidgetRef ref,
  List<Uint8List> ids, {
  List<Uint8List> assets = const [],
  int? count,
}) async {
  final service = await ref.read(deletionProvider.future);
  if (!context.mounted) return;
  final library = Mutations(service.db);
  Future<void> mark({required bool trashed}) async {
    for (final asset in assets) {
      await library.edit('assets', asset, {'trashed_at': trashed ? 0 : null});
    }
  }

  await _undoable(
    context,
    AppLocalizations.of(context).trashMoved(count ?? ids.length),
    // A refusal of the platform's dialog leaves the library's copies too.
    () async {
      final undoable = ids.isEmpty || await service.trash(ids);
      await mark(trashed: true);
      return undoable;
    },
    () async {
      await service.restore(ids);
      await mark(trashed: false);
    },
  );
}

/// Hides or, unless [hide], archives the items of [ids], offering to undo
/// it; unless [value], shows them again.
Future<void> veil(
  BuildContext context,
  WidgetRef ref,
  List<Uint8List> ids, {
  required bool hide,
  bool value = true,
}) async {
  final db = await ref.read(replicaProvider.future);
  if (!context.mounted) return;
  final strings = AppLocalizations.of(context);
  final set = hide ? setHidden : setArchived;
  if (!value) {
    await tryChange(context, () => set(db, ids, value: false));
    return;
  }
  await _undoable(
    context,
    hide ? strings.veilHidden(ids.length) : strings.veilArchived(ids.length),
    () => set(db, ids, value: true).then((_) => true),
    () => set(db, ids, value: false),
  );
}

/// Marks the items of [ids] favourite, or not.
Future<void> favourite(
  BuildContext context,
  WidgetRef ref,
  List<Uint8List> ids, {
  required bool value,
}) async {
  final db = await ref.read(replicaProvider.future);
  if (!context.mounted) return;
  await tryChange(
    context,
    () => setFavorite(db, ref.read(mediaPlatformProvider), ids, value: value),
  );
}

/// A selected item: its id and whether it is a favourite.
typedef Chosen = ({Uint8List id, bool favourite});

/// What a selection's bar does to the items [chosen] hands over, which
/// clears the selection (docs/10 §5.4): favourites them, or takes the mark
/// off when all have it, moves them to the trash, or does [trash] instead,
/// then [more], and a menu that hides or archives them, or takes back what
/// shows for a while. The page's [context] outlives the menu and the bar.
List<Widget> selectionActions(
  BuildContext context,
  WidgetRef ref,
  Future<List<Chosen>> Function() chosen, {
  VoidCallback? trash,
  List<Widget> more = const [],
}) {
  final strings = AppLocalizations.of(context);
  VoidCallback apply(
    Future<void> Function(List<Uint8List> ids, List<Chosen> items) change,
  ) =>
      () => unawaited(
        chosen().then(
          (items) => context.mounted
              ? change([for (final i in items) i.id], items)
              : null,
        ),
      );
  return [
    IconButton(
      icon: const Icon(Icons.favorite_border),
      tooltip: strings.actionFavourite,
      onPressed: apply(
        (ids, items) => favourite(
          context,
          ref,
          ids,
          value: !items.every((i) => i.favourite),
        ),
      ),
    ),
    IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: strings.actionTrash,
      onPressed: trash ?? apply((ids, _) => moveToTrash(context, ref, ids)),
    ),
    ...more,
    PopupMenuButton<VoidCallback>(
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        for (final (hide, value, label) in [
          (true, true, strings.actionHide),
          (false, true, strings.actionArchive),
          // Only what shows for a while can be hidden already.
          if (ref.read(veiledProvider)) ...[
            (true, false, strings.actionUnhide),
            (false, false, strings.actionUnarchive),
          ],
        ])
          PopupMenuItem(
            value: apply(
              (ids, _) => veil(context, ref, ids, hide: hide, value: value),
            ),
            child: Text(label),
          ),
      ],
    ),
  ];
}

/// Runs [change], then says [done] with a way to [undo] it, unless [change]
/// returns that it cannot be undone.
Future<void> _undoable(
  BuildContext context,
  String done,
  Future<bool> Function() change,
  Future<void> Function() undo,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);
  var undoable = false;
  if (!await tryChange(context, () async => undoable = await change())) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(done),
      action: undoable
          ? SnackBarAction(
              label: strings.actionUndo,
              onPressed: () => _report(messenger, strings, undo),
            )
          : null,
    ),
  );
}

/// Runs [change], saying in a snack bar when it failed.
Future<bool> tryChange(BuildContext context, Future<void> Function() change) =>
    _report(
      ScaffoldMessenger.of(context),
      AppLocalizations.of(context),
      change,
    );

/// Runs [change]; says when it failed, but not when the user refused the
/// platform's dialog.
Future<bool> _report(
  ScaffoldMessengerState messenger,
  AppLocalizations strings,
  Future<void> Function() change,
) async {
  try {
    await change();
    return true;
  } on Object catch (error, stack) {
    if (error is PlatformException && error.code == 'refused') return false;
    _log.warning('change failed', error: error, stackTrace: stack);
    messenger.showSnackBar(SnackBar(content: Text(strings.errorTitle)));
    return false;
  }
}
