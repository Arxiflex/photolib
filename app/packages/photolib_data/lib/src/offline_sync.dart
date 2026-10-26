// tool/single_writer_lint.dart: the store's own files import each other
// by relative paths.
// ignore_for_file: always_use_package_imports

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'offline_plan.dart';
import 'offline_policy.dart';
import 'offline_store.dart';
import 'replica.dart';

/// The server cannot be reached: the pass waits for the network.
class OfflineUnreachable implements Exception {
  /// The server did not answer, because of [cause].
  const OfflineUnreachable([this.cause]);

  /// What the network said.
  final Object? cause;

  @override
  String toString() => 'OfflineUnreachable($cause)';
}

/// The server has no such file (yet).
class OfflineMissing implements Exception {
  /// There is no such file.
  const OfflineMissing();
}

/// Opens the body of `media/<asset>/<role>` of the signed-in server, through
/// the app's network stack; throws [OfflineUnreachable] or [OfflineMissing].
typedef OfflineFetch = Future<Stream<List<int>>> Function(String path);

/// What one pin has of what it wants.
class PinProgress {
  /// A pin with [files] to hold, [have] of them held, and so on.
  const PinProgress({
    this.files = 0,
    this.have = 0,
    this.bytes = 0,
    this.haveBytes = 0,
    this.left = 0,
    this.leftBytes = 0,
  });

  /// The files the pin plans that fit the budget.
  final int files;

  /// How many of them are held.
  final int have;

  /// Their bytes on disk.
  final int bytes;

  /// The held ones' bytes on disk.
  final int haveBytes;

  /// The files that did not fit the budget.
  final int left;

  /// Their bytes on disk.
  final int leftBytes;

  /// Whether everything it wants is held.
  bool get complete => have == files && left == 0;

  PinProgress _held(int size) => PinProgress(
    files: files,
    have: have + 1,
    bytes: bytes,
    haveBytes: haveBytes + size,
    left: left,
    leftBytes: leftBytes,
  );

  PinProgress _planned(int size, {required bool held, required bool fits}) =>
      PinProgress(
        files: files + (fits ? 1 : 0),
        have: have + (fits && held ? 1 : 0),
        bytes: bytes + (fits ? size : 0),
        haveBytes: haveBytes + (fits && held ? size : 0),
        left: left + (fits ? 0 : 1),
        leftBytes: leftBytes + (fits ? 0 : size),
      );
}

/// Where a pass of [OfflineSync] is, for the settings and the albums.
class OfflineProgress {
  /// The progress of a store that holds [used] of [budget] bytes.
  const OfflineProgress({
    this.used = 0,
    this.budget = 0,
    this.pins = const {},
    this.running = false,
    this.waiting = false,
    this.failed = 0,
    this.kept = const {},
  });

  /// The bytes the store takes on disk.
  final int used;

  /// Its budget.
  final int budget;

  /// By pin id; the library's baseline under [OfflinePin.libraryId].
  final Map<String, PinProgress> pins;

  /// Whether a pass is downloading.
  final bool running;

  /// Whether the last pass stopped for want of the network: *will download
  /// when online*.
  final bool waiting;

  /// Files the server refused for good in the last pass.
  final int failed;

  /// The assets, in hex, whose every file the plan wants is held: *kept on
  /// this device*. One set the pass goes on changing: copy it to keep it.
  final Set<String> kept;
}

/// Keeps the offline store as the policy and the pins say (MOB-15, LIB-20):
/// each pass plans, drops what the plan no longer wants (an unpinned album's
/// files), then fetches what is missing in the plan's order, never past the
/// budget. A new pass takes over from a running one.
class OfflineSync {
  /// Syncs [store] with the server's files over [fetch] by the replica [db].
  OfflineSync({
    required this.db,
    required this.store,
    required this.fetch,
    this.search,
    this.parallel = 4,
    this.ceiling = Keep.originals,
  });

  /// The replica that says which files an asset has.
  final Replica db;

  /// Where the files are kept.
  final OfflineStore store;

  /// Opens a file of the server.
  final OfflineFetch fetch;

  /// The assets a search pin's results are.
  final Future<List<Uint8List>> Function(OfflinePin pin)? search;

  /// How many files it fetches at once.
  final int parallel;

  /// The most it keeps of an item: a browser keeps no originals.
  final Keep ceiling;

  final _progress = StreamController<OfflineProgress>.broadcast(sync: true);
  OfflineProgress _state = const OfflineProgress();
  var _generation = 0;
  Future<void> _pass = Future.value();
  StoragePolicy? _policy;
  List<OfflinePin> _pins = const [];
  var _closed = false;

  /// The state after each file and each pass.
  Stream<OfflineProgress> get progress => _progress.stream;

  /// The state now.
  OfflineProgress get state => _state;

