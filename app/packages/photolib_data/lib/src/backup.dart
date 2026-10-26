// app/tool/single_writer_lint.dart reads a package import of this package's
// src/ as a way around the vault.
// ignore_for_file: always_use_package_imports
import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_log/photolib_log.dart';

import 'metadata.dart';
import 'replica.dart';
import 'search.dart' show videoExtensions;

const _log = Logger('photolib.backup');

/// Above every time and size.
const _never = 9007199254740991;

/// What to back up (ING-05, ING-06): the folders chosen, by key, photos,
/// videos, and items taken since a time.
class BackupSelection {
  /// Everything in [folders] marked true.
  const BackupSelection({
    this.folders = const {},
    this.photos = true,
    this.videos = true,
    this.since,
  });

  /// Each folder's choice, by its [BackupFolder] key. The items of a folder
  /// not here wait for the person's answer (`folder_new`).
  final Map<String, bool> folders;

  /// Whether photos are backed up.
  final bool photos;

  /// Whether videos are backed up.
  final bool videos;

  /// The capture time, in UTC milliseconds, before which nothing is.
  final int? since;
}

/// What the device and its network allow a run to send now.
class BackupConditions {
  /// Anything, at once.
  const BackupConditions({
    this.photos = true,
    this.videos = true,
    this.cap,
    this.stop,
  });

  /// Whether the network in use may carry photos: a metered one may not.
  final bool photos;

  /// Whether the network in use may carry videos.
  final bool videos;

  /// The largest item the network in use may carry, in bytes.
  final int? cap;

  /// Why nothing may be sent now, such as `charging`; the run only selects.
  final String? stop;
}

/// A folder of the device's items, as [BackupSelection] names it by `key`.
typedef BackupFolder = ({
  String key,
  String source,
  String volume,
  String dir,
  int items,
});

/// The folders that hold the device's items, each with its key.
Future<List<BackupFolder>> backupFolders(Replica db) async => [
  for (final f in await db.localFolders().get())
    (
      key: '${f.source}:${f.volume}:${f.dir ?? ''}',
      source: f.source,
      volume: f.volume,
      dir: f.dir ?? '',
      items: f.items,
    ),
];

/// Backup at a glance: when a run last left nothing to send, when the first
/// started, why the last stopped, how many of the device's items wait, and
/// when the replica last synced, its last contact with the server.
typedef BackupStatus = ({
  int? completed,
  int? first,
  String? stopped,
  int pending,
  int? contact,
});

/// [BackupStatus] as it changes.
Stream<BackupStatus> watchBackupStatus(Replica db) => db
    .customSelect(
      'SELECT (SELECT MAX(ended) FROM backup_run '
      'WHERE pending = 0 AND stopped IS NULL) AS completed, '
      '(SELECT MIN(started) FROM backup_run) AS first, '
      '(SELECT stopped FROM backup_run ORDER BY id DESC LIMIT 1) AS stopped, '
      '(SELECT COUNT(*) FROM backup_state b '
      'JOIN local_asset a ON a.id = b.local_asset_id '
      "WHERE a.state = 'present' AND a.trashed = 0 "
      "AND b.state NOT IN ('discovered', 'backed_up', 'linked')) AS pending, "
      '(SELECT MAX(updated_at) FROM sync_cursor) AS contact',
      readsFrom: {db.backupRun, db.backupState, db.localAsset, db.syncCursor},
    )
    .watchSingle()
    .map(
      (row) => (
        completed: row.readNullable<int>('completed'),
        first: row.readNullable<int>('first'),
        stopped: row.readNullable<String>('stopped'),
        pending: row.read<int>('pending'),
        contact: row.readNullable<int>('contact'),
      ),
    );

/// The BLAKE3 of a file, or null when it cannot be read.
typedef HashFile = Future<Uint8List?> Function(MediaFile file);

/// A file's bytes from an offset on.
typedef ReadFile = Stream<List<int>> Function(MediaFile file, int offset);

