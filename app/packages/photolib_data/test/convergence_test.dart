// Two devices editing offline converge (ADR-0265): each edits its replica at
// random, then pushes and syncs at random moments through a stand-in photolibd
// that merges as photolibd does (per-field hybrid logical clocks, the latest
// add or removal of an album's asset), sometimes unreachable, sometimes losing
// its answer, refusing what a viewer may not change, until both replicas hold
// what the server holds.
@TestOn('vm')
library;

import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'support/sync_rows.dart';

const _start = 1767225600000;
const _album = 50;

/// Asset 4 is shared with the account to view only: its edits are refused for
/// good, but a favourite.
const _viewOnly = 4;

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

String _uuidOf(List<int> bytes) {
  final hex = _hex(bytes);
  return [
    for (final (from, to) in [(0, 8), (8, 12), (12, 16), (16, 20), (20, 32)])
      hex.substring(from, to),
  ].join('-');
}

/// A stand-in photolibd that merges mutations by photolibd's rules and sends
/// what they changed down its streams.
class _Merging {
  _Merging(this.photolibd) {
    photolibd
      ..capabilities.add('sync.mutations.v1')
      ..onPush = _push
      ..streams.addAll({
        for (final s in ['account', 'tags', 'people', 'faces/${uuid(1)}'])
          s: <Object>[],
        'libraries': [
          [
            rows('libraries', [library(1)]),
          ],
        ],
        'assets/${uuid(1)}': [
          [
            rows('assets', [for (var n = 1; n <= 4; n++) asset(n)]),
          ],
        ],
        'albums': [
          [
            rows('albums', [
              {'id': uuid(_album), 'owner_id': uuid(100), 'title': 'Trip'},
            ]),
          ],
        ],
      });
    for (final (n, key) in [(1, 'V'), (2, 'k')]) {
      _apply(
        pb.Mutation(
          hlc: pb.Hlc(physicalMs: Int64(_start - 1000), deviceId: uuid(9)),
          member: pb.MemberEdit(
            setId: uuid(_album),
            elementId: uuid(n),
            present: true,
            sortKey: key,
          ),
        ),
      );
    }
    _send(_values.keys.toSet());
  }

  final SyncServer photolibd;

  /// Each row's values by `table/key`, and each value's clock by
  /// `table/key/field`.
  final _values = <String, Map<String, Object?>>{};
  final _clocks = <String, String>{};
  final _processed = <String, String?>{};

  /// Whether the next answer is lost, once the mutations are applied.
  bool loseAnswer = false;

  static String _at(pb.Hlc h) =>
      '${h.physicalMs.toString().padLeft(13, '0')}-'
      '${h.counter.toString().padLeft(10, '0')}-${h.deviceId}';

  /// Sets [field] of [row] unless a later edit holds it; returns whether it
  /// did.
  bool _take(String row, String field, String at, Object? value) {
    final held = _clocks['$row/$field'];
    if (held != null && held.compareTo(at) > 0) return false;
    _clocks['$row/$field'] = at;
    (_values[row] ??= {})[field] = value;
    return true;
  }

  pb.PushMutationsResponse _push(pb.PushMutationsRequest request) {
    final touched = {for (final m in request.mutations) _row(m)};
    final before = {
      for (final row in touched) row: {...?_values[row]},
    };
    final results = [
      for (final m in request.mutations)
        pb.MutationResult(
          mutationId: m.mutationId,
          rejected: switch (_processed.containsKey(m.mutationId)
              ? _processed[m.mutationId]
              : _processed[m.mutationId] = _apply(m)) {
            null => null,
            final code => ErrorDetail(code: code),
          },
        ),
    ];
    // Only what changed goes down the streams, as photolibd's change capture
    // sends it.
    _send({
      for (final row in touched)
        if ('${before[row]}' != '${_values[row] ?? {}}') row,
    });
    if (loseAnswer) {
      loseAnswer = false;
      return pb.PushMutationsResponse();
    }
    return pb.PushMutationsResponse(
      results: results,
      rows: _send(touched, stream: false),
      clock: pb.Hlc(physicalMs: Int64(_start)),
    );
  }