  /// Makes the store what [policy] and [pins] say, and completes when the
  /// pass ends: all fetched, the network lost ([OfflineProgress.waiting]) or
  /// another pass taking over.
  Future<void> reconcile(StoragePolicy policy, List<OfflinePin> pins) {
    _policy = policy;
    _pins = pins;
    final mine = ++_generation;
    return _pass = _pass.then((_) => _run(mine));
  }

  /// Tries again what the last pass could not fetch, if it waited.
  Future<void> retry() {
    final policy = _policy;
    return policy == null ? Future.value() : reconcile(policy, _pins);
  }

  /// Stops, and completes once nothing is under way.
  Future<void> close() async {
    _closed = true;
    _generation++;
    await _pass;
    await _progress.close();
  }

  bool _current(int generation) => generation == _generation && !_closed;

  void _emit(OfflineProgress state) {
    _state = state;
    if (!_progress.isClosed) _progress.add(state);
  }

  Future<void> _run(int generation) async {
    final policy = _policy;
    if (!_current(generation) || policy == null) return;
    store.budget = policy.budget;
    final plan = await planOffline(
      db,
      policy,
      _pins,
      search: search,
      ceiling: ceiling,
    );
    if (!_current(generation)) return;
    final fit = plan.within(store.budget, store.sealedSize);
    await store.retain({for (final f in fit.chosen) f.key});
    if (!_current(generation)) return;
    final pass = _Pass(this, generation, _tally(fit.chosen, fit.left))
      ..count(fit.chosen);
    await pass.run([
      for (final f in fit.chosen)
        if (!store.has(f.key)) f,
    ]);
  }

  // What each pin wants and has before the pass fetches anything.
  Map<String, PinProgress> _tally(
    List<PlannedFile> chosen,
    List<PlannedFile> left,
  ) {
    final pins = <String, PinProgress>{};
    void add(PlannedFile f, {required bool fits}) {
      pins[f.pin] = (pins[f.pin] ?? const PinProgress())._planned(
        store.sealedSize(f.size),
        held: store.has(f.key),
        fits: fits,
      );
    }

    for (final f in chosen) {
      add(f, fits: true);
    }
    for (final f in left) {
      add(f, fits: false);
    }
    for (final pin in _pins) {
      pins.putIfAbsent(pin.id, () => const PinProgress());
    }
    return pins;
  }
}

/// One pass of [OfflineSync]: a few workers take the files to fetch in turn.
class _Pass {
  _Pass(this._sync, this._generation, this._pins);

  final OfflineSync _sync;
  final int _generation;
  final Map<String, PinProgress> _pins;
  var _failed = 0;
  var _waiting = false;
  // For each asset the plan wants files of: how many, and how many are held.
  final _wanted = <String, int>{};
  final _held = <String, int>{};
  final _kept = <String>{};

  bool get _live => _sync._current(_generation);

  void _publish({required bool running}) => _sync._emit(
    OfflineProgress(
      used: _sync.store.used,
      budget: _sync.store.budget,
      pins: Map.of(_pins),
      running: running,
      waiting: _waiting,
      failed: _failed,
      kept: _kept,
    ),
  );

  // Counts the files [chosen] wants of each asset and those held already.
  void count(List<PlannedFile> chosen) {
    for (final f in chosen) {
      _wanted[f.assetHex] = (_wanted[f.assetHex] ?? 0) + 1;
    }
    for (final f in chosen) {
      if (_sync.store.has(f.key)) _holds(f.assetHex);
    }
  }

  void _holds(String asset) {
    final held = _held[asset] = (_held[asset] ?? 0) + 1;
    if (held == _wanted[asset]) _kept.add(asset);
  }

  Future<void> run(List<PlannedFile> todo) async {
    _publish(running: todo.isNotEmpty);
    var next = 0;
    Future<void> worker() async {
      while (_live && !_waiting && next < todo.length) {
        await _fetch(todo[next++]);
        if (_live) _publish(running: true);
      }
    }

    await Future.wait([
      for (var i = 0; i < min(todo.length, _sync.parallel); i++) worker(),
    ]);
    if (_live) _publish(running: false);
  }

  Future<void> _fetch(PlannedFile file) async {
    final store = _sync.store;
    try {
      final body = await _sync.fetch('media/${_uuid(file.asset)}/${file.role}');
      await store.put(file.key, body.takeWhile((_) => _live), size: file.size);
      _pins[file.pin] = (_pins[file.pin] ?? const PinProgress())._held(
        store.sealedSize(file.size),
      );
      _holds(file.assetHex);
    } on OfflineUnreachable {
      _waiting = true;
    } on OfflineMissing {
      _failed++;
    } on BudgetExceeded {
      _failed++;
    } on SizeMismatch {
      // Cut short by a new pass, or not the size the replica has.
      if (_live) _failed++;
    } on Exception {
      // The body broke off: the network went.
      _waiting = true;
    }
  }
}

String _uuid(Uint8List id) {
  final h = [for (final b in id) b.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