/// The key of an item's folder, as [backupFolders] makes it, in SQL.
const _key =
    "a.source || ':' || a.volume || ':' || COALESCE(CASE a.source "
    "WHEN 'folder' THEN rtrim(a.path, replace(a.path, '/', '')) "
    "ELSE a.path END, '')";

/// Whether an item is a video, as `isVideo` says, in SQL.
final String _video = () {
  final named = [for (final e in videoExtensions) "lower(a.path) LIKE '%.$e'"];
  return "(CASE WHEN COALESCE(a.mime, '') = '' THEN ${named.join(' OR ')} "
      "ELSE lower(a.mime) LIKE 'video/%' END)";
}();

/// The states of a run under way, which the next run resumes.
const _working =
    "'hashing', 'dedup_check', 'preparing', 'uploading', "
    "'verifying'";

/// Refusals every further item would get too: the run stops at the first.
const _stopping = {
  'quota.exceeded',
  'library.contribute_denied',
  'second_factor.required',
};

/// The backup state machine of docs/05-sync-and-offline.md §6 (ADR-0226),
/// the source of truth for what the device has backed up whoever sends the
/// bytes: each item is discovered, selected or not and why, hashed with
/// BLAKE3, linked when the server or another item of the device holds its
/// content, else uploaded (resumable, its upload kept before the first byte
/// goes) and backed up, or failed with a reason and a retry time, or paused by
/// what the network may carry. Runs where the replica's writer is, telling
/// the replica's other clients through `notify` what it changed.
class BackupEngine {
  /// An engine sending through [server], [parallel] uploads at once.
  BackupEngine(
    this.db,
    this.server, {
    required this.hash,
    required this.read,
    this.parallel = 8,
    DateTime Function()? now,
    void Function(Set<TableUpdate>)? notify,
  }) : _now = now ?? DateTime.now,
       _notify = notify ?? db.notifyUpdates;

  /// The replica.
  final Replica db;

  /// The signed-in server.
  final Server server;

  /// Hashes a file.
  final HashFile hash;

  /// Reads a file.
  final ReadFile read;

  /// Uploads, and hashes, at once.
  final int parallel;
  final DateTime Function() _now;
  final void Function(Set<TableUpdate>) _notify;
  var _uploaded = 0;
  var _linked = 0;
  var _failed = 0;
  String? _stop;

  /// The answer that stopped the run, which the log keeps.
  CallError? _cause;

  int get _ms => _now().millisecondsSinceEpoch;

  /// Selects by [selection], pauses what [conditions] do not allow, sends the
  /// rest, tells the server what waits, and returns the run's log entry.
  Future<BackupRunData> run(
    BackupSelection selection,
    BackupConditions conditions,
  ) async {
    final id = await db
        .into(db.backupRun)
        .insert(BackupRunCompanion.insert(started: _ms));
    _log.info('backup started');
    _stop = conditions.stop;
    try {
      await _select(selection);
      await _pause(conditions);
      if (_stop == null) await _send();
    } on CallError catch (error) {
      _stopAt(_stopped(error) ?? error.reason, error);
    }
    final run = BackupRunCompanion(
      ended: Value(_ms),
      uploaded: Value(_uploaded),
      linked: Value(_linked),
      failed: Value(_failed),
      pending: Value(await _pending()),
      stopped: Value(_stop),
    );
    final [ended] = await (db.update(
      db.backupRun,
    )..where((r) => r.id.equals(id))).writeReturning(run);
    _changed();
    if (conditions.stop == null &&
        _stop != 'offline' &&
        _stop != 'signed_out') {
      await _report(ended.pending);
    }
    _log.log(
      LogLevel.info,
      'backup ended',
      fields: {
        'uploaded': _uploaded,
        'linked': _linked,
        'failed': _failed,
        'pending': ended.pending,
        'stopped': ?_stop,
      },
      error: _cause,
    );
    return ended;
  }

  void _stopAt(String? reason, CallError error) {
    _stop = reason;
    _cause = error;
  }

  void _changed() => _notify({
    const TableUpdate('backup_state'),
    const TableUpdate('backup_run'),
    const TableUpdate('local_asset'),
  });

