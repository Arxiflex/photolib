import 'dart:async';
import 'dart:io';

import 'package:photolib_data/src/file_system.dart';
import 'package:photolib_data/src/folder_indexer.dart';
import 'package:photolib_data/src/folders.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_log/photolib_log.dart';

export 'file_system.dart' show isNetworkShare, networkMount;

const _log = Logger('photolib.index');

/// Desktops add folders by path ([addFolder]); only browsers need [BrowserFolders].
const BrowserFolders? browserFolders = null;

/// Keeps the folder [root] indexed until [stop] (docs/10-client-app.md §8.1): a full scan at once, scans of what file
/// system events name, and full scans every [poll] while events cannot be trusted — on a network share, while the drive
/// is away, after a watch failed, or past [watchLimit] watches (Linux needs one per directory, and defaults to half of
/// `max_user_watches`; macOS and Windows watch the tree) — and every [reconcile] regardless.
class FolderWatcher {
  FolderWatcher(
    this.indexer,
    this.root, {
    this.poll = const Duration(minutes: 1),
    this.reconcile = const Duration(hours: 1),
    int? watchLimit,
  }) : _limit = watchLimit ?? _inotifyLimit() {
    _timer = Timer.periodic(poll, (_) {
      if (!_trusted || DateTime.now().difference(_scanned) >= reconcile) {
        _queue('', true);
      }
    });
    _queue('', true);
  }

  final FolderIndexer indexer;
  final String root;
  final Duration poll, reconcile;
  final int _limit;
  late final Timer _timer;
  late final _network = isNetworkShare(root);
  final _watches = <String, StreamSubscription<FileSystemEvent>>{};
  final _queued = <(String, bool)>{};
  Future<void>? _running;
  var _trusted = false, _stopped = false;
  var _scanned = DateTime(0), _retry = DateTime(0);

  /// Stops watching once the scan under way ends.
  Future<void> stop() async {
    _stopped = true;
    _timer.cancel();
    _unwatch('', const {});
    await _running;
  }

  void _queue(String dir, bool recursive) {
    if (_stopped) return;
    _queued.add((dir, recursive));
    _running ??= _drain();
  }

  Future<void> _drain() async {
    try {
      // A burst of events names the same directories.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      while (_queued.isNotEmpty && !_stopped) {
        final (dir, recursive) = _queued.first;
        _queued.remove((dir, recursive));
        final entered = <String>{};
        final bool online;
        try {
          online = await indexer.scan(
            root,
            dir: dir,
            recursive: recursive,
            entering: recursive
                ? (d) {
                    entered.add(d);
                    _watch(d);
                  }
                : null,
          );
        } on Exception catch (e) {
          // An I/O or database failure must not end the data isolate; the next poll scans again.
          _log.warning(
            'scan failed',
            fields: {'root': root, 'dir': dir},
            error: e,
          );
          _trusted = false;
          continue;
        }
        if (!online) {
          _unwatch('', const {}); // Away: polled until it is back.
          _trusted = false;
        } else if (recursive) {
          _unwatch(dir, entered);
          if (dir.isEmpty) {
            _scanned = DateTime.now();
            _trusted = _watches.isNotEmpty;
          }
        }
      }
    } finally {
      _running = null;
    }
  }

  /// Watches [dir] before a scan lists it, so that no change after the listing goes unseen.
  void _watch(String dir) {
    if (_stopped ||
        _network ||
        DateTime.now().isBefore(_retry) ||
        !Platform.isLinux && dir.isNotEmpty) {
      return;
    }
    _watches[dir] ??= Directory(nativePath(root, dir))
        .watch(recursive: !Platform.isLinux)
        .listen(
          _event,
          onError: (_) => _lost(poll),
          onDone: () => dir.isEmpty ? _lost() : null,
        );
    if (_watches.length > _limit) {
      _log.info(
        'too many directories to watch: polling',
        fields: {'root': root, 'limit': _limit},
      );
      _retry = DateTime.now().add(reconcile);
      _unwatch('', const {});
    }
  }

  /// Cancels the watches of [dir] and below, except those of [keep].
  void _unwatch(String dir, Set<String> keep) {
    for (final d in _watches.keys.toList()) {
      if ((dir.isEmpty || d == dir || d.startsWith('$dir/')) &&
          !keep.contains(d)) {
        _watches.remove(d)!.cancel();
      }
    }
  }

  /// Falls back to a full scan now and polling, with no watches for [pause].
  void _lost([Duration pause = Duration.zero]) {
    _log.info('watch lost: scanning, then polling', fields: {'root': root});
    _retry = DateTime.now().add(pause);
    _unwatch('', const {});
    _trusted = false;
    _queue('', true);
  }

  void _event(FileSystemEvent e) {
    for (final path in [e.path, if (e is FileSystemMoveEvent) ?e.destination]) {
      final rel = relativePath(root, path);
      if (rel == null) continue; // Moved out of the folder.
      if (rel.isEmpty) return _lost();
      final slash = rel.lastIndexOf('/');
      _queue(slash < 0 ? '' : rel.substring(0, slash), false);
      if (e.isDirectory) _queue(rel, true);
    }
  }
}

int _inotifyLimit() {
  try {
    return int.parse(
          File(
            '/proc/sys/fs/inotify/max_user_watches',
          ).readAsStringSync().trim(),
        ) ~/
        2;
  } on Exception {
    return 1 << 30;
  }
}

/// Watches every folder of [db] as folders are added and removed; the data isolate does it on desktops.
StreamSubscription<void> watchLibraryFolders(Replica db) {
  final indexer = FolderIndexer(db);
  final watchers = <String, FolderWatcher>{};
  return watchFolders(db)
      .map((folders) => {for (final f in folders) f.root})
      .distinct((a, b) => a.length == b.length && a.containsAll(b))
      .listen((roots) {
        for (final root in [...watchers.keys]) {
          if (roots.contains(root)) continue;
          _log.info('folder removed', fields: {'root': root});
          watchers.remove(root)!.stop();
        }
        for (final root in roots) {
          watchers[root] ??= () {
            _log.info(
              'watching folder',
              fields: {'root': root, 'network': isNetworkShare(root)},
            );
            return FolderWatcher(indexer, root);
          }();
        }
      });
}
