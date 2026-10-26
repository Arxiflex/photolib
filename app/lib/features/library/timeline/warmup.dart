import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:photolib_data/photolib_data.dart';

import 'pipeline.dart';
import 'thumbnails.dart';

/// Warms the disk cache (T2) with the tiles of what is [add]ed, [workers] at
/// a time and never while [busy], when the timeline's own decodes and the
/// user's scroll come first, so that a folder just scanned scrolls from the
/// cache; and keeps the ThumbHash of each, [save]d a batch at a time
/// (docs/10-client-app.md §3.4–§3.5, ADR-0107, ADR-0114). Each time its queue
/// drains it [report]s how many it warmed and why each of the rest has no
/// tile.
class Warmup {
  Warmup(this._warm, this.busy, {this.workers = 1, this.save, this.report}) {
    busy.addListener(_next);
  }

  final void Function(String summary)? report;

  /// Warms an item and returns its ThumbHash, if it has none yet.
  final Future<Uint8List?> Function(ThumbnailItem item) _warm;
  final ValueListenable<bool> busy;
  final int workers;
  final Future<void> Function(Map<Uint8List, Uint8List> hashes)? save;
  final _queue = Queue<ThumbnailItem>();
  final _queued = <ThumbnailItem>{};
  final _hashes = <Uint8List, Uint8List>{};
  var _running = 0;
  var _tried = 0;
  final _misses = <(ThumbnailItem, Object)>[];

  /// How many of the items added since it was last done are warm, of how
  /// many.
  final progress = ValueNotifier((0, 0));

  /// The items still to warm.
  int get pending => _queue.length;

  /// Queues [items], but those it holds already.
  void add(List<ThumbnailItem> items) {
    final (done, total) = progress.value;
    final before = _queue.length;
    _queue.addAll(items.where(_queued.add));
    progress.value = (done, total + _queue.length - before);
    _next();
  }

  void _next() {
    while (_running < workers && _queue.isNotEmpty && !busy.value) {
      _running++;
      unawaited(_work());
    }
  }

  Future<void> _work() async {
    while (_queue.isNotEmpty && !busy.value) {
      final item = _queue.removeFirst();
      _queued.remove(item);
      _tried++;
      try {
        if ((await _warm(item), item.id) case (final hash?, final id?)) {
          _hashes[id] = hash;
        }
      } on Object catch (e) {
        _misses.add((item, e));
      }
      final (done, total) = progress.value;
      progress.value = done + 1 < total ? (done + 1, total) : (0, 0);
      if (_hashes.length >= 256) await _flush();
    }
    if (--_running > 0) return;
    if (_queue.isEmpty && _tried > 0) {
      report?.call(_summary());
      _tried = 0;
      _misses.clear();
    }
    await _flush();
  }

  Future<void> _flush() async {
    if (_hashes.isEmpty || save == null) return;
    final hashes = {..._hashes};
    _hashes.clear();
    try {
      await save!(hashes);
    } on Object {
      // The next warm-up computes them again.
    }
  }

  // `warmed 1,204 of 1,210; 6 videos without a poster: a.mp4 (macos: …) | …`,
  // the first 20 of each kind.
  String _summary() {
    final count = NumberFormat.decimalPattern('en').format;
    final summary = [
      'warmed ${count(_tried - _misses.length)} of ${count(_tried)}',
    ];
    for (final (video, kind, what) in [
      (true, 'video', 'without a poster'),
      (false, 'photo', 'without a tile'),
    ]) {
      final misses = [
        for (final (item, e) in _misses)
          if (item.video == video)
            '${item.uri.pathSegments.last} '
                '(${e is NoThumbnail ? e.cause : e})',
      ];
      if (misses.isEmpty) continue;
      final n = misses.length;
      summary.add(
        '${count(n)} $kind${n > 1 ? 's' : ''} $what: '
        '${[...misses.take(20), if (n > 20) '…'].join(' | ')}',
      );
    }
    return summary.join('; ');
  }

  void dispose() {
    busy.removeListener(_next);
    _queue.clear();
    _queued.clear();
  }
}

/// Hands [add] the items of each folder of [db] whose scan ends, newest
/// first, [page] at a time; at start, those without a ThumbHash of the
/// folders not being scanned: indexed before schema 8, or with no tile.
StreamSubscription<void> warmScans(
  Replica db,
  void Function(List<ThumbnailItem> items) add, {
  int page = 500,
}) {
  final scanning = <String>{};
  var backfill = true;
  return watchFolders(db)
      .asyncMap((folders) async {
        for (final folder in folders) {
          if (folder.state == 'scanning') {
            scanning.add(folder.root);
          } else if (scanning.remove(folder.root) && folder.state == 'online') {
            for (TimelineItemData? last; ;) {
              final items = await folderTimeline(
                db,
                folder.root,
                after: last,
                limit: page,
              );
              if (items.isNotEmpty) {
                add([for (final item in items) ThumbnailItem.local(item)]);
              }
              if (items.length < page) break;
              last = items.last;
            }
          }
        }
        if (!backfill) return;
        backfill = false;
        for (TimelineItemData? last; ;) {
          final items = await withoutThumbHash(db, after: last, limit: page);
          if (items.isEmpty) break;
          last = items.last;
          final hashless = [
            for (final item in items)
              if (!scanning.contains(item.volume)) ThumbnailItem.local(item),
          ];
          if (hashless.isNotEmpty) add(hashless);
        }
      })
      .listen(null, onError: (Object _) {});
}
