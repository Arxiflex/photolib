import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_data/photolib_data.dart'
    show keyBetween, localOwner, uuidv7;
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_data/src/sync_message.dart';
import 'package:protobuf/protobuf.dart' show RpcClient;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

part 'outbox.dart';

/// The replica table of each server table that syncs into one; rows travel by
/// table and column name (ADR-0091), and whatever else a server sends is
/// ignored.
const _tables = {
  'libraries': 'library',
  'assets': 'asset',
  'asset_user_state': 'asset_user_state',
  'album_user_state': 'album_user_state',
  'library_user_state': 'library_user_state',
  'asset_files': 'asset_file',
  'versions': 'asset_version',
  'stacks': 'stack',
  'album_folders': 'album_folder',
  'albums': 'album',
  'album_items': 'album_item',
  'album_members': 'album_member',
  'partner_shares': 'partner_share',
  'tags': 'tag',
  'asset_tags': 'asset_tag',
  'persons': 'person',
  'faces': 'face',
};

/// Arrays that the replica keeps comma-separated.
const _lists = {'facets', 'bbox'};

/// The streams of every account; its libraries, album memberships and partner
/// shares open more.
const _accountStreams = ['account', 'libraries', 'albums', 'tags', 'people'];

/// Whether the asset `a` is in an album shared with the account, or a
/// partner's share shows it, as photolibd's does: in a library of the partner's
/// own that its stream sent, taken within its window or shown whole.
const _inSharedAlbum =
    'a.id IN (SELECT asset_id FROM album_item WHERE album_id IN '
    '(SELECT album_id FROM album_member))';
const _shared =
    '($_inSharedAlbum OR EXISTS (SELECT 1 FROM partner_share p '
    'JOIN partner_library l ON l.owner_id = p.owner_id '
    'WHERE p.owner_id = a.owner_id AND l.library_id = a.library_id '
    'AND (p.taken_since IS NULL OR l.whole '
    'OR a.taken_utc >= unixepoch(p.taken_since) * 1000)))';

/// Changes to these may leave rows that nothing shows any more.
const _access = {
  'libraries',
  'library_members',
  'albums',
  'album_members',
  'album_items',
  'partner_shares',
};

/// What losing a membership takes along: the shared library or album, of which
/// the stream of libraries or albums sends no deletion, as it sends only what
/// the account may see.
const _left = {
  'library_members': ('library_id', 'DELETE FROM library WHERE id = ?'),
  'album_members': ('album_id', 'DELETE FROM album WHERE id = ?'),
};

/// The streams a membership or a share opens, by the column with their id: a
/// change to one syncs them again from scratch, as what the account may see
/// there changed with it (ADR-0091).
const _governs = {
  'library_members': ('library_id', ['assets', 'faces']),
  'album_members': ('album_id', ['album_items']),
  'partner_shares': ('owner_id', ['partner']),
};

const _libraryAssets =
    'DELETE FROM asset AS a WHERE txid IS NOT NULL AND library_id = ?1 '
    'AND NOT $_shared';
const _libraryFaces =
    'DELETE FROM face WHERE asset_id IN '
    '(SELECT id FROM asset WHERE library_id = ?1)';
const _partnerAssets =
    'DELETE FROM asset AS a WHERE txid IS NOT NULL AND owner_id = ?1 '
    'AND library_id NOT IN (SELECT id FROM library) AND NOT $_inSharedAlbum';

/// What each kind of stream delivered, which starting it again drops: SQL on
/// the stream's id.
const Map<String, List<String>> _delivered = {
  'account': [
    'DELETE FROM asset_user_state WHERE txid IS NOT NULL',
    'DELETE FROM album_user_state WHERE txid IS NOT NULL',
    'DELETE FROM library_user_state WHERE txid IS NOT NULL',
  ],
  'libraries': [
    'DELETE FROM library WHERE txid IS NOT NULL',
    'DELETE FROM partner_share',
  ],
  'albums': [
    'DELETE FROM album_folder WHERE txid IS NOT NULL',
    'DELETE FROM album WHERE txid IS NOT NULL',
    'DELETE FROM album_member',
  ],
  'tags': ['DELETE FROM tag WHERE txid IS NOT NULL'],
  'people': ['DELETE FROM person WHERE txid IS NOT NULL'],
  'assets': [_libraryAssets],
  'faces': [_libraryFaces],
  'album_items': ['DELETE FROM album_item WHERE album_id = ?1'],
  'partner': [
    _partnerAssets,
    'DELETE FROM partner_library WHERE owner_id = ?1',
  ],
};