  /// Tells the server what waits, for its watchdog (ADR-0234); a report that
  /// fails waits for the next pass.
  Future<void> _report(int pending) async {
    try {
      await AuthServiceApi(
        server.rpc,
      ).reportBackup(null, ReportBackupRequest(pendingCount: Int64(pending)));
    } on CallError catch (error) {
      _log.info('backup not reported', fields: {'reason': error.reason});
    }
  }

  /// Gives each new item a state, and one changed since it was sent its first
  /// again, and selects or deselects items by [selection], with the reason an
  /// item waits.
  Future<void> _select(BackupSelection selection) async {
    final folders = selection.folders.entries;
    final included = [
      for (final f in folders)
        if (f.value) f.key,
    ];
    final excluded = [
      for (final f in folders)
        if (!f.value) f.key,
    ];
    String marks(List<String> keys) => List.filled(keys.length, '?').join(',');
    final why =
        "CASE WHEN $_key IN (${marks(excluded)}) THEN 'folder_excluded' "
        "WHEN $_key NOT IN (${marks(included)}) THEN 'folder_new' "
        "WHEN IIF($_video, NOT ?, NOT ?) THEN 'type_excluded' "
        'WHEN COALESCE(a.taken_utc, a.taken, a.mtime) < ? '
        "THEN 'before_date' END";
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO backup_state (local_asset_id, state, updated_at) '
        "SELECT id, 'discovered', ? FROM local_asset "
        "WHERE state = 'present' AND trashed = 0 ON CONFLICT DO NOTHING",
        [_ms],
      );
      // An indexer that sees a file change clears its hash: it goes again.
      await db.customStatement(
        "UPDATE backup_state SET state = 'discovered', reason = NULL, "
        'upload = NULL, attempts = 0, retry_at = NULL, updated_at = ? '
        "WHERE state IN ('backed_up', 'linked') AND local_asset_id IN "
        '(SELECT id FROM local_asset WHERE content_hash IS NULL)',
        [_ms],
      );
      await db.customStatement(
        'UPDATE backup_state AS b '
        "SET state = IIF(c.why IS NULL, 'selected', 'discovered'), "
        'reason = c.why, updated_at = ? '
        'FROM (SELECT a.id, $why AS why FROM local_asset a) AS c '
        'WHERE b.local_asset_id = c.id '
        "AND b.state IN ('discovered', 'selected', 'paused', 'failed') "
        "AND IIF(c.why IS NULL, b.state = 'discovered', "
        "b.state <> 'discovered' OR b.reason IS NOT c.why)",
        [
          _ms,
          ...excluded,
          ...included,
          if (selection.videos) 1 else 0,
          if (selection.photos) 1 else 0,
          selection.since ?? -_never,
        ],
      );
    });
  }

  /// Pauses the items due that the network in use may not carry, with why,
  /// and selects again the paused ones it may; an upload under way keeps its
  /// path to resume.
  Future<void> _pause(BackupConditions conditions) => db.customStatement(
    'UPDATE backup_state AS b '
    "SET state = IIF(c.why IS NULL, 'selected', 'paused'), reason = c.why, "
    'updated_at = ? '
    "FROM (SELECT a.id, CASE WHEN IIF($_video, NOT ?, NOT ?) THEN 'metered' "
    "WHEN a.size > ? THEN 'metered_cap' END AS why FROM local_asset a) AS c "
    'WHERE b.local_asset_id = c.id '
    "AND (b.state IN ('selected', 'paused', $_working) "
    "OR b.state = 'failed' AND b.retry_at <= ?) "
    "AND IIF(c.why IS NULL, b.state = 'paused', "
    "b.state <> 'paused' OR b.reason IS NOT c.why)",
    [
      _ms,
      if (conditions.videos) 1 else 0,
      if (conditions.photos) 1 else 0,
      conditions.cap ?? _never,
      _ms,
    ],
  );

  /// Sends the items due, a batch at a time, newest found first, until none
  /// is left or a refusal stops the run.
  Future<void> _send() async {
    // Above every id.
    var after = Uint8List.fromList(List.filled(17, 0xff));
    while (_stop == null) {
      final batch = await _batch(after);
      if (batch.isEmpty) return;
      after = batch.last.id;
      final hashed = await _hash(batch);
      final List<_Item> send;
      final List<_Item> twins;
      try {
        (send, twins) = await _check(hashed);
      } on CallError {
        await _set([
          for (final i in hashed)
            if (i.upload == null) i,
        ], 'selected');
        rethrow;
      }
      await _inParallel(send, _uploadOne);
      if (_stop == null) await _linkCopies(twins);
      _changed();
    }
  }

  Future<List<_Item>> _batch(Uint8List after) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT b.local_asset_id AS id, b.upload, b.attempts, a.source, '
              'a.path, a.name, a.size, a.mtime, a.content_hash, '
              "CASE a.source WHEN 'folder' THEN a.volume ELSE c.root END "
              'AS root FROM backup_state b '
              'JOIN local_asset a ON a.id = b.local_asset_id '
              'LEFT JOIN volume_cursor c '
              'ON c.source = a.source AND c.volume = a.volume '
              "WHERE b.local_asset_id < ? AND a.state = 'present' "
              "AND a.trashed = 0 AND (b.state IN ('selected', $_working) "
              "OR b.state = 'failed' AND b.retry_at <= ?) "
              'ORDER BY b.local_asset_id DESC LIMIT 1000',
              variables: [Variable(after), Variable(_ms)],
            )
            .get())
      _Item.of(row),
  ];

  /// Hashes the items of [batch] without a hash, keeping each hash unless the
  /// file changed meanwhile; returns the items with one.
  Future<List<_Item>> _hash(List<_Item> batch) async {
    final unhashed = [
      for (final i in batch)
        if (i.hash == null) i,
    ];
    await _set(unhashed, 'hashing');
    // As many at once as uploads: each holds a file open, and a batch of
    // them at once ran out of a 1,024-file limit.
    await _inParallel(unhashed, (item) async {
      if (item.file case final file?) item.hash = await hash(file);
    });
    await db.batch((b) {
      for (final item in unhashed) {
        if (item.hash case final hash?) {
          b.customStatement(
            'UPDATE local_asset SET content_hash = ? '
            'WHERE id = ? AND size = ? AND mtime = ?',
            [hash, item.id, item.size, item.mtime],
          );
        }
      }
    });
    for (final item in unhashed) {
      if (item.hash == null) await _fail(item, 'unreadable');
    }
    return [
      for (final i in batch)
        if (i.hash != null) i,
    ];
  }

  /// Links the items of [items] whose content the device or the server holds
  /// already; returns those to upload, one per content, and their copies.
  Future<(List<_Item>, List<_Item>)> _check(List<_Item> items) async {
    final fresh = [
      for (final i in items)
        if (i.upload == null) i,
    ];
    final rest = await _linkCopies(fresh);
    final held = rest.isEmpty
        ? const <String>[]
        : (await pb.SyncServiceApi(server.rpc).checkHashes(
            null,
            pb.CheckHashesRequest(hashes: [for (final i in rest) ?i.hash]),
          )).assetIds;
    final send = [
      for (final i in items)
        if (i.upload != null) i,
    ];
    final twins = <_Item>[];
    final sending = <String>{};
    final linked = <(_Item, Uint8List?)>[];
    for (final (n, item) in rest.indexed) {
      final asset = held.elementAtOrNull(n) ?? '';
      if (asset.isNotEmpty) {
        linked.add((item, _uuid(asset)));
      } else if (sending.add(item.hex)) {
        send.add(item);
      } else {
        twins.add(item);
      }
    }
    await _link(linked, null);
    return (send, twins);
  }

  /// Links the items of [items] that have a copy on the device backed up, to
  /// its asset; returns the others.
  Future<List<_Item>> _linkCopies(List<_Item> items) async {
    if (items.isEmpty) return items;
    final copies = {
      for (final row
          in await db
              .customSelect(
                'SELECT l.content_hash AS hash, MAX(l.asset_id) AS asset '
                'FROM local_asset l '
                'JOIN backup_state s ON s.local_asset_id = l.id '
                "WHERE s.state IN ('backed_up', 'linked') "
                'AND l.content_hash IN '
                '(${List.filled(items.length, '?').join(',')}) '
                'GROUP BY l.content_hash',
                variables: [for (final i in items) Variable(i.hash)],
              )
              .get())
        _hex(row.read<Uint8List>('hash')): row.readNullable<Uint8List>('asset'),
    };
    final rest = <_Item>[];
    final linked = <(_Item, Uint8List?)>[];
    for (final item in items) {
      if (copies.containsKey(item.hex)) {
        linked.add((item, copies[item.hex]));
      } else {
        rest.add(item);
      }
    }
    await _link(linked, 'duplicate');
    return rest;
  }

  /// Links each item to its asset, in one batch.
  Future<void> _link(List<(_Item, Uint8List?)> items, String? reason) async {
    await db.batch((b) {
      for (final (item, asset) in items) {
        b
          ..customStatement(
            "UPDATE backup_state SET state = 'linked', reason = ?, "
            'upload = NULL, attempts = 0, retry_at = NULL, updated_at = ? '
            'WHERE local_asset_id = ?',
            [reason, _ms, item.id],
          )
          ..customStatement(
            'UPDATE local_asset SET asset_id = ? WHERE id = ?',
            [asset, item.id],
          );
      }
    });
    _linked += items.length;
  }

  /// Runs [each] on [items], [parallel] at a time, until a refusal stops the
  /// run.
  Future<void> _inParallel(
    List<_Item> items,
    Future<void> Function(_Item) each,
  ) async {
    final queue = items.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty && _stop == null) {
        await each(queue.removeAt(0));
      }
    }

    await Future.wait([for (var w = 0; w < parallel; w++) worker()]);
  }

  Future<void> _uploadOne(_Item item) async {
    try {
      await _sendBytes(item);
      await _write(item, 'backed_up');
      _uploaded++;
    } on CallError catch (error) {
      final stop = _stopped(error);
      if (stop != null || _stop != null) {
        // The run stops here, or stopped at another upload: this one waits
        // for the next run.
        if (_stop == null) _stopAt(stop, error);
        await _write(item, _waiting(item), upload: item.upload);
        return;
      }
      final reason = error.reason;
      if (_stopping.contains(reason)) _stopAt(reason, error);
      if (reason == 'upload.hash_mismatch') await _changedFile(item);
      await _fail(item, reason, refused: true);
    } on _Shorter {
      await _changedFile(item);
      await _fail(item, 'changed');
    } on Exception catch (error) {
      _log.warning('unreadable', fields: {'path': ?item.path}, error: error);
      await _fail(item, 'unreadable');
    }
  }

  /// Creates the item's upload unless it has one, keeps its path before any
  /// byte goes, then sends what the server lacks; an upload the server forgot
  /// starts over once.
  Future<void> _sendBytes(_Item item) async {
    final file = item.file;
    if (file == null) throw const FormatException('no root');
    var upload = item.upload;
    if (upload == null) {
      upload = item.upload = await server.createUpload(
        null,
        item.size,
        item.hex,
        path: file.path,
      );
      await _write(item, 'uploading', upload: upload);
    }
    try {
      await server.sendUpload(
        upload,
        item.size,
        (offset) => _whole(read(file, offset), item.size - offset),
      );
    } on ServerError catch (error) {
      if (error.code != 'not_found' || item.resumed) rethrow;
      item
        ..upload = null
        ..resumed = true;
      await _sendBytes(item);
    }
  }

  Future<void> _changedFile(_Item item) => db.customStatement(
    'UPDATE local_asset SET content_hash = NULL WHERE id = ?',
    [item.id],
  );

  /// Fails [item] until a retry 1, 2, 4 … minutes later, hours for a
  /// server's refusal (photolib-design#719), at most a day.
  Future<void> _fail(_Item item, String reason, {bool refused = false}) async {
    final attempts = item.attempts + 1;
    final wait = Duration(
      minutes: min((refused ? 60 : 1) << min(attempts - 1, 11), 24 * 60),
    );
    await _write(
      item,
      'failed',
      reason: reason,
      attempts: attempts,
      retry: _ms + wait.inMilliseconds,
    );
    _failed++;
  }

  Future<void> _write(
    _Item item,
    String state, {
    String? reason,
    String? upload,
    int attempts = 0,
    int? retry,
  }) => db.customStatement(
    'UPDATE backup_state SET state = ?, reason = ?, upload = ?, attempts = ?, '
    'retry_at = ?, updated_at = ? WHERE local_asset_id = ?',
    [
      state,
      reason,
      upload,
      if (state == 'uploading') item.attempts else attempts,
      retry,
      _ms,
      item.id,
    ],
  );

  Future<void> _set(List<_Item> items, String state) async {
    if (items.isEmpty) return;
    await db.customStatement(
      'UPDATE backup_state SET state = ?, updated_at = ? WHERE local_asset_id '
      'IN (${List.filled(items.length, '?').join(',')})',
      [state, _ms, for (final i in items) i.id],
    );
  }

  Future<int> _pending() async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM backup_state b '
                'JOIN local_asset a ON a.id = b.local_asset_id '
                "WHERE a.state = 'present' AND a.trashed = 0 "
                "AND b.state NOT IN ('discovered', 'backed_up', 'linked')",
              )
              .getSingle())
          .read<int>('n');
}

