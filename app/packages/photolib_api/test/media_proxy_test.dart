// The loopback proxy's decrypting sessions (design 08 §6.3): a player reads plaintext byte ranges, the proxy fetches
// whole 1 MiB windows of the encrypted object and opens their chunks. The cipher here is a stand-in whose tag names
// the chunk's index and whether it is the last, so a run opened at the wrong place fails as it would in the kernel.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_api/media_proxy.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:test/test.dart';

const chunk = 1 << 16, window = 1 << 20;
final plaintext = Uint8List.fromList(
  List.generate(3 * window + 1000, (i) => i % 251),
);

Uint8List tag(int index, bool last) =>
    (ByteData(16)
          ..setUint64(0, index)
          ..setUint8(8, last ? 1 : 0))
        .buffer
        .asUint8List();

/// The header (content kind 1 at byte 5, chunk_log2 16 at byte 6) and the chunks, each followed by its tag.
final sealed = Uint8List.fromList([
  ...List.filled(5, 0x50),
  1,
  16,
  ...List.filled(81, 0),
  for (var i = 0; i * chunk < plaintext.length; i++) ...[
    ...plaintext.sublist(
      i * chunk,
      ((i + 1) * chunk).clamp(0, plaintext.length),
    ),
    ...tag(i, (i + 1) * chunk >= plaintext.length),
  ],
]);

Uint8List? open(Uint8List header, int first, Uint8List chunks, bool more) {
  final out = BytesBuilder();
  for (var at = 0, index = first; at < chunks.length; index++) {
    final end = (at + chunk + 16).clamp(0, chunks.length);
    final last = !more && end == chunks.length;
    final tag = ByteData.sublistView(chunks, end - 16, end);
    if (header.length != 88 ||
        end - at != chunk + 16 && !last ||
        tag.getUint64(0) != index ||
        tag.getUint8(8) != (last ? 1 : 0)) {
      return null;
    }
    out.add(chunks.sublist(at, end - 16));
    at = end;
  }
  return out.takeBytes();
}

void main() {
  late HttpServer origin;
  late List<String> ranges;
  late Uint8List served;
  late MediaProxy proxy;
  late Uri url;
  setUp(() async {
    ranges = [];
    served = sealed;
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) {
      final range = request.headers.value('range')!;
      ranges.add(range);
      final [from, end] = range.substring(6).split('-').map(int.parse).toList();
      final to = end.clamp(0, served.length - 1);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('content-range', 'bytes $from-$to/${served.length}')
        ..add(served.sublist(from, to + 1))
        ..close();
    });
    final server = Server(
      NetworkConfig(endpoints: [Uri.parse('http://127.0.0.1:${origin.port}/')]),
    );
    proxy = await MediaProxy.start(server);
    url = proxy.decrypted('media/1/stream', 'video/mp4', open);
    addTearDown(() async {
      await proxy.close();
      server.close();
      await origin.close(force: true);
    });
  });

  Future<HttpClientResponse> send(
    Uri target, {
    String method = 'GET',
    String? range,
    String? host,
  }) async {
    final player = HttpClient();
    addTearDown(player.close);
    final request = await player.openUrl(method, target);
    if (range != null) request.headers.set('range', range);
    if (host != null) request.headers.host = host;
    return request.close();
  }

  Future<(HttpClientResponse, List<int>)> play(String range) async {
    final response = await send(url, range: range);
    return (response, await response.expand((bytes) => bytes).toList());
  }

  test('a player reads a closed range whole, an open one to its window\'s end', () async {
    final size = plaintext.length;
    for (final (range, from, to) in [
      ('bytes=0-', 0, window),
      ('bytes=5-9', 5, 10),
      ('bytes=${window - 3}-${window + 3}', window - 3, window + 4),
      ('bytes=${window - 3}-', window - 3, window),
      ('bytes=7-${3 * window}', 7, 3 * window + 1),
      ('bytes=${size - 10}-${size + 99}', size - 10, size),
    ]) {
      final (response, body) = await play(range);
      expect(response.statusCode, HttpStatus.partialContent, reason: range);
      expect(
        response.headers.value('content-range'),
        'bytes $from-${to - 1}/$size',
      );
      expect(response.headers.contentType?.mimeType, 'video/mp4');
      expect(body, plaintext.sublist(from, to), reason: range);
    }
    // The server sees the header once, then only whole windows: never where a range starts or ends.
    String w(int i) =>
        'bytes=${88 + 16 * i * (chunk + 16)}-${i == 3 ? sealed.length - 1 : 88 + 16 * (i + 1) * (chunk + 16) - 1}';
    expect(ranges, [
      'bytes=0-87',
      w(0),
      w(0),
      ...[w(0), w(1)],
      w(0),
      ...[w(0), w(1), w(2), w(3)],
      w(3),
    ]);
  });

  test('a range past the end is not satisfiable', () async {
    final (response, _) = await play('bytes=${plaintext.length}-');
    expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    expect(
      response.headers.value('content-range'),
      'bytes */${plaintext.length}',
    );
  });

  test(
    'a later chunk that fails to open ends the response before it',
    () async {
      served = Uint8List.fromList(sealed)
        ..[88 + 32 * (chunk + 16) + chunk] ^= 1;
      final response = await send(
        url,
        range: 'bytes=0-${plaintext.length - 1}',
      );
      expect(response.statusCode, HttpStatus.partialContent);
      final body = <int>[];
      await expectLater(
        response.listen(body.addAll).asFuture<void>(),
        throwsA(isA<HttpException>()),
      );
      expect(body.length, lessThanOrEqualTo(2 * window));
      expect(body, plaintext.sublist(0, body.length));
    },
  );

  test(
    'a first chunk that fails to open, or no envelope, is a bad gateway',
    () async {
      for (final bad in [
        Uint8List.fromList(sealed)..[88 + chunk] ^= 1,
        Uint8List.fromList(sealed)..[6] = 99,
        Uint8List.fromList(sealed)..[6] = 15,
        Uint8List(40),
      ]) {
        served = bad;
        // A session reads the header once: a new one for each object.
        url = proxy.decrypted('media/1/stream', 'video/mp4', open);
        final (response, body) = await play('bytes=0-');
        expect(response.statusCode, HttpStatus.badGateway);
        expect(body, isEmpty);
      }
    },
  );

  test('a request naming another host is refused (DNS rebinding)', () async {
    for (final target in [url, proxy.url('media/1/original')]) {
      final response = await send(target, host: 'rebound.example');
      expect(response.statusCode, HttpStatus.forbidden, reason: '$target');
      await response.drain<void>();
    }
    expect(ranges, isEmpty);
  });

  test('only GET reads a session', () async {
    final response = await send(url, method: 'POST');
    expect(response.statusCode, HttpStatus.methodNotAllowed);
    await response.drain<void>();
  });
}