/// Drops every row and cursor a server synced into [db] and its partners'
/// libraries, retries the outbox now and marks every backed-up item to
/// re-verify, in one transaction, then tells [notify] or [db]'s clients: after
/// the server was restored (§8), once the replica's account is removed, so
/// that the next server it syncs with shows none of it (ADR-0234), or signed
/// out, as the replica belongs to one account (docs/10-client-app.md §2); the
/// device's own items stay, not backed up until their assets are back.
Future<void> forgetServer(
  Replica db, {
  void Function(Set<TableUpdate>)? notify,
}) async {
  await db.transaction(() async {
    // What hangs off an asset first, so that the trigger finds nothing left.
    for (final table in db.allTables.toList().reversed) {
      if (table.$columns.any((c) => c.name == 'txid')) {
        await db.customStatement(
          'DELETE FROM ${table.actualTableName} WHERE txid IS NOT NULL',
        );
      }
    }
    await db.delete(db.syncCursor).go();
    await db.delete(db.partnerLibrary).go();
    await db.customStatement('UPDATE outbox SET retry_at = NULL');
    await db.customStatement(
      "UPDATE backup_state SET reason = 'reverify' "
      "WHERE state IN ('backed_up', 'linked')",
    );
  });
  (notify ?? db.notifyUpdates)({
    for (final table in [
      ..._tables.values,
      'sync_cursor',
      'partner_library',
      'outbox',
      'backup_state',
      'local_asset',
    ])
      TableUpdate(table),
  });
}

/// How [SyncEngine] marks an item the restored server no longer holds, and
/// one it still does.
const _uploadAgain =
    "UPDATE backup_state SET state = 'selected', reason = 'server_restored', "
    'updated_at = ?2 WHERE local_asset_id = ?1';
const _stillHeld =
    'UPDATE backup_state SET reason = NULL, updated_at = ?2 '
    'WHERE local_asset_id = ?1';

/// How many calls one run makes at most: the first, then one for the streams
/// each opened or reset.
const _calls = 10;

/// The sync engine (docs/05-sync-and-offline.md §3–4, ADR-0120): brings the
/// replica up to date with what [server] streams, one transaction per batch
/// with its cursor. It runs where the replica's writer is, the data isolate,
/// never on the UI's; its `notify` tells the replica's other clients what it
/// changed.
class SyncEngine {
  /// An engine that syncs [db] with [server].
  SyncEngine(
    this.db,
    this.server, {
    void Function(Set<TableUpdate>)? notify,
    int Function()? now,
  }) : _notify = notify ?? db.notifyUpdates,
       _now = now;

  /// The replica it writes.
  final Replica db;

  /// The server it syncs with.
  final Server server;
  final void Function(Set<TableUpdate>) _notify;

  /// The wall clock, in ms since the epoch, which mutations' retries wait by.
  final int Function()? _now;
  final _plans = <String, _Plan?>{};

  /// The streams dropped during a call, whose later batches in it are stale.
  final _dropped = <String>{};

  /// Syncs every stream until each has caught up, those the batches open
  /// included, with a server that has `sync.stream.v1` (ADR-0091). After the
  /// server was restored from a backup, it first syncs everything again and
  /// re-verifies the device's backups (§8).
  Future<void> run() async {
    final refused = <String>{};
    for (var call = 0; ; call++) {
      // Read before each call and after the last, so that a restore while the
      // run lasts is found in it.
      final epoch = await _epoch();
      if (call == _calls) return;
      if (call == 0 &&
          (await server.selectEndpoint()).capabilities.contains(
            'sync.mutations.v1',
          )) {
        final outbox = Mutations(db, notify: _notify, now: _now);
        await outbox.adoptAlbums();
        await outbox.push(server);
      }
      final cursors = {
        for (final c in await db.select(db.syncCursor).get())
          c.stream: c.cursor,
      };
      var follow = (await streams()).difference(refused);
      final due = [
        for (final s in follow)
          if (call == 0 || !cursors.containsKey(s)) s,
      ];
      if (due.isEmpty) return;
      final request = pb.SyncRequest(
        streams: [
          for (final s in due) pb.StreamCursor(stream: s, cursor: cursors[s]),
        ],
      );
      _dropped.clear();
      var checked = false;
      await for (final message in server.sync(request)) {
        final batch = SyncMessage(message);
        // A batch of this call may have closed or dropped a stream that a later
        // one continues.
        if (!follow.contains(batch.stream) || _dropped.contains(batch.stream)) {
          continue;
        }
        final bool access;
        if (batch.status == pb.StreamStatus.STREAM_STATUS_OK.value) {
          access = await _apply(batch, epoch);
        } else {
          if (batch.status !=
              pb.StreamStatus.STREAM_STATUS_RESET_REQUIRED.value) {
            refused.add(batch.stream);
          } else if (!checked) {
            // A restore since the epoch was read resets every stream: their
            // cursors, of the old epoch, stay for the next call's reading of
            // it to drop everything with them.
            checked = true;
            if ((await server.selectEndpoint()).epoch != epoch) break;
          }
          await db.transaction(() => _drop(batch.stream));
          access = true;
        }
        if (access) follow = (await streams()).difference(refused);
      }
    }
  }

