@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/sync_message.dart';
import 'package:test/test.dart';

import 'support/sync_rows.dart';

void main() {
  late SyncServer photolibd;
  late Server server;
  late Replica db;
  setUp(() async {
    photolibd = await SyncServer.start();
    photolibd.streams.addAll({
      for (final s in ['account', 'libraries', 'albums', 'tags', 'people'])
        s: [],
    });
    server = Server(NetworkConfig(endpoints: [photolibd.url]));
    db = Replica(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    server.close();
    await photolibd.close();
  });

  Future<void> sync() => SyncEngine(db, server).run();

  /// Batches the server's log of [stream] gains.
  void append(String stream, List<List<pb.Rows>> batches) =>
      photolibd.streams[stream] = [...?photolibd.streams[stream], ...batches];

  Future<Map<String, String>> cursors() async => {
    for (final c in await db.select(db.syncCursor).get())
      c.stream: '${utf8.decode(c.cursor)} ${c.epoch}',
  };

  Future<List<String>> assets() async => [
    for (final a in await (db.select(
      db.asset,
    )..orderBy([(a) => OrderingTerm(expression: a.id)])).get())
      '${a.originalFilename} ${a.title}',
  ];

  test(
    'a first sync applies every batch, opens the streams of each library it brings, from scratch, and keeps a cursor '
    'per stream',
    () async {
      photolibd.streams.addAll({
        'libraries': [
          [
            rows('libraries', [library(1)..remove('state')]),
          ],
        ],
        'assets/${uuid(1)}': [
          [
            rows('assets', [asset(1)..['fps'] = 29.97, asset(2)]),
            rows('asset_files', [file(1), file(2)]),
            rows('custom_fields', [
              {'id': uuid(7)},
            ]),
          ],
          [
            rows('assets', [
              asset(3)..addAll({'original_filename': null, 'media_kind': null}),
            ]),
          ],
        ],
        'faces/${uuid(1)}': [],
      });
      await sync();
      expect(
        [
          for (final r in photolibd.requests)
            [for (final s in r.streams) '${s.stream} ${utf8.decode(s.cursor)}'],
        ],
        [
          ['account ', 'libraries ', 'albums ', 'tags ', 'people '],
          ['assets/${uuid(1)} ', 'faces/${uuid(1)} '],
        ],
      );
      expect(await cursors(), {
        'account': 'instance.0 0 instance.0',
        'libraries': 'instance.0 1 instance.0',
        'albums': 'instance.0 0 instance.0',
        'tags': 'instance.0 0 instance.0',
        'people': 'instance.0 0 instance.0',
        'assets/${uuid(1)}': 'instance.0 2 instance.0',
        'faces/${uuid(1)}': 'instance.0 0 instance.0',
      });
      final a = await (db.select(
        db.asset,
      )..where((a) => a.id.equals(bytes(1)))).getSingle();
      expect(
        [
          a.libraryId,
          a.ownerId,
          a.contentHash,
          a.facets,
          a.takenLocal,
          a.takenUtc,
          a.tzAssumed,
          a.lat,
          a.width,
          a.fps,
          a.txid,
          a.thumbhash,
        ],
        [
          bytes(1),
          bytes(100),
          List.filled(32, 1),
          'live,raw',
          '2024-05-03T00:30:00',
          1714687200001,
          0,
          38.7,
          4000,
          29.97,
          9,
          List.filled(25, 3),
        ],
      );
      expect(await assets(), ['IMG_1.jpg null', 'IMG_2.jpg null', ' null']);
      expect(
        [for (final f in await db.otherFiles().get()) uuidOf(f.id)],
        [uuid(3)],
      );
      expect((await db.select(db.assetFile).get()).map((f) => f.assetId), [
        bytes(1),
        bytes(2),
      ]);
      final mine = await db.select(db.library).getSingle();
      expect([mine.isUploadTarget, mine.state], [1, '']);
    },
  );

  test('a server without the sync stream is not synced', () async {
    photolibd.capabilities.clear();
    await expectLater(sync(), throwsA(isA<UnsupportedError>()));
    expect(photolibd.requests, isEmpty);
  });

  group('after a first sync', () {
    final libraryStream = 'assets/${uuid(1)}';
    setUp(() async {
      photolibd.streams.addAll({
        'libraries': [
          [
            rows('libraries', [library(1)]),
          ],
        ],
        libraryStream: [
          [
            rows('assets', [asset(1), asset(2)]),
            rows('asset_files', [file(1), file(2)]),
          ],
        ],
        'faces/${uuid(1)}': [],
      });
      await sync();
      photolibd.requests.clear();
    });

    test(
      'a sync sends each cursor and applies only what changed since, deletions taking what hangs off them',
      () async {
        append(libraryStream, [
          [
            rows('assets', [asset(1, title: 'Lisbon')]),
          ],
          [
            rows('assets', [
              {'id': uuid(2)},
            ], deleted: true),
          ],
        ]);
        await sync();
        expect(
          [
            for (final s in photolibd.requests.single.streams)
              '${s.stream} ${utf8.decode(s.cursor)}',
          ],
          containsAll([
            'libraries instance.0 1',
            '$libraryStream instance.0 1',
          ]),
        );
        expect(await assets(), ['IMG_1.jpg Lisbon']);
        expect((await db.select(db.assetFile).get()).map((f) => f.assetId), [
          bytes(1),
        ]);
        expect((await cursors())[libraryStream], 'instance.0 3 instance.0');
      },
    );

    test(
      'a sync cut short keeps the batches it applied, each with its cursor, and the next resumes after them',
      () async {
        append(libraryStream, [
          [
            rows('assets', [asset(3)]),
          ],
          [
            rows('assets', [asset(4)]),
          ],
        ]);
        photolibd.dropAfter =
            6; // the five account streams, caught up, then the first new batch
        await expectLater(sync(), throwsA(isA<Unreachable>()));
        expect(await assets(), [
          'IMG_1.jpg null',
          'IMG_2.jpg null',
          'IMG_3.jpg null',
        ]);
        expect((await cursors())[libraryStream], 'instance.0 2 instance.0');
        photolibd.dropAfter = null;
        await sync();
        expect(await assets(), hasLength(4));
        expect((await cursors())[libraryStream], 'instance.0 3 instance.0');
      },
    );

    test(
      'a stream the server resets syncs again from scratch, without what the server no longer has',
      () async {
        photolibd
          ..reset.add(libraryStream)
          ..streams[libraryStream] = [
            [
              rows('assets', [asset(3)]),
            ],
          ];
        await sync();
        expect(await assets(), ['IMG_3.jpg null']);
        expect(await db.select(db.assetFile).get(), isEmpty);
        expect((await cursors())[libraryStream], 'instance.0 1 instance.0');
      },
    );

    test(
      'a stream the server refuses goes, with what it brought, and that sync asks for it no more',
      () async {
        append('tags', [
          [
            rows('tags', [
              {
                'id': uuid(8),
                'owner_id': uuid(100),
                'name': 'x',
                'path': 'x',
                'txid': 5,
              },
            ]),
          ],
        ]);
        await sync();
        expect(await db.select(db.tag).get(), hasLength(1));
        photolibd
          ..forbidden.add('tags')
          ..requests.clear();
        await sync();
        expect(await db.select(db.tag).get(), isEmpty);
        expect((await cursors()).keys, isNot(contains('tags')));
        expect(
          photolibd.requests
              .expand((r) => r.streams)
              .where((s) => s.stream == 'tags'),
          hasLength(1),
        );
      },
    );

    test(
      'a partner share that changes, as its window does, syncs its stream again from scratch',
      () async {
        final partner = 'partner/${uuid(200)}';
        append('libraries', [
          [
            rows('partner_shares', [partnerShare(null)]),
          ],
        ]);
        photolibd.streams[partner] = [
          [
            rows('assets', [
              asset(41, library: 3, owner: 200)..['taken_utc'] = 1500000000000,
              asset(42, library: 3, owner: 200),
            ]),
          ],
        ];
        await sync();
        expect(await assets(), [
          'IMG_1.jpg null',
          'IMG_2.jpg null',
          'IMG_41.jpg null',
          'IMG_42.jpg null',
        ]);
        append('libraries', [
          [
            rows('partner_shares', [partnerShare('2020-01-01')]),
          ],
        ]);
        photolibd.streams[partner] = [
          [
            rows('assets', [asset(42, library: 3, owner: 200)]),
          ],
        ];
        photolibd.requests.clear();
        await sync();
        expect(await assets(), [
          'IMG_1.jpg null',
          'IMG_2.jpg null',
          'IMG_42.jpg null',
        ]);
        expect(
          [
            for (final r in photolibd.requests)
              for (final s in r.streams)
                if (s.stream == partner) utf8.decode(s.cursor),
          ],
          ['instance.0 1', ''],
        );
      },
    );
  });

  group('what the account can no longer see goes', () {
    // Ann (100) owns library 1; Bob (200) shares his library 2 with her and his album 5, which shows asset 21 of his
    // library 3, that Ann is no member of, and asset 22 of library 2.
    final (mine, shared, album) = (
      'assets/${uuid(1)}',
      'assets/${uuid(2)}',
      'album_items/${uuid(5)}',
    );
    final member = {
      'library_id': uuid(2),
      'user_id': uuid(100),
      'role': 'viewer',
      'txid': 3,
    };
    final albumMember = {
      'album_id': uuid(5),
      'user_id': uuid(100),
      'role': 'viewer',
      'txid': 3,
    };

    /// Ann leaves library 2 or album 5: photolibd deletes her membership.
    void leave(String stream, String members, Map<String, Object?> key) =>
        append(stream, [
          [
            rows(members, [
              {...key, 'user_id': uuid(100)},
            ], deleted: true),
          ],
        ]);

    Map<String, Object?> item(int n, int asset) => {
      'id': uuid(n),
      'album_id': uuid(5),
      'kind': 'asset',
      'asset_id': uuid(asset),
      'sort_key': 'a$n',
      'txid': 4,
    };
    setUp(() async {
      photolibd.streams.addAll({
        'libraries': [
          [
            rows('libraries', [library(1), library(2, owner: 200)]),
            rows('library_members', [member]),
          ],
        ],
        'albums': [
          [
            rows('albums', [
              {
                'id': uuid(5),
                'owner_id': uuid(200),
                'title': 'Trip',
                'created_at': 1,
                'txid': 3,
              },
            ]),
            rows('album_members', [albumMember]),
          ],
        ],
        mine: [
          [
            rows('assets', [asset(11)]),
          ],
        ],
        shared: [
          [
            rows('assets', [
              asset(22, library: 2, owner: 200),
              asset(23, library: 2, owner: 200),
            ]),
            rows('asset_files', [file(22), file(23)]),
          ],
        ],
        album: [
          [
            rows('album_items', [item(31, 21), item(32, 22)]),
            rows('assets', [
              asset(21, library: 3, owner: 200),
              asset(22, library: 2, owner: 200),
            ]),
            rows('asset_files', [file(21)]),
          ],
        ],
        for (final l in [1, 2]) 'faces/${uuid(l)}': [],
      });
      await sync();
      expect(await assets(), [
        'IMG_11.jpg null',
        'IMG_21.jpg null',
        'IMG_22.jpg null',
        'IMG_23.jpg null',
      ]);
    });

    test(
      'a library Ann leaves, but for what an album still shows her',
      () async {
        leave('libraries', 'library_members', {'library_id': uuid(2)});
        await sync();
        expect(await assets(), [
          'IMG_11.jpg null',
          'IMG_21.jpg null',
          'IMG_22.jpg null',
        ]);
        expect((await db.select(db.assetFile).get()).map((f) => f.assetId), [
          bytes(22),
          bytes(21),
        ]);
        expect((await db.select(db.library).get()).map((l) => l.id), [
          bytes(1),
        ]);
        expect(
          (await cursors()).keys,
          isNot(anyOf(contains(shared), contains('faces/${uuid(2)}'))),
        );
      },
    );

    test('an album Ann leaves, its items, and what only it showed', () async {
      leave('albums', 'album_members', {'album_id': uuid(5)});
      await sync();
      expect(await assets(), [
        'IMG_11.jpg null',
        'IMG_22.jpg null',
        'IMG_23.jpg null',
      ]);
      expect(await db.select(db.album).get(), isEmpty);
      expect(await db.select(db.albumItem).get(), isEmpty);
      expect((await cursors()).keys, isNot(contains(album)));
    });

    test(
      "an undated asset goes with Ann's last way to it but Bob's share, which "
      'shows his dated assets and private libraries whole, as photolibd does',
      () async {
        Map<String, Object?> undated(int n, int library) =>
            asset(n, library: library, owner: 200)..['taken_utc'] = null;
        append('libraries', [
          [
            rows('partner_shares', [partnerShare('2020-01-01')]),
          ],
        ]);
        append(shared, [
          [
            rows('assets', [undated(24, 2)]),
          ],
        ]);
        append(album, [
          [
            rows('album_items', [item(33, 25)]),
            rows('assets', [undated(25, 3)]),
          ],
        ]);
        // Bob's library 4 is private.
        photolibd.streams['partner/${uuid(200)}'] = [
          [
            rows('assets', [
              asset(21, library: 3, owner: 200),
              for (final n in [22, 23]) asset(n, library: 2, owner: 200),
              undated(41, 4),
            ]),
          ],
        ];
        await sync();
        expect(await assets(), [
          for (final n in [11, 21, 22, 23, 24, 25, 41]) 'IMG_$n.jpg null',
        ]);
        leave('libraries', 'library_members', {'library_id': uuid(2)});
        leave('albums', 'album_members', {'album_id': uuid(5)});
        await sync();
        expect(await assets(), [
          for (final n in [11, 21, 22, 23, 41]) 'IMG_$n.jpg null',
        ]);
      },
    );

    test("Bob's asset in Carol's library goes with Ann's membership of it: his "
        'share shows his own libraries only, as photolibd does', () async {
      append('libraries', [
        [
          rows('libraries', [library(6, owner: 300)]),
          rows('library_members', [
            {...member, 'library_id': uuid(6)},
          ]),
          rows('partner_shares', [partnerShare('2020-01-01')]),
        ],
      ]);
      photolibd.streams.addAll({
        'assets/${uuid(6)}': [
          [
            rows('assets', [asset(61, library: 6, owner: 200)]),
          ],
        ],
        'faces/${uuid(6)}': [],
        'partner/${uuid(200)}': [
          [
            rows('assets', [
              for (final n in [22, 23]) asset(n, library: 2, owner: 200),
            ]),
          ],
        ],
      });
      await sync();
      expect(await assets(), contains('IMG_61.jpg null'));
      leave('libraries', 'library_members', {'library_id': uuid(6)});
      await sync();
      expect(await assets(), [
        for (final n in [11, 21, 22, 23]) 'IMG_$n.jpg null',
      ]);
    });

    test(
      'an item taken out of the album, and its asset if nothing else shows it',
      () async {
        append(album, [
          [
            rows('album_items', [
              {'id': uuid(31)},
              {'id': uuid(32)},
            ], deleted: true),
          ],
        ]);
        await sync();
        expect(await assets(), [
          'IMG_11.jpg null',
          'IMG_22.jpg null',
          'IMG_23.jpg null',
        ]);
      },
    );
  });

  group('a server restored from a backup, which changes its epoch', () {
    // Device items 1 to 4: 1 and 2 backed up, 3 linked to what the server held, 4 uploading; 5 backed up unhashed.
    const states = {
      1: 'backed_up',
      2: 'backed_up',
      3: 'linked',
      4: 'uploading',
      5: 'backed_up',
    };
    setUp(() async {
      await db.batch((b) {
        for (final MapEntry(key: n, value: state) in states.entries) {
          b
            ..insert(
              db.localAsset,
              LocalAssetCompanion.insert(
                id: bytes(n),
                source: 'mediastore',
                sourceId: '$n',
                size: n,
                mtime: n,
                contentHash: Value(n == 5 ? null : Uint8List.fromList([n])),
                assetId: Value(bytes(50 + n)),
              ),
            )
            ..insert(
              db.backupState,
              BackupStateCompanion.insert(
                localAssetId: bytes(n),
                state: state,
                updatedAt: 0,
              ),
            );
        }
        b.insert(
          db.outbox,
          OutboxCompanion.insert(
            mutationId: bytes(9),
            entity: 'asset',
            entityId: bytes(51),
            mutation: Uint8List(1),
            retryAt: const Value(1 << 50),
            createdAt: 0,
          ),
        );
      });
      photolibd.streams.addAll({
        'libraries': [
          [
            rows('libraries', [library(1)]),
          ],
        ],
        'assets/${uuid(1)}': [
          [
            rows('assets', [asset(51), asset(52)]),
          ],
        ],
        'faces/${uuid(1)}': [],
      });
      await sync();
      // The backup that the server is restored from lacks asset 52, which held item 2.
      photolibd
        ..epoch = 'instance.1'
        ..streams['assets/${uuid(1)}'] = [
          [
            rows('assets', [asset(51)]),
          ],
        ]
        ..hashes.addAll({'01': uuid(51), '03': uuid(53)});
    });

    Future<Map<int, String>> backups() async => {
      for (final row
          in await db
              .customSelect(
                'SELECT b.state, b.reason, l.asset_id, l.source_id FROM backup_state b '
                'JOIN local_asset l ON l.id = b.local_asset_id',
              )
              .get())
        int.parse(
          row.read<String>('source_id'),
        ): '${row.read<String>('state')} ${row.readNullable<String>('reason')} '
            '${row.readNullable<Uint8List>('asset_id')?.last}',
    };

    test(
      'syncs everything again, re-verifies every backed-up item with CheckHashes and uploads again what the server '
      'lost',
      () async {
        await sync();
        expect(await assets(), ['IMG_51.jpg null']);
        expect((await cursors()).values.map((c) => c.split(' ').last).toSet(), {
          'instance.1',
        });
        expect(await backups(), {
          1: 'backed_up null 51',
          2: 'selected server_restored null',
          3: 'linked null 53',
          4: 'uploading null 54',
          5: 'selected server_restored null',
        });
        expect((await db.select(db.outbox).getSingle()).retryAt, null);
      },
    );

    for (final (call, at) in [
      ('the first call, which resets every stream', 0),
      ('a later one, which only starts streams', 1),
    ]) {
      test(
        'a restore between GetServerInfo and $call is found in the same sync, '
        'and the next downloads nothing again',
        () async {
          append('libraries', [
            [
              rows('libraries', [library(2)]),
            ],
          ]);
          photolibd
            ..streams.addAll({'assets/${uuid(2)}': [], 'faces/${uuid(2)}': []})
            ..requests.clear()
            ..epoch = 'instance.0'
            ..onSync = () {
              if (photolibd.requests.length > at) {
                photolibd.epoch = 'instance.1';
              }
            };
          await sync();
          expect(await assets(), ['IMG_51.jpg null']);
          expect(
            (await cursors()).values.map((c) => c.split(' ').last).toSet(),
            {'instance.1'},
          );
          expect((await backups())[2], 'selected server_restored null');
          photolibd.requests.clear();
          await sync();
          expect([
            for (final r in photolibd.requests)
              for (final s in r.streams)
                if (s.cursor.isEmpty) s.stream,
          ], isEmpty);
        },
      );
    }

    test(
      'a restore during the last call a sync makes is found in that sync',
      () async {
        // Each library's stream brings the next library, so that streams
        // open until the sync stops at its tenth call.
        photolibd
          ..streams.addAll({
            for (var n = 2; n <= 11; n++) ...{
              'assets/${uuid(n)}': [
                [
                  rows('libraries', [library(n + 1)]),
                ],
              ],
              'faces/${uuid(n)}': [],
            },
          })
          ..requests.clear()
          ..epoch = 'instance.0'
          ..onSync = () {
            if (photolibd.requests.length == 10) {
              photolibd.epoch = 'instance.1';
            }
          };
        append('libraries', [
          [
            rows('libraries', [library(2)]),
          ],
        ]);
        await sync();
        expect(photolibd.requests, hasLength(10));
        expect(await cursors(), isEmpty);
        expect((await backups())[2], 'selected server_restored null');
      },
    );

    test(
      'a sync that stops before it re-verified, the next still does',
      () async {
        photolibd.unavailable.add('CheckHashes');
        await expectLater(sync(), throwsA(isA<CallError>()));
        photolibd.unavailable.clear();
        await sync();
        expect((await backups())[2], 'selected server_restored null');
      },
    );
  });

  test(
    'a broken batch is a FormatException, never another error or a hang',
    () {
      final valid = pb.SyncResponse(
        batch: pb.SyncBatch(
          stream: 'assets/${uuid(1)}',
          changes: [
            rows('assets', [asset(1), asset(2)]),
          ],
          cursor: [1],
        ),
      ).writeToBuffer();
      final random = Random(7);
      var broken = 0;
      for (var i = 0; i < 3000; i++) {
        final bytes = Uint8List.fromList(valid);
        final message = switch (i % 3) {
          0 => Uint8List.sublistView(bytes, 0, random.nextInt(bytes.length)),
          1 => bytes..[random.nextInt(bytes.length)] = random.nextInt(256),
          _ => Uint8List.fromList([
            for (var n = random.nextInt(64); n > 0; n--) random.nextInt(256),
          ]),
        };
        try {
          for (final rows in SyncMessage(message).changes) {
            for (var r = 0; r < rows.length; r++) {
              rows.values(r);
            }
          }
        } on FormatException {
          broken++;
        }
      }
      expect(broken, greaterThan(1000));
    },
  );
}
