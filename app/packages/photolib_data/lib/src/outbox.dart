part of 'sync.dart';

/// The replica's key column of each server table whose rows a device edits.
const _keys = {
  'versions': 'id',
  'assets': 'id',
  'asset_user_state': 'asset_id',
  'album_items': 'id',
  'albums': 'id',
  'album_user_state': 'album_id',
  'library_user_state': 'library_id',
};

/// What `Mutations.emptyServerTrash` got: the items `queued` for deletion, or
/// the `held` count (null when none) that the user confirms with `token`.
typedef TrashEmptying = ({int queued, int? held, String token});

/// The most mutations one call sends, as photolibd takes.
const _pushed = 500;

/// The device's edits (docs/05-sync-and-offline.md §5, ADR-0265). Each shows
/// in the replica at once and waits in the outbox, with an idempotency key and
/// a reading of the device's hybrid logical clock, until the server has it;
/// then what the server holds of its row replaces it, and the edits still
/// waiting show over that again. One the server refuses for good is so rolled
/// back, and stays in [rejected] until its user has seen it.
class Mutations {
  /// The edits of [db]; [now] is the wall clock in ms since the epoch, and
  /// [notify] tells the replica's clients what changed.
  Mutations(
    this.db, {
    int Function()? now,
    void Function(Set<TableUpdate>)? notify,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _notify = notify ?? db.notifyUpdates;

  /// The replica edited.
  final Replica db;
  final int Function() _now;
  final void Function(Set<TableUpdate>) _notify;

  /// Sets [fields] of the row [id] of the server's table [entity]: an asset's
  /// `title`, `description`, `rating`, `color_label`, `archived` or
  /// `trashed_at` (any time trashes it, at the edit's; null restores it); the
  /// account's own `favorite` and `hidden_from_memories` of the asset [id]
  /// (`asset_user_state`); an album item's `sort_key`.
  Future<void> edit(String entity, Uint8List id, Map<String, Object?> fields) =>
      _record(
        entity,
        id,
        pb.Mutation(
          edit: pb.FieldEdit(
            entity: entity,
            id: uuidOf(id),
            fields: [
              for (final MapEntry(:key, :value) in fields.entries)
                MapEntry(key, _value(value)),
            ],
          ),
        ),
      );

  /// Adds a version to the history of [asset] (roadmap M8-01, ADR-0391): the
  /// edit [recipe], an encoded `photolib.model.v1.EditRecipe`, which continues
  /// [parent] or else the version now current, and makes it the current one.
  /// It shows at once; a version never changes, and the server keeps the
  /// recipe in the kernel's canonical form. Returns the new version's id.
  Future<Uint8List> addVersion(
    Uint8List asset,
    List<int> recipe, {
    String? label,
    Uint8List? parent,
  }) async {
    final id = uuidv7();
    final from = parent ?? await currentVersion(asset);
    await _record(
      'versions',
      id,
      pb.Mutation(
        version: pb.VersionEdit(
          assetId: uuidOf(asset),
          versionId: uuidOf(id),
          parentId: from == null ? '' : uuidOf(from),
          label: label ?? '',
          recipe: recipe,
        ),
      ),
    );
    await revert(asset, id);
    return id;
  }

  /// Makes [version], one of [asset]'s, its current one: a revert when it is
  /// an older one. The latest such edit by clock wins on every device, and
  /// no version changes.
  Future<void> revert(Uint8List asset, Uint8List version) =>
      edit('assets', asset, {'current_version_id': uuidOf(version)});

  /// The version of [asset] that is current, if it has one.
  Future<Uint8List?> currentVersion(Uint8List asset) async => (await (db.select(
    db.asset,
  )..where((a) => a.id.equals(asset))).getSingleOrNull())?.currentVersionId;

  /// Adds [asset] to [album], last in its custom order.
  Future<void> addToAlbum(Uint8List album, Uint8List asset) async {
    final last = await db
        .customSelect(
          'SELECT max(sort_key) AS k FROM album_item '
          "WHERE album_id = ? AND sort_key <> ''",
          variables: [Variable(album)],
        )
        .getSingle();
    await _member(album, asset, keyBetween(last.readNullable('k'), null));
  }

  /// Removes [asset] from [album].
  Future<void> removeFromAlbum(Uint8List album, Uint8List asset) =>
      _member(album, asset, null);

  /// Moves the album item [item] between the items [after] and [before] of
  /// its album, either null for an end.
  Future<void> moveInAlbum(
    Uint8List item, {
    Uint8List? after,
    Uint8List? before,
  }) async {
    Future<String?> key(Uint8List? id, String sql) async => id == null
        ? null
        : (await db
                  .customSelect(sql, variables: [Variable(id)])
                  .getSingleOrNull())
              ?.read<String>('k');
    const at = 'SELECT sort_key AS k FROM album_item WHERE id = ?';
    final low = await key(after, at);
    var high = await key(before, at);
    // Neighbours of one key, as concurrent adds may make: the next key after.
    if (low != null && high != null && high.compareTo(low) <= 0) {
      high = await key(
        after,
        'SELECT min(b.sort_key) AS k FROM album_item a JOIN album_item b '
        'ON b.album_id = a.album_id AND b.sort_key > a.sort_key '
        'WHERE a.id = ?',
      );
    }
    await edit('album_items', item, {'sort_key': keyBetween(low, high)});
  }

  /// Hands the albums this device made (the nil owner, ADR-0217) to the
  /// account under their own ids: a title and description edit that creates
  /// the album, and an add for each of its items, which name server assets by
  /// the `asset_id` of the device item they stand for. An album waits until
  /// every item is on the server, and is adopted once: the server's answer
  /// gives it an owner, and until then its edits wait in the outbox. Returns
  /// how many albums were queued.
  Future<int> adoptAlbums() => db.transaction(() async {
    final albums = await db
        .customSelect(
          'SELECT a.id, a.title, a.description FROM album a '
          'WHERE a.owner_id = ?1 AND NOT EXISTS (SELECT 1 FROM outbox o '
          "WHERE o.entity = 'albums' AND o.entity_id = a.id "
          'AND o.error IS NULL) ORDER BY a.created_at, a.id',
          variables: [Variable(localOwner)],
          readsFrom: {db.album, db.outbox},
        )
        .get();
    var adopted = 0;
    for (final album in albums) {
      final id = album.read<Uint8List>('id');
      final items = await db
          .customSelect(
            'SELECT coalesce(l.asset_id, i.asset_id) AS asset, i.sort_key, '
            'EXISTS (SELECT 1 FROM asset s WHERE s.id = '
            'coalesce(l.asset_id, i.asset_id)) AS known '
            'FROM album_item i LEFT JOIN local_asset l ON l.id = i.asset_id '
            "WHERE i.album_id = ?1 AND i.kind = 'asset' "
            'ORDER BY i.sort_key, i.id',
            variables: [Variable(id)],
            readsFrom: {db.albumItem, db.localAsset, db.asset},
          )
          .get();
      if (items.any((i) => !i.read<bool>('known'))) continue;
      await edit('albums', id, {
        'title': album.read<String>('title'),
        'description': album.readNullable<String>('description'),
      });
      for (final item in items) {
        await _member(id, item.read<Uint8List>('asset'), item.read('sort_key'));
      }
      adopted++;
    }
    return adopted;
  });

  /// Asks the server at [rpc] to empty the account's trash for good: files
  /// and objects go through its intent log, and every device learns of each
  /// deletion by sync. A trash of more than 1,000 items or 5 % of the account
  /// waits for the user: the answer then has the `held` count to show and the
  /// token that, passed as `confirmToken`, confirms exactly that count.
  Future<TrashEmptying> emptyServerTrash(
    RpcClient rpc, {
    String confirmToken = '',
  }) async {
    final answer = await pb.SyncServiceApi(
      rpc,
    ).emptyTrash(null, pb.EmptyTrashRequest(confirmToken: confirmToken));
    return (
      queued: answer.queued.toInt(),
      held: answer.hasHeld() ? answer.held.count.toInt() : null,
      token: answer.hasHeld() ? answer.held.token : '',
    );
  }

  /// The mutations the server refused for good, oldest first, each with why
  /// (`error`), for the UI to tell its user.
  Selectable<OutboxData> rejected() => db.select(db.outbox)
    ..where((o) => o.error.isNotNull())
    ..orderBy([(o) => OrderingTerm(expression: o.seq)]);

  /// Forgets the [rejected] mutations, once their user has seen them.
  Future<void> dismiss() =>
      (db.delete(db.outbox)..where((o) => o.error.isNotNull())).go();

  Future<void> _member(Uint8List album, Uint8List asset, String? key) =>
      _record(
        'album_items',
        itemId(album, asset),
        pb.Mutation(
          member: pb.MemberEdit(
            entity: 'album_items',
            setId: uuidOf(album),
            elementId: uuidOf(asset),
            present: key != null,
            sortKey: key,
          ),
        ),
      );

  /// Shows [mutation] of the row [id] of [entity] and adds it to the outbox,
  /// at the next reading of the clock, in one transaction.
  Future<void> _record(
    String entity,
    Uint8List id,
    pb.Mutation mutation,
  ) async {
    await db.transaction(() async {
      final now = _now();
      await db.customStatement(
        'INSERT INTO clock (device_id, ms, counter) SELECT ?, 0, 0 '
        'WHERE NOT EXISTS (SELECT 1 FROM clock)',
        [uuidv7()],
      );
      final [clock] = await db.customWriteReturning(
        'UPDATE clock SET ms = max(ms, ?1), '
        'counter = CASE WHEN ?1 > ms THEN 0 ELSE counter + 1 END '
        'RETURNING device_id, ms, counter',
        variables: [Variable(now)],
      );
      final key = uuidv7();
      mutation
        ..mutationId = uuidOf(key)
        ..hlc = pb.Hlc(
          physicalMs: Int64(clock.read<int>('ms')),
          counter: clock.read<int>('counter'),
          deviceId: uuidOf(clock.read<Uint8List>('device_id')),
        )
        ..recordedAt = Timestamp.fromDateTime(
          DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
        );
      await _show(db, mutation);
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              mutationId: key,
              entity: entity,
              entityId: id,
              mutation: mutation.writeToBuffer(),
              createdAt: now,
            ),
          );
    });
    _notify({
      const TableUpdate('clock'),
      TableUpdate(_tables[entity] ?? entity),
    });
  }