  /// The server's epoch, once what an earlier one synced is dropped and the
  /// backups it held are re-verified.
  Future<String> _epoch() async {
    final info = await server.selectEndpoint();
    if (!info.capabilities.contains('sync.stream.v1')) {
      throw UnsupportedError('the server has no sync.stream.v1');
    }
    await _restored(info.epoch);
    await _reverify();
    return info.epoch;
  }

  /// The streams the replica follows.
  Future<Set<String>> streams() async {
    Future<List<String>> ids(String sql) async => [
      for (final row in await db.customSelect(sql).get())
        uuidOf(row.read<Uint8List>('id')),
    ];
    return {
      ..._accountStreams,
      for (final id in await ids(
        'SELECT id FROM library WHERE txid IS NOT NULL',
      )) ...['assets/$id', 'faces/$id'],
      for (final id in await ids('SELECT album_id AS id FROM album_member'))
        'album_items/$id',
      for (final id in await ids('SELECT owner_id AS id FROM partner_share'))
        'partner/$id',
    };
  }

  /// When the cursors are of another epoch, the server was restored:
  /// everything it synced is forgotten.
  Future<void> _restored(String epoch) async {
    final stale = await db
        .customSelect(
          'SELECT 1 FROM sync_cursor WHERE epoch IS NOT ? LIMIT 1',
          variables: [Variable(epoch)],
        )
        .get();
    if (stale.isNotEmpty) await forgetServer(db, notify: _notify);
  }

  /// Asks the server whether it still holds each item marked by
  /// [forgetServer], a thousand at a time: those it does keep their state and
  /// link to its asset, the others are selected to upload again.
  Future<void> _reverify() async {
    final api = pb.SyncServiceApi(server.rpc);
    while (true) {
      final items = await db
          .customSelect(
            'SELECT b.local_asset_id AS id, l.content_hash AS hash '
            'FROM backup_state b '
            'LEFT JOIN local_asset l ON l.id = b.local_asset_id '
            "WHERE b.reason = 'reverify' LIMIT 1000",
          )
          .get();
      if (items.isEmpty) return;
      final hashes = [
        for (final i in items) ?i.readNullable<Uint8List>('hash'),
      ];
      final held = hashes.isEmpty
          ? const <String>[]
          : (await api.checkHashes(
              null,
              pb.CheckHashesRequest(hashes: hashes),
            )).assetIds;
      final now = DateTime.now().millisecondsSinceEpoch;
      var next = 0;
      await db.transaction(() async {
        for (final item in items) {
          final id = item.read<Uint8List>('id');
          final hashed = item.readNullable<Uint8List>('hash') != null;
          final asset = hashed ? held.elementAtOrNull(next++) ?? '' : '';
          await db.customStatement(asset.isEmpty ? _uploadAgain : _stillHeld, [
            id,
            now,
          ]);
          await db.customStatement(
            'UPDATE local_asset SET asset_id = ?2 WHERE id = ?1',
            [id, if (asset.isEmpty) null else _bytes(asset)],
          );
        }
      });
      _notify({
        const TableUpdate('backup_state'),
        const TableUpdate('local_asset'),
      });
    }
  }

  /// Drops what [stream] delivered and its cursor, so that it syncs again from
  /// scratch.
  Future<void> _drop(String stream) async {
    final [kind, ...id] = stream.split('/');
    for (final sql in _delivered[kind] ?? const <String>[]) {
      await db.customStatement(sql, [for (final i in id) _bytes(i)]);
    }
    await (db.delete(
      db.syncCursor,
    )..where((c) => c.stream.equals(stream))).go();
    _dropped.add(stream);
    await _collect();
    _notify({
      for (final table in [..._tables.values, 'sync_cursor'])
        TableUpdate(table),
    });
  }

