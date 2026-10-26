import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_data/photolib_data.dart';

/// The edits the server refused for good, which were undone, for the library
/// to say why (ADR-0265).
final StreamProvider<List<OutboxData>> refusedEditsProvider =
    StreamProvider.autoDispose((ref) async* {
      final db = await ref.watch(replicaProvider.future);
      yield* Mutations(db).rejected().watch();
    });

/// Forgets the refused edits, once their user has read why.
Future<void> dismissRefusedEdits(WidgetRef ref) async {
  await Mutations(await ref.read(replicaProvider.future)).dismiss();
}

/// Whether hidden and archived items show (ADR-0245): for [shownFor] once
/// the user asks, and never past the app going to the background.
class VeiledNotifier extends Notifier<bool> {
  /// How long they show.
  static const shownFor = Duration(minutes: 5);
  Timer? _timer;

  @override
  bool build() {
    final lifecycle = AppLifecycleListener(onHide: () => show(shown: false));
    ref.onDispose(() {
      _timer?.cancel();
      lifecycle.dispose();
    });
    return false;
  }

  /// Shows them for [shownFor], or hides them again.
  void show({required bool shown}) {
    _timer?.cancel();
    _timer = shown ? Timer(shownFor, () => state = false) : null;
    state = shown;
  }
}

/// Whether hidden and archived items show.
final veiledProvider = NotifierProvider<VeiledNotifier, bool>(
  VeiledNotifier.new,
);

/// The library's timeline while shown, anew whenever the device index or
/// the synced assets change.
final StreamProvider<(TimelineBuckets, TimelinePages)> libraryTimelineProvider =
    StreamProvider.autoDispose((ref) async* {
      final db = await ref.watch(replicaProvider.future);
      yield* libraryTimeline(
        db,
        added: ref.watch(settingsProvider.select((s) => s.library.added)),
        veiled: ref.watch(veiledProvider),
        backup: ref.watch(settingsProvider.select((s) => s.library.backup)),
      );
    });

/// The tiles of the device's items and the account's assets per day, one
/// per photo (ADR-0267), and its [ThumbnailItem]s by position, by date taken
/// or [added] (days in this time zone), hidden and archived ones only when
/// [veiled], only those in [backup] if given, anew on every change but at
/// most once a second, its first page loaded so that the first frame paints
/// ThumbHashes.
Stream<(TimelineBuckets, TimelinePages)> libraryTimeline(
  Replica db, {
  bool added = false,
  bool veiled = false,
  Availability? backup,
  int pageSize = 128,
}) {
  final offset = DateTime.now().timeZoneOffset.inMilliseconds;
  final state = backup?.sql;
  final days = added
      ? db.timelineAddedDays(offset, veiled, state).map((d) => (d.day, d.count))
      : db.timelineDays(veiled, state).map((d) => (d.day, d.count));
  // Days change with every folder setting, which may change what is excluded.
  return everySecond(days.watch()).asyncMap((rows) async {
    final excluded = await excludedFolders(db);
    final buckets = TimelineBuckets(
      days: [for (final (day, _) in rows) day],
      counts: [for (final (_, count) in rows) count],
    );
    final before = [0];
    for (final count in buckets.counts) {
      before.add(before.last + count);
    }
    final pages = TimelinePages((first, count) async {
      // A page starts at the day of its first position.
      var s = 0;
      while (before[s + 1] <= first) {
        s++;
      }
      final day = buckets.days[s];
      final skip = first - before[s];
      final end = DateTime.utc(day ~/ 10000, day ~/ 100 % 100, day % 100 + 1);
      final items = added
          ? db.timelineAddedPage(
              end.millisecondsSinceEpoch - offset,
              veiled,
              state,
              count,
              skip,
            )
          : db.timelinePage(day, veiled, state, count, skip);
      return [
        for (final item in await items.get())
          ThumbnailItem.local(item, excluded: excluded.contains(item.folder)),
      ];
    }, size: pageSize);
    if (buckets.assets > 0) await pages.preload(0);
    return (buckets, pages);
  });
}