/// Why a run stops at [error], which every further call would get too: the
/// session ended, or the server is out of reach; null for an item's refusal.
String? _stopped(CallError error) => switch (error) {
  _ when error.logsOut => 'signed_out',
  Unreachable() => 'offline',
  _ => null,
};

/// The state an interrupted upload waits in: resumed when it has an upload.
String _waiting(_Item item) => item.upload == null ? 'selected' : 'uploading';

extension on CallError {
  String get reason => switch (this) {
    final ServerError e => e.detail?.code ?? e.code,
    Unreachable() => 'offline',
  };
}

/// An item a run sends, and what it learns of it on the way.
class _Item {
  _Item.of(QueryRow row)
    : id = row.read<Uint8List>('id'),
      upload = row.readNullable<String>('upload'),
      attempts = row.read<int>('attempts'),
      size = row.read<int>('size'),
      mtime = row.read<int>('mtime'),
      hash = row.readNullable<Uint8List>('content_hash'),
      path = row.readNullable<String>('path'),
      file = switch ((
        row.readNullable<String>('root'),
        row.readNullable<String>('path'),
      )) {
        (final root?, final path?) => (
          root: root,
          path: row.read<String>('source') == 'folder'
              ? path
              : '$path${row.readNullable<String>('name') ?? ''}',
        ),
        _ => null,
      };