  /// Drops the rows that no stream the replica follows shows any more, and the
  /// cursors of the streams it no longer follows. Assets of the account's
  /// libraries stay; those of other libraries stay while a shared album or a
  /// partner's share shows them.
  Future<void> _collect() async {
    final followed = await streams();
    await (db.delete(
      db.syncCursor,
    )..where((c) => c.stream.isNotIn(followed))).go();
    await db.customStatement(
      'DELETE FROM album_item WHERE txid IS NOT NULL '
      'AND album_id NOT IN (SELECT id FROM album)',
    );
    await db.customStatement(
      'DELETE FROM partner_library '
      'WHERE owner_id NOT IN (SELECT owner_id FROM partner_share)',
    );
    await db.customStatement(
      'DELETE FROM asset AS a WHERE txid IS NOT NULL AND library_id IN '
      '(SELECT library_id FROM asset WHERE library_id NOT IN '
      '(SELECT id FROM library)) AND NOT $_shared',
    );
  }

  /// Applies [batch] and stores its cursor, in one transaction; returns whether
  /// what the account may see changed.
  Future<bool> _apply(SyncMessage batch, String epoch) async {
    final access = batch.changes.any((r) => _access.contains(r.entity));
    await db.transaction(() async {
      final again = <String>{};
      final waiting = await db
          .customSelect('SELECT 1 FROM outbox WHERE error IS NULL LIMIT 1')
          .get();
      final touched = <String, Set<String>>{};
      for (final rows in batch.changes) {
        final plan = _plan(rows);
        final values = [for (var i = 0; i < rows.length; i++) rows.values(i)];
        // The id in each row's [column], where the rows have one.
        Iterable<String> ids(String column) sync* {
          final at = rows.columns.indexOf(column);
          for (final row in values) {
            if (at >= 0 && at < row.length) yield '${row[at]}';
          }
        }

        if (_keys[rows.entity] case final key? when waiting.isNotEmpty) {
          (touched[rows.entity] ??= {}).addAll(ids(key));
        }
        if (_governs[rows.entity] case (
          final column,
          final kinds,
        ) when !rows.deleted) {
          for (final id in ids(column)) {
            again.addAll([for (final k in kinds) '$k/$id']);
          }
        }
        await db.batch((b) {
          if (_left[rows.entity] case (
            final column,
            final sql,
          ) when rows.deleted) {
            for (final id in ids(column)) {
              b.customStatement(sql, [_bytes(id)]);
            }
          }
          if (plan == null) return;
          for (final row in values) {
            b.customStatement(plan.sql, plan.values(row));
          }
          // A partner's share shows only the partner's own libraries; with a
          // window, undated assets only of those it shows whole. A window
          // that starts later starts the stream again (_governs), which
          // forgets what one without sent.
          if (batch.stream.startsWith('partner/') &&
              rows.entity == 'assets' &&
              !rows.deleted) {
            final assets = [for (final id in ids('id')) _bytes(id)];
            b.customStatement(
              'INSERT INTO partner_library '
              'SELECT owner_id, library_id, max(taken_utc IS NULL) FROM asset '
              'WHERE id IN (${List.filled(assets.length, '?').join(', ')}) '
              'GROUP BY owner_id, library_id '
              'ON CONFLICT (owner_id, library_id) '
              'DO UPDATE SET whole = whole OR excluded.whole',
              assets,
            );
          }
        });
      }
      await _showWaiting(db, touched);
      for (final stream in again) {
        await _drop(stream);
      }
      if (access) await _collect();
      await db
          .into(db.syncCursor)
          .insertOnConflictUpdate(
            SyncCursorCompanion.insert(
              stream: batch.stream,
              cursor: batch.cursor,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              epoch: Value(epoch),
            ),
          );
    });
    _notify({
      const TableUpdate('sync_cursor'),
      for (final rows in batch.changes)
        if (_tables[rows.entity] case final String table) TableUpdate(table),
    });
    return access;
  }

  /// The statement that applies [rows] to its replica table, or null when none
  /// has it.
  _Plan? _plan(SyncRows rows) {
    final key = '${rows.deleted} ${rows.entity} ${rows.columns.join(',')}';
    if (_plans.containsKey(key)) return _plans[key];
    final table = db.allTables
        .where((t) => t.actualTableName == _tables[rows.entity])
        .firstOrNull;
    return _plans[key] = table == null
        ? null
        : _Plan.of(table, rows.columns, deleted: rows.deleted);
  }
}

/// An upsert or a deletion of rows with given columns, and how to bind a row's
/// values to it.
final class _Plan {
  _Plan(this.sql, this._columns);