  /// Sends the waiting mutations to [server] in the order they were made and
  /// applies its answers, until none waits, the first waits for its retry or
  /// an answer leaves one unsettled. A failed call puts them off, twice as
  /// long each time up to an hour, and rethrows.
  Future<void> push(Server server) async {
    final api = pb.SyncServiceApi(server.rpc);
    while (true) {
      final now = _now();
      final waiting = await db.pendingOutbox(1 << 62, _pushed).get();
      if (waiting.isEmpty || (waiting.first.retryAt ?? now) > now) return;
      final pb.PushMutationsResponse answer;
      try {
        answer = await api.pushMutations(
          null,
          pb.PushMutationsRequest(
            mutations: [
              for (final o in waiting) pb.Mutation.fromBuffer(o.mutation),
            ],
          ),
        );
      } on Object {
        final wait = min(1000 << min(waiting.first.attempts + 1, 12), 3600000);
        await db.customStatement(
          'UPDATE outbox SET attempts = attempts + 1, retry_at = ? '
          'WHERE error IS NULL',
          [now + wait],
        );
        _notify({const TableUpdate('outbox')});
        rethrow;
      }
      if (!await _settle(waiting, answer)) return;
    }
  }

  /// Settles [sent] by [answer] in one transaction: drops the applied, keeps
  /// the refused with why, applies the rows the server holds and shows what
  /// still waits over them. Returns whether it settled every one.
  Future<bool> _settle(
    List<OutboxData> sent,
    pb.PushMutationsResponse answer,
  ) async {
    final results = {for (final r in answer.results) r.mutationId: r};
    await db.transaction(() async {
      for (final o in sent) {
        final result = results[uuidOf(o.mutationId)];
        if (result == null) continue;
        await db.customStatement(
          result.hasRejected()
              ? 'UPDATE outbox SET error = ?2 WHERE seq = ?1'
              : 'DELETE FROM outbox WHERE seq = ?1',
          [o.seq, if (result.hasRejected()) result.rejected.code],
        );
      }
      final touched = <String, Set<String>>{};
      for (final rows in answer.rows) {
        final table = _replicaTable(db, rows.entity);
        final plan = table == null
            ? null
            : _Plan.of(table, rows.columns, deleted: rows.deleted);
        if (plan == null) continue;
        final at = rows.columns.indexOf(_keys[rows.entity] ?? '');
        for (final row in rows.rows) {
          final values = [for (final v in row.values) _raw(v)];
          await db.customStatement(plan.sql, plan.values(values));
          if (at >= 0) (touched[rows.entity] ??= {}).add('${values[at]}');
        }
      }
      await _showWaiting(db, touched);
      await db.customStatement(
        'UPDATE clock SET ms = ?1, counter = 0 WHERE ms < ?1',
        [answer.clock.physicalMs.toInt()],
      );
    });
    _notify({
      for (final table in ['outbox', 'clock', ..._tables.values])
        TableUpdate(table),
    });
    return sent.every((o) => results.containsKey(uuidOf(o.mutationId)));
  }
}

