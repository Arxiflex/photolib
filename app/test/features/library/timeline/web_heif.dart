// ignore_for_file: unused-code, unused-files
// The VM side of web_test.dart's HEIC tests: builds the kernel's module (tools/kernel/wasm.sh), serves it with CORS as
// a static host would, and sends the browser its URL, the AVC twins of the HEIC corpus files (testdata/corpus/twins,
// tools/corpus/avc_twins.py) with the colours they must show, and a corpus HEIC whose HEVC no Linux Chrome decodes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final out = await Directory.systemTemp.createTemp('photolib-heif-wasm-');
  final build = await Process.run('bash', [
    '../tools/kernel/wasm.sh',
    out.path,
  ]);
  if (build.exitCode != 0) {
    throw StateError('tools/kernel/wasm.sh failed:\n${build.stderr}');
  }
  final modules = {
    for (final file in out.listSync().whereType<File>())
      '/${file.uri.pathSegments.last}': file.readAsBytesSync(),
  };
  await out.delete(recursive: true);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final body = modules[request.uri.path];
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = request.uri.path.endsWith('.wasm')
          ? ContentType('application', 'wasm')
          : ContentType('text', 'javascript', charset: 'utf-8');
      request.response.add(body);
    }
    unawaited(request.response.close());
  });

  final twins = Directory('../testdata/corpus/twins/heif-avc');
  final listing = jsonDecode(
    File('${twins.path}/twins.json').readAsStringSync(),
  );
  channel.sink.add({
    'module':
        'http://${server.address.host}:${server.port}/photolib_kernel_wasm.js',
    'twins': listing,
    'files': {
      for (final name in (listing as Map<String, Object?>).keys)
        name: base64.encode(File('${twins.path}/$name').readAsBytesSync()),
    },
    'hevc': base64.encode(
      File('../testdata/corpus/files/stills/grid.heic').readAsBytesSync(),
    ),
  });
}