  final String sql;
  final List<Object? Function(List<Object?>)> _columns;

  List<Object?> values(List<Object?> row) => [for (final c in _columns) c(row)];

  /// Null when [columns] lack a column of the table's key.
  static _Plan? of(
    TableInfo<Table, Object?> table,
    List<String> columns, {
    required bool deleted,
  }) {
    final at = {for (final (i, c) in columns.indexed) c: i};
    final key = table.$primaryKey;
    if (!key.every((c) => at.containsKey(c.name))) return null;
    // A column the server does not send keeps a NOT NULL column's zero value.
    final used = deleted
        ? key.toList()
        : [
            for (final c in table.$columns)
              if (at.containsKey(c.name) ||
                  (!c.$nullable && c.defaultValue == null))
                c,
          ];
    final name = table.actualTableName;
    final names = [for (final c in used) c.name];
    final String sql;
    if (deleted) {
      final where = [for (final n in names) '$n = ?'];
      sql = 'DELETE FROM $name WHERE ${where.join(' AND ')}';
    } else {
      final set = [
        for (final c in used)
          if (!key.contains(c)) '${c.name} = excluded.${c.name}',
      ];
      final values = List.filled(names.length, '?');
      sql =
          'INSERT INTO $name (${names.join(', ')}) '
          'VALUES (${values.join(', ')}) '
          'ON CONFLICT (${[for (final c in key) c.name].join(', ')}) '
          '${set.isEmpty ? 'DO NOTHING' : 'DO UPDATE SET ${set.join(', ')}'}';
    }
    return _Plan(sql, [for (final c in used) _converter(c, at[c.name])]);
  }
}

/// Reads a column of a row as the replica's column [c] takes it: by its type,
/// whatever the server's (a newer server never fails a batch), and its zero
/// value for a NULL that it does not allow.
Object? Function(List<Object?>) _converter(GeneratedColumn c, int? at) {
  final type = c.type;
  final zero = c.$nullable
      ? null
      : switch (type) {
          DriftSqlType.string => '',
          DriftSqlType.blob => Uint8List(0),
          DriftSqlType.double => 0.0,
          _ => 0,
        };
  if (at == null) return (_) => zero;
  final list = _lists.contains(c.name);
  return (row) {
    final v = at < row.length ? row[at] : null;
    final value = switch ((type, v)) {
      (_, null) => null,
      (DriftSqlType.blob, final String s) => _bytes(s),
      (DriftSqlType.blob, final Uint8List b) => b,
      (DriftSqlType.blob, _) => null,
      (DriftSqlType.string, final String s) => list ? _joined(s) : s,
      (DriftSqlType.string, Uint8List()) => null,
      (DriftSqlType.string, _) => '$v',
      (DriftSqlType.double, final num n) => n.toDouble(),
      (DriftSqlType.double, final bool b) => b ? 1.0 : 0.0,
      (DriftSqlType.double, final String s) => double.tryParse(s),
      (_, final int i) => i,
      (_, final double d) => d.round(),
      (_, final bool b) => b ? 1 : 0,
      (_, final String s) => int.tryParse(s),
      _ => null,
    };
    return value ?? zero;
  };
}

/// A JSON array comma-separated.
String _joined(String json) {
  try {
    return (jsonDecode(json) as List).join(',');
  } on Object {
    return json;
  }
}

/// A uuid's 16 bytes, as the replica keeps ids; other text as UTF-8.
Uint8List uuidBytes(String text) => _bytes(text);

/// A uuid's 16 bytes; other text as UTF-8.
Uint8List _bytes(String text) {
  if (text.length != 36) return utf8.encode(text);
  final out = Uint8List(16);
  var j = 0;
  for (var i = 0; i < 36; i++) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (text.codeUnitAt(i) != 0x2d) return utf8.encode(text);
      continue;
    }
    final hi = _nibble(text.codeUnitAt(i));
    final lo = _nibble(text.codeUnitAt(++i));
    if (hi < 0 || lo < 0) return utf8.encode(text);
    out[j++] = hi << 4 | lo;
  }
  return out;
}

int _nibble(int c) => switch (c) {
  >= 0x30 && <= 0x39 => c - 0x30,
  >= 0x61 && <= 0x66 => c - 0x57,
  >= 0x41 && <= 0x46 => c - 0x37,
  _ => -1,
};

/// The uuid of 16 bytes, as stream names and media paths hold it.
String uuidOf(Uint8List bytes) {
  final hex = [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20),
  ].join('-');
}