  String _row(pb.Mutation m) {
    if (!m.hasMember()) return '${m.edit.entity}/${m.edit.id}';
    final item = itemId(_bytes(m.member.setId), _bytes(m.member.elementId));
    return 'album_items/${_uuidOf(item)}';
  }

  /// Applies [m]; returns why it is refused, if it is.
  String? _apply(pb.Mutation m) {
    final at = _at(m.hlc);
    final row = _row(m);
    if (m.hasMember()) {
      final item = m.member;
      if (_take(row, 'present', at, item.present) && item.present) {
        _take(row, 'sort_key', at, item.sortKey);
      }
      _values[row]!
        ..['album_id'] = item.setId
        ..['asset_id'] = item.elementId;
      return null;
    }
    final edit = m.edit;
    if (edit.entity == 'album_items' && !_values.containsKey(row)) {
      return 'mutation.not_found';
    }
    if (edit.entity == 'assets' && edit.id == uuid(_viewOnly)) {
      return 'mutation.forbidden';
    }
    for (final MapEntry(:key, :value) in edit.fields.entries) {
      _take(row, key, at, switch (value.whichKind()) {
        pb.Value_Kind.text => value.text,
        pb.Value_Kind.integer when key == 'trashed_at' =>
          m.hlc.physicalMs.toInt(),
        pb.Value_Kind.integer => value.integer.toInt(),
        pb.Value_Kind.boolean => value.boolean,
        _ => null,
      });
    }
    return null;
  }

  /// The rows [touched] as the server holds them, appended to the streams
  /// that carry them unless not to [stream].
  List<pb.Rows> _send(Set<String> touched, {bool stream = true}) {
    final changed = <pb.Rows>[];
    for (final key in touched) {
      final [table, id] = key.split('/');
      final values = _values[key] ?? {};
      final (name, row) = switch (table) {
        'assets' => (
          'assets/${uuid(1)}',
          rows('assets', [
            {...asset(int.parse(id.substring(24), radix: 16)), ...values},
          ]),
        ),
        'asset_user_state' => (
          'account',
          rows('asset_user_state', [
            {'user_id': uuid(100), 'asset_id': id, ...values},
          ]),
        ),
        _ when values['present'] == true => (
          'albums',
          rows('album_items', [
            {
              'id': id,
              'album_id': values['album_id'],
              'kind': 'asset',
              'asset_id': values['asset_id'],
              'sort_key': values['sort_key'],
            },
          ]),
        ),
        _ => (
          'albums',
          rows('album_items', [
            {'id': id},
          ], deleted: true),
        ),
      };
      changed.add(row);
      if (stream) {
        photolibd.streams[name] = [
          ...?photolibd.streams[name],
          [row],
        ];
      }
    }
    return changed;
  }

  /// What the server holds, as [_state] reads a replica.
  List<String> get state {
    String value(String row, String field, Object? zero) =>
        '${_values[row]?[field] ?? zero}';
    return [
      for (var n = 1; n <= 4; n++)
        [
          'asset $n',
          value('assets/${uuid(n)}', 'title', null),
          value('assets/${uuid(n)}', 'rating', 0),
          value('assets/${uuid(n)}', 'trashed_at', null),
        ].join(' '),
      for (var n = 1; n <= 4; n++)
        if (_values['asset_user_state/${uuid(n)}']?['favorite'] == true)
          'favourite $n',
      ...[
        for (final MapEntry(:key, :value) in _values.entries)
          if (key.startsWith('album_items/') && value['present'] == true)
            [
              'item',
              key.substring(12).replaceAll('-', ''),
              '${value['asset_id']}'.substring(24),
              value['sort_key'],
            ].join(' '),
      ]..sort(),
    ];
  }
}

Uint8List _bytes(String uuid) => Uint8List.fromList([
  for (var i = 0; i < 32; i += 2)
    int.parse(uuid.replaceAll('-', '').substring(i, i + 2), radix: 16),
]);

