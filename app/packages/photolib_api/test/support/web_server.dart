// The VM side of web_test.dart: the stand-in for photolibd over plain HTTP with CORS, for a test page on another
// origin. The browser names the answer to give and gets back the requests seen so far.
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_api/sync.dart';
import 'package:stream_channel/stream_channel.dart';

import 'servers.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final server = await ProxiedServer.start(null)
    ..cors = true;
  channel.sink.add('${server.url}');
  await for (final answer in channel.stream) {
    if (answer == 'network loss') server.losses.add((at: 2, hangs: false));
    server
      ..cors = answer != '502 page without cors'
      ..answer = switch (answer) {
        'photolibd' || 'network loss' => null,
        '502 page' || '502 page without cors' => page(502),
        'redirect' => redirect(server.url.resolve('elsewhere')),
        'revoked' => connectError(
          401,
          'unauthenticated',
          reason: 'auth.session_revoked',
        ),
        'gzip' => gzipped(
          gzip.encode(
            SyncResponse(batch: SyncBatch(stream: 'tags')).writeToBuffer(),
          ),
        ),
        'broken gzip' => gzipped([1, 2, 3]),
        'gzip bomb' => gzipped(gzip.encode(Uint8List(65 << 20))),
        _ => throw ArgumentError.value(answer),
      };
    channel.sink.add([
      for (final r in server.seen)
        '${r.method} ${r.path} ${r.headers.value('cf-access-token')}',
    ]);
  }
}
