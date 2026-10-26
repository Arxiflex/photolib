@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/offline/video_proxy.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../../support/fake_server.dart';

Uint8List _id(int kind, int n) => Uint8List(16)
  ..[0] = kind
  ..[15] = n;

String _hex(List<int> b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

String _uuid(Uint8List id) {
  final h = _hex(id);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

void main() {
  late Directory dir;
  late Vault vault;
  late Replica db;
  late OfflineStore store;
  late OfflineMedia media;
  final video = Uint8List.fromList([for (var i = 0; i < 5000; i++) i % 251]);
  final hash = Uint8List(32)..[0] = 7;

  // flutter_test answers every HTTP request with 400 unless told not to.
  setUpAll(() => HttpOverrides.global = null);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-proxy-');
    (vault, _) = await scratchVault('${dir.path}/store', Kernel().keyring);
    db = Replica(NativeDatabase.memory());
    store = await OfflineStore.open(
      vault,
      storeFiles(vault.location),
      budget: 1 << 20,
      chunkSize: 1024,
    );
    media = OfflineMedia(db, store);
    await db
        .into(db.library)
        .insert(
          LibraryCompanion.insert(
            id: _id(1, 1),
            ownerId: _id(2, 1),
            kind: 'managed',
            privacy: 'standard',
            access: 'rw',
            state: 'online',
          ),
        );
    await db
        .into(db.asset)
        .insert(
          AssetCompanion.insert(
            id: _id(3, 1),
            libraryId: _id(1, 1),
            ownerId: _id(2, 1),
            originalFilename: 'v.mp4',
            source: 'upload',
            mediaKind: 'video',
            createdAt: 1,
          ),
        );
    await db
        .into(db.assetFile)
        .insert(
          AssetFileCompanion.insert(
            id: _id(4, 1),
            assetId: _id(3, 1),
            role: 'r1',
            mime: 'video/mp4',
            size: video.length,
            contentHash: Value(hash),
            state: 'present',
          ),
        );
  });
  tearDown(() async {
    await db.close();
    await vault.lock();
    await dir.delete(recursive: true);
  });

  Future<(int, Map<String, String>, List<int>)> get(
    Uri url, {
    String? range,
    String method = 'GET',
  }) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.openUrl(method, url);
      if (range != null) request.headers.set('range', range);
      final response = await request.close();
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      final headers = <String, String>{};
      response.headers.forEach((k, v) => headers[k] = v.join(','));
      return (response.statusCode, headers, body);
    } finally {
      client.close(force: true);
    }
  }

  final path = 'media/${_uuid(_id(3, 1))}/r1';

  test('a held video is served in ranges, whole or from a byte', () async {
    await store.putBytes(
      OfflineMedia.keyOf(_hex(_id(3, 1)), 'r1', _hex(hash)),
      video,
    );
    final proxy = await VideoProxy.start(media, null);
    addTearDown(proxy.close);
    final url = await proxy.url(path);
    expect(url.host, '127.0.0.1');

    final (status, headers, body) = await get(url);
    expect(status, 200);
    expect(body, video);
    expect(headers['accept-ranges'], 'bytes');
    expect(headers['content-type'], 'video/mp4');
    expect(headers['content-length'], '5000');

    final (s2, h2, b2) = await get(url, range: 'bytes=1000-2999');
    expect(s2, 206);
    expect(b2, video.sublist(1000, 3000));
    expect(h2['content-range'], 'bytes 1000-2999/5000');

    final (s3, h3, b3) = await get(url, range: 'bytes=4500-');
    expect(s3, 206);
    expect(b3, video.sublist(4500));
    expect(h3['content-range'], 'bytes 4500-4999/5000');

    final (s4, _, b4) = await get(url, range: 'bytes=-100');
    expect(s4, 206);
    expect(b4, video.sublist(4900));

    final (s5, h5, b5) = await get(url, range: 'bytes=9000-');
    expect(s5, 416);
    expect(h5['content-range'], 'bytes */5000');
    expect(b5, isEmpty);

    final (s6, h6, b6) = await get(url, method: 'HEAD');
    expect(s6, 200);
    expect(h6['content-length'], '5000');
    expect(b6, isEmpty);
  });

  test('only its own token and files get an answer', () async {
    await store.putBytes(
      OfflineMedia.keyOf(_hex(_id(3, 1)), 'r1', _hex(hash)),
      video,
    );
    final proxy = await VideoProxy.start(media, null);
    addTearDown(proxy.close);
    final url = await proxy.url(path);
    final wrong = url.replace(
      pathSegments: ['0' * 32, ...url.pathSegments.skip(1)],
    );
    expect((await get(wrong)).$1, 404);
    expect(
      (await get(await proxy.url('media/${_uuid(_id(3, 2))}/r1'))).$1,
      404,
    );
    expect((await get(url, method: 'POST')).$1, 405);
  });

  test(
    'a video this device does not hold comes from the server, by range',
    () async {
      final server = FakeServer();
      final asked = <String>[];
      final link = _Ranged(server, video, asked);
      final proxy = await VideoProxy.start(media, link);
      addTearDown(proxy.close);
      final (status, headers, body) = await get(
        await proxy.url(path),
        range: 'bytes=100-1099',
      );
      expect(status, 206);
      expect(body, video.sublist(100, 1100));
      expect(headers['content-range'], 'bytes 100-1099/5000');
      expect(asked, ['$path bytes=100-1099']);
    },
  );

  test('with no store and no server it answers 503', () async {
    final proxy = await VideoProxy.start(media, null);
    addTearDown(proxy.close);
    expect((await get(await proxy.url(path))).$1, 503);
  });

  test('closed, it refuses', () async {
    final proxy = await VideoProxy.start(media, null);
    final url = await proxy.url(path);
    await proxy.close();
    await expectLater(get(url), throwsA(isA<SocketException>()));
  });
}

/// A server that answers `Range` for one video.
class _Ranged extends FakeServer {
  new(this.server, this.video, this.asked);

  final FakeServer server;
  final Uint8List video;
  final List<String> asked;

  @override
  Future<Media> media(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    asked.add('$path ${headers['range']}');
    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(headers['range'] ?? '');
    final from = int.parse(m![1]!);
    final to = int.parse(m[2]!);
    return (
      status: 206,
      etag: null,
      bytes: Stream.value(video.sublist(from, to + 1)),
      length: to + 1 - from,
    );
  }
}
