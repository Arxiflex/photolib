// The one network stack on the web: the browser's fetch against the stand-in
// for photolibd, in browsers (`MOZ_HEADLESS=1 dart test -p chrome -p firefox
// -c dart2js -c dart2wasm test/web_test.dart`, the `web` part of the gate).
// The browser owns TLS, so the private CA and mutual TLS are
// network_test.dart's.
@TestOn('browser')
library;

import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:test/test.dart';

void main() {
  strict();
  late void Function(String) send;
  late Stream<Object?> replies;
  late Server server;
  setUpAll(() async {
    final channel = spawnHybridUri('support/web_server.dart');
    send = channel.sink.add;
    replies = channel.stream.asBroadcastStream();
    final url = Uri.parse(await replies.first as String);
    server = Server(
      NetworkConfig(endpoints: [url], headers: {'cf-access-token': 'token'}),
    );
  });

  /// Makes the server give `answer` from now on, and returns the requests it
  /// has seen.
  Future<List<Object?>> answer(String answer) async {
    send(answer);
    return await replies.first as List<Object?>;
  }

  Future<void> upload() async {
    final path = await server.createUpload('library-1', 3, 'af13');
    await server.sendUpload(
      path,
      3,
      (offset) => Stream.value([1, 2, 3].sublist(offset)),
      backoff: Duration.zero,
    );
  }

  Future<GetServerInfoResponse> serverInfo() =>
      ServerInfoServiceApi(server.rpc)
          .getServerInfo(null, GetServerInfoRequest());

  test('API calls, media and uploads go through fetch, '
      'without the headers over plain HTTP', () async {
    await answer('photolibd');
    expect((await serverInfo()).epoch, 'instance-a');
    final video = await server.get(
      'media/1/original',
      headers: {'range': 'bytes=10-19'},
    );
    expect(await video.stream.toBytes(), [for (var i = 10; i < 20; i++) i]);
    await upload();
    expect(await answer('photolibd'), [
      'POST /photolib.api.v1.ServerInfoService/GetServerInfo null',
      'GET /media/1/original null',
      'POST /upload null',
      'HEAD /upload/1 null',
      'PATCH /upload/1 null',
    ]);
  });

  test('an upload resumes after the connection drops', () async {
    final before = (await answer('network loss')).length;
    await upload();
    final seen = (await answer('photolibd')).skip(before);
    expect(seen.take(3), [
      'POST /upload null',
      'HEAD /upload/1 null',
      'PATCH /upload/1 null',
    ]);
    // Browsers send the lost append again by themselves, and get a conflict.
    expect(
      seen.skip(3),
      containsAllInOrder(['HEAD /upload/1 null', 'PATCH /upload/1 null']),
    );
    expect(seen.last, 'PATCH /upload/1 null');
  });

  for (final failure in ['502 page', '502 page without cors', 'redirect']) {
    test("a reverse proxy's $failure does not log out", () async {
      await answer(failure);
      for (final call in [serverInfo, () => server.get('media/1/thumb_s')]) {
        await expectLater(call(), throwsA(isA<Unreachable>()));
      }
    });
  }

  test(
    'Sync reads a gzipped message; a broken one or a bomb is Unreachable',
    () async {
      Future<List<String>> sync() => server
          .sync(SyncRequest(streams: [StreamCursor(stream: 'tags')]))
          .map((m) => SyncResponse.fromBuffer(m).batch.stream)
          .toList();
      await answer('gzip');
      expect(await sync(), ['tags']);
      for (final failure in ['broken gzip', 'gzip bomb']) {
        await answer(failure);
        await expectLater(sync(), throwsA(isA<Unreachable>()));
      }
    },
  );

  test(
    'over plain HTTP the session goes to no address the browser does not '
    'show is local, nor to a name it resolves without saying to what',
    () async {
      for (final host in [
        '203.0.113.9',
        '[2001:db8::1]',
        'photos.example.org',
      ]) {
        final remote = Server(
          NetworkConfig(
            endpoints: [Uri.parse('http://$host/')],
            session: 'token-1',
          ),
        );
        await expectLater(remote.get('media/1'), throwsA(isA<HttpsRequired>()));
      }
    },
  );

  test('a revoked session logs out', () async {
    await answer('revoked');
    await expectLater(
      serverInfo(),
      throwsA(isA<ServerError>().having((e) => e.logsOut, 'logsOut', isTrue)),
    );
  });
}