  final Uint8List id;
  final int attempts;
  final int size;
  final int mtime;
  final String? path;

  /// Where its bytes are; null when the device cannot say.
  final MediaFile? file;
  Uint8List? hash;
  String? upload;

  /// Whether its upload was forgotten by the server and started again.
  bool resumed = false;

  String get hex => _hex(hash ?? const []);
}

/// A file shorter than when it was hashed: it changed since.
class _Shorter implements Exception {
  const _Shorter();
}

/// [data], failing with [_Shorter] when it ends before [length] bytes.
Stream<List<int>> _whole(Stream<List<int>> data, int length) async* {
  var got = 0;
  await for (final bytes in data) {
    got += bytes.length;
    yield bytes;
  }
  if (got < length) throw const _Shorter();
}

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// A uuid's 16 bytes.
Uint8List _uuid(String text) {
  final hex = text.replaceAll('-', '');
  return Uint8List.fromList([
    for (var i = 0; i + 1 < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// Whether the device item [id] is backed up, as its backup state changes.
Stream<bool> backedUp(Replica db, Uint8List id) => db
    .customSelect(
      "SELECT state IN ('backed_up', 'linked') AS done FROM backup_state "
      'WHERE local_asset_id = ?1',
      variables: [Variable(id)],
      readsFrom: {db.backupState},
    )
    .watchSingleOrNull()
    .map((row) => row?.read<bool>('done') ?? false);