/// The id of [asset]'s item in [album], the same on every device
/// (photolib.sync.v1.MemberEdit).
Uint8List itemId(Uint8List album, Uint8List asset) {
  final hash = sha256.convert([
    ...utf8.encode('photolib.album_item'),
    ...album,
    ...asset,
  ]);
  final id = Uint8List.fromList(hash.bytes.sublist(0, 16));
  id[6] = id[6] & 0x0f | 0x80;
  id[8] = id[8] & 0x3f | 0x80;
  return id;
}

TableInfo<Table, dynamic>? _replicaTable(Replica db, String entity) =>
    db.allTables.where((t) => t.actualTableName == _tables[entity]).firstOrNull;

/// A user field's value: text, an integer, a flag or null.
pb.Value _value(Object? value) => switch (value) {
  null => pb.Value(),
  final String text => pb.Value(text: text),
  final int integer => pb.Value(integer: Int64(integer)),
  final bool boolean => pb.Value(boolean: boolean),
  _ => throw ArgumentError.value(value, 'value', 'is no user field value'),
};

Object? _raw(pb.Value value) => switch (value.whichKind()) {
  pb.Value_Kind.text => value.text,
  pb.Value_Kind.integer => value.integer.toInt(),
  pb.Value_Kind.real => value.real,
  pb.Value_Kind.boolean => value.boolean,
  pb.Value_Kind.blob => Uint8List.fromList(value.blob),
  pb.Value_Kind.notSet => null,
};

