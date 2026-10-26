// The sync RPC's server stream (Connect, ADR-0091) through the one network stack.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart';
import 'package:photolib_api/testing.dart';
import 'package:test/test.dart';

import 'support/servers.dart';

void main() {
  late SyncServer photolibd;
  late Server server;
  setUp(() async {
    photolibd = await SyncServer.start();
    server = Server(NetworkConfig(endpoints: [photolibd.url]));
  });
  tearDown(() async {
    server.close();
    await photolibd.close();
  });

  Rows rows(String entity, List<String> ids) => Rows(
    entity: entity,
    columns: ['id'],
    rows: [
      for (final id in ids) Row(values: [Value(text: id)]),
    ],
  );

  SyncRequest request(Map<String, String> cursors) => SyncRequest(
    streams: [
      for (final MapEntry(:key, :value) in cursors.entries)
        StreamCursor(stream: key, cursor: utf8.encode(value)),
    ],
  );

  test('streams the batches of every stream named, each stream ending caught up', () async {
    photolibd.streams
      ..['tags'] = [
        [
          rows('tags', ['t1']),
        ],
        [
          rows('tags', ['t2', 't3']),
        ],
      ]
      ..['people'] = [];
    final batches = await server
        .sync(request({'tags': 'instance.0 1', 'people': ''}))
        .map((m) => SyncResponse.fromBuffer(m).batch)
        .toList();
    expect(photolibd.requests.single.streams.map((s) => s.stream), [
      'tags',
      'people',
    ]);
    expect(
      [
        for (final b in batches)
          '${b.stream} ${b.status.value} ${utf8.decode(b.cursor)} ${b.caughtUp} '
              '${[for (final r in b.changes)
                for (final row in r.rows) row.values.single.text]}',
      ],
      [
        'tags 1 instance.0 2 false [t2, t3]',
        'tags 1 instance.0 2 true []',
        'people 1 instance.0 0 true []',
      ],
    );
  });

  test('accepts gzip and reads the messages photolibd compresses', () async {
    final tags = [for (var i = 0; i < 200; i++) 'tag $i'];
    photolibd.streams['tags'] = [
      [rows('tags', tags)],
    ];
    final batches = await server
        .sync(request({'tags': ''}))
        .map((m) => SyncResponse.fromBuffer(m).batch)
        .toList();
    expect(photolibd.compressed, 1);
    expect([
      for (final row in batches.first.changes.single.rows)
        row.values.single.text,
    ], tags);
  });

  for (final (what, compressed) in [
    ('broken', [1, 2, 3]),
    ('a decompression bomb', gzip.encode(Uint8List(65 << 20))),
  ]) {
    test('a compressed message that is $what is Unreachable', () async {
      final proxy = await ProxiedServer.start(null);
      addTearDown(proxy.close);
      proxy.answer = gzipped(compressed);
      await expectLater(
        Server(NetworkConfig(endpoints: [proxy.url]))
            .sync(request({'tags': ''}))
            .toList(),
        throwsA(isA<Unreachable>()),
      );
    });
  }

  for (final compressed in [false, true]) {
    test('a message over 64 MiB is Unreachable, '
        '${compressed ? '' : 'un'}compressed', () async {
      final proxy = await ProxiedServer.start(null);
      addTearDown(proxy.close);
      // Stored gzip, which inflates to 64 MiB, the most allowed.
      final message = compressed
          ? GZipCodec(level: 0).encode(Uint8List(64 << 20))
          : Uint8List((64 << 20) + 1);
      proxy.answer = (response) => response
        ..headers.contentType = ContentType('application', 'connect+proto')
        ..headers.set('connect-content-encoding', 'gzip')
        ..add(envelope(compressed ? 1 : 0, message))
        ..add(envelope(2, utf8.encode('{}')));
      await expectLater(
        Server(NetworkConfig(endpoints: [proxy.url]))
            .sync(request({'tags': ''}))
            .toList(),
        throwsA(isA<Unreachable>()),
      );
    });
  }

  test("photolibd's error at the end of the stream is a ServerError with its reason", () async {
    photolibd.error = {
      'code': 'unauthenticated',
      'details': [
        {
          'type': 'photolib.api.v1.ErrorDetail',
          'value': base64Encode(
            ErrorDetail(code: 'auth.session_revoked').writeToBuffer(),
          ),
        },
      ],
    };
    await expectLater(
      server.sync(request({'tags': ''})).toList(),
      throwsA(
        isA<ServerError>()
            .having((e) => e.logsOut, 'logsOut', isTrue)
            .having((e) => e.detail?.code, 'reason', 'auth.session_revoked'),
      ),
    );
  });

  test('a stream that ends before photolibd ends it is Unreachable, after the batches that arrived', () async {
    photolibd
      ..streams['tags'] = [
        [
          rows('tags', ['t1']),
        ],
        [
          rows('tags', ['t2']),
        ],
      ]
      ..dropAfter = 1;
    final seen = <String>[];
    await expectLater(
      server
          .sync(request({'tags': ''}))
          .map(
            (m) =>
                seen.add(utf8.decode(SyncResponse.fromBuffer(m).batch.cursor)),
          )
          .drain<void>(),
      throwsA(isA<Unreachable>()),
    );
    expect(seen, ['instance.0 1']);
  });

  test('an answer that is not a Connect stream is Unreachable', () async {
    server = Server(
      NetworkConfig(endpoints: [photolibd.url.resolve('elsewhere/')]),
    );
    await expectLater(
      server.sync(request({'tags': ''})).toList(),
      throwsA(isA<Unreachable>()),
    );
  });

  test('hints name the streams that may have advanced: first those the '
      'account may read, then those a change advanced, until photolibd '
      'stops', () async {
    photolibd.streams
      ..['tags'] = []
      ..['assets/1'] = [];
    final hints = StreamIterator(server.hints(['tags', 'assets/1', 'people']));
    expect(await hints.moveNext(), isTrue);
    expect(hints.current, ['tags', 'assets/1']);
    expect(photolibd.follows, [
      ['tags', 'assets/1', 'people'],
    ]);
    await photolibd.hint(['assets/1']);
    expect(await hints.moveNext(), isTrue);
    expect(hints.current, ['assets/1']);
    await photolibd.endHints();
    expect(await hints.moveNext(), isFalse);
  });

  test('hints open, with the session, only on an endpoint that answers as '
      'the instance', () async {
    final other = await SyncServer.start();
    addTearDown(other.close);
    other
      ..epoch = 'other.0'
      ..streams['tags'] = [];
    photolibd.streams['tags'] = [];
    final config = NetworkConfig(
      endpoints: [other.url, photolibd.url],
      session: 'token',
    );
    final hints = Server(config, instance: 'instance').hints(['tags']);
    expect(await hints.first, ['tags']);
    expect(other.follows, isEmpty);
    expect(photolibd.follows, [
      ['tags'],
    ]);
  });

  test('a server without hints is not asked for them', () async {
    photolibd.capabilities.remove('sync.hints.v1');
    await expectLater(server.hints(['tags']).first, throwsUnsupportedError);
    expect(photolibd.follows, isEmpty);
  });

  test('cancelling hints between events closes the channel at once', () async {
    photolibd.streams['tags'] = [];
    final first = Completer<void>();
    final hints = server.hints(['tags']).listen((_) => first.complete());
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await hints.cancel().timeout(const Duration(seconds: 1));
  });

  test('hints read every form of event the format allows', () async {
    final proxy = await ProxiedServer.start(null);
    addTearDown(proxy.close);
    proxy.answers['/events'] = (response) => response
      ..headers.contentType = ContentType('text', 'event-stream')
      ..write(': keep-alive\r\n\r\ndata:tags\r\ndata: people\r\n\r\n')
      ..write('event: other\nid: 7\nretry: 10\ndata\n\ndata: albums\n\n');
    final hints = Server(NetworkConfig(endpoints: [proxy.url])).hints([]);
    expect(await hints.toList(), [
      ['tags', 'people'],
      <String>[],
      ['albums'],
    ]);
  });

  for (final (what, answer, error) in [
    (
      'a revoked session',
      connectError(401, 'unauthenticated', reason: 'r'),
      isA<ServerError>().having((e) => e.logsOut, 'logsOut', isTrue),
    ),
    ("a proxy's page", page(502), isA<Unreachable>()),
    (
      'an event over 1 MiB',
      (HttpResponse response) => response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..write('data: ${'x' * (1 << 20)}'),
      isA<Unreachable>(),
    ),
  ]) {
    test('hints refused by $what fail with the error it is', () async {
      final proxy = await ProxiedServer.start(null);
      addTearDown(proxy.close);
      proxy.answers['/events'] = answer;
      final hints = Server(NetworkConfig(endpoints: [proxy.url])).hints([]);
      await expectLater(hints.toList(), throwsA(error));
    });
  }
}