/// What [db] holds, as [_Merging.state] reads the server.
Future<List<String>> _state(Replica db) async => [
  for (final a in await (db.select(
    db.asset,
  )..orderBy([(a) => OrderingTerm(expression: a.id)])).get())
    [
      'asset ${int.parse(_hex(a.id).substring(20), radix: 16)}',
      a.title,
      a.rating,
      a.trashedAt,
    ].join(' '),
  for (final s in await (db.select(
    db.assetUserState,
  )..orderBy([(s) => OrderingTerm(expression: s.assetId)])).get())
    if (s.favorite == 1)
      'favourite ${int.parse(_hex(s.assetId).substring(20), radix: 16)}',
  ...[
    for (final i in await db.select(db.albumItem).get())
      [
        'item',
        _hex(i.id),
        _hex(i.assetId ?? []).substring(20),
        i.sortKey,
      ].join(' '),
  ]..sort(),
];

/// One device: its replica, its wall clock, which runs [skew] ms off the
/// server's, and its edits.
class _Device {
  _Device(this.skew) : db = Replica(NativeDatabase.memory()) {
    mutations = Mutations(db, now: now);
  }

  final int skew;
  final Replica db;
  late final Mutations mutations;
  int elapsed = 0;

  int now() => _start + skew + elapsed;

  Future<void> sync(Server server) => SyncEngine(db, server, now: now).run();

  /// One edit of its user's, at random, of what its replica shows.
  Future<void> edit(Random random) async {
    final asset = bytes(random.nextInt(4) + 1);
    final items = [
      for (final i
          in await (db.select(db.albumItem)..orderBy([
                (i) => OrderingTerm(expression: i.sortKey),
                (i) => OrderingTerm(expression: i.id),
              ]))
              .get())
        i.id,
    ];
    switch (random.nextInt(7)) {
      case 0:
        await mutations.edit('assets', asset, {
          'title': [null, 'x', 'y'][random.nextInt(3)],
        });
      case 1:
        await mutations.edit('assets', asset, {
          'rating': random.nextInt(7) - 1,
        });
      case 2:
        await mutations.edit('assets', asset, {
          'trashed_at': random.nextBool() ? 0 : null,
        });
      case 3:
        await mutations.edit('asset_user_state', asset, {
          'favorite': random.nextBool(),
        });
      case 4:
        await mutations.addToAlbum(bytes(_album), asset);
      case 5:
        await mutations.removeFromAlbum(bytes(_album), asset);
      case _ when items.isNotEmpty:
        final at = random.nextInt(items.length + 1);
        await mutations.moveInAlbum(
          items[random.nextInt(items.length)],
          after: at == 0 ? null : items[at - 1],
          before: at == items.length ? null : items[at],
        );
    }
  }
}

void main() {
  for (var seed = 0; seed < 25; seed++) {
    test('two devices editing offline converge (seed $seed)', () async {
      final random = Random(seed);
      final photolibd = await SyncServer.start();
      final server = _Merging(photolibd);
      final api = Server(NetworkConfig(endpoints: [photolibd.url]));
      final devices = [
        _Device(random.nextInt(20000) - 10000),
        _Device(random.nextInt(20000) - 10000),
      ];
      addTearDown(() async {
        for (final d in devices) {
          await d.db.close();
        }
        api.close();
        await photolibd.close();
      });
      for (final d in devices) {
        await d.sync(api);
      }

      for (var step = 0; step < 40; step++) {
        final device = devices[random.nextInt(2)]
          ..elapsed += random.nextInt(3000);
        if (random.nextInt(10) < 7) {
          await device.edit(random);
          continue;
        }
        server.loseAnswer = random.nextInt(6) == 0;
        if (random.nextInt(6) == 0) {
          photolibd.unavailable.add('PushMutations');
        }
        try {
          await device.sync(api);
        } on CallError {
          // Offline: the edits wait.
        }
        photolibd.unavailable.clear();
      }

      server.loseAnswer = false;
      for (var round = 0; round < 3; round++) {
        for (final d in devices) {
          d.elapsed += 3600000;
          await d.sync(api);
        }
      }
      for (final d in devices) {
        expect(await _state(d.db), server.state, reason: 'device ${d.skew}');
        expect(await d.db.pendingOutbox(1 << 62, 1).get(), isEmpty);
        expect({
          for (final r in await d.mutations.rejected().get())
            (r.entity, r.error),
        }, everyElement(('assets', 'mutation.forbidden')));
      }
    });
  }
}
