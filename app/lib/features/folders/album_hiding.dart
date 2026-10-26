import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart' show sessionProvider;
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart' hide Stack;

/// The menu that hides an album of the signed-in account's library from its
/// timeline and from memories (ORG-17): each is a checked item and an edit of
/// the account's own state of the album, which the outbox sends and the server
/// keeps for every device. Nothing for an album only this device made.
class AlbumHidingMenu extends ConsumerStatefulWidget {
  /// The menu of [album].
  const new({required this.album, super.key});

  /// The album's id.
  final Uint8List album;

  @override
  ConsumerState<AlbumHidingMenu> createState() => _AlbumHidingMenuState();
}

class _AlbumHidingMenuState extends ConsumerState<AlbumHidingMenu> {
  StreamSubscription<({bool timeline, bool memories, bool shared})>? _watch;
  ({bool timeline, bool memories, bool shared})? _hiding;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = await ref.read(replicaProvider.future);
    if (!mounted) return;
    _watch = albumHiding(
      db,
      widget.album,
    ).listen((hiding) => setState(() => _hiding = hiding));
  }

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _set(String field, {required bool value}) async {
    final db = await ref.read(replicaProvider.future);
    await Mutations(db).edit('album_user_state', widget.album, {field: value});
  }

  @override
  Widget build(BuildContext context) {
    final hiding = _hiding;
    if (hiding == null ||
        !hiding.shared ||
        ref.watch(sessionProvider) == null) {
      return const SizedBox.shrink();
    }
    final strings = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.visibility_off_outlined),
      tooltip: strings.actionHide,
      onSelected: (field) => _set(
        field,
        value: !(field == 'hide_from_timeline'
            ? hiding.timeline
            : hiding.memories),
      ),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'hide_from_timeline',
          checked: hiding.timeline,
          child: Text(strings.albumHideTimeline),
        ),
        CheckedPopupMenuItem(
          value: 'hide_from_memories',
          checked: hiding.memories,
          child: Text(strings.albumHideMemories),
        ),
      ],
    );
  }
}