/// Shows the mutations still waiting of the rows [touched] names, by server
/// table, over what those rows now hold.
Future<void> _showWaiting(Replica db, Map<String, Set<String>> touched) async {
  for (final MapEntry(key: entity, value: ids) in touched.entries) {
    final waiting =
        await (db.select(db.outbox)
              ..where(
                (o) =>
                    o.error.isNull() &
                    o.entity.equals(entity) &
                    o.entityId.isIn([for (final id in ids) _bytes(id)]),
              )
              ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
            .get();
    for (final o in waiting) {
      await _show(db, pb.Mutation.fromBuffer(o.mutation));
    }
  }
}

/// Shows [mutation] in the replica as the server holds it once applied,
/// unless a later edit overrides it there.
Future<void> _show(Replica db, pb.Mutation mutation) async {
  if (mutation.hasMember()) {
    final m = mutation.member;
    final (album, asset) = (_bytes(m.setId), _bytes(m.elementId));
    await db.customStatement(
      m.present
          // An item synced under another id stands for the asset already.
          ? 'INSERT INTO album_item (id, album_id, kind, asset_id, sort_key) '
                "SELECT ?1, ?2, 'asset', ?3, ?4 WHERE NOT EXISTS (SELECT 1 "
                'FROM album_item WHERE album_id = ?2 AND asset_id = ?3 '
                'AND id <> ?1) '
                'ON CONFLICT (id) DO UPDATE SET sort_key = excluded.sort_key'
          : 'DELETE FROM album_item WHERE album_id = ?2 AND asset_id = ?3',
      [itemId(album, asset), album, asset, if (m.present) m.sortKey],
    );
    return;
  }
  if (mutation.hasVersion()) {
    final v = mutation.version;
    final parent = v.parentId.isEmpty ? null : _bytes(v.parentId);
    final label = v.label.isEmpty ? null : v.label;
    await db.customStatement(
      'INSERT INTO asset_version (id, asset_id, parent_id, kind, label, '
      "recipe, created_at) VALUES (?1, ?2, ?3, 'edit', ?4, ?5, ?6) "
      'ON CONFLICT (id) DO NOTHING',
      [
        _bytes(v.versionId),
        _bytes(v.assetId),
        parent,
        label,
        Uint8List.fromList(v.recipe),
        mutation.hlc.physicalMs.toInt(),
      ],
    );
    return;
  }
  final edit = mutation.edit;
  final (table, key) = (_replicaTable(db, edit.entity), _keys[edit.entity]);
  if (table == null || key == null) return;
  final id = _bytes(edit.id);
  final (sets, values) = (<String>[], <Object?>[]);
  for (final column in table.$columns) {
    final value = edit.fields[column.name];
    if (value == null) continue;
    final raw =
        column.name == 'trashed_at' && value.whichKind() != pb.Value_Kind.notSet
        ? mutation.hlc.physicalMs.toInt()
        : _raw(value);
    sets.add('${column.name} = ?');
    values.add(_converter(column, 0)([raw]));
  }
  if (sets.isEmpty) return;
  final name = table.actualTableName;
  // A row the replica lacks and can make of its key alone: the account's own
  // state of an asset.
  await db.customStatement('INSERT OR IGNORE INTO $name ($key) VALUES (?)', [
    id,
  ]);
  await db.customStatement(
    'UPDATE $name SET ${sets.join(', ')} WHERE $key = ?',
    [...values, id],
  );
}
