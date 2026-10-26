// The VM side of web_vectors_test.dart: builds the kernel for the web with tools/kernel/wasm.sh, pins the browser to
// the fastest cores for the benchmark, serves the module from another origin, as a static host would, and sends the
// browser its URL and the vector files.
import 'dart:io';

import 'package:photolib_kernel/testing.dart';
import 'package:stream_channel/stream_channel.dart';

final root = Directory.current.uri.resolve('../../../');

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final out = await Directory.systemTemp.createTemp('photolib-kernel-wasm-');
  final build = await Process.run('bash', [
    root.resolve('tools/kernel/wasm.sh').toFilePath(),
    out.path,
  ]);
  if (build.exitCode != 0) {
    throw StateError('tools/kernel/wasm.sh failed:\n${build.stderr}');
  }
  print((build.stdout as String).trim());
  // The test runner, this process, started the browser.
  pinToFastestCores(pid);
  final files = {
    for (final file in out.listSync().whereType<File>())
      '/${file.uri.pathSegments.last}': file.readAsBytesSync(),
  };
  await out.delete(recursive: true);

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final path = request.uri.path;
    final body = files[path];
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = path.endsWith('.wasm')
          ? ContentType('application', 'wasm')
          : ContentType('text', 'javascript', charset: 'utf-8');
      request.response.add(body);
    }
    request.response.close();
  });

  final vectors = Directory.fromUri(
    root.resolve('kernel/testvectors/'),
  ).listSync().whereType<File>().where((file) => file.path.endsWith('.json'));
  channel.sink.add({
    'module':
        'http://${server.address.host}:${server.port}/photolib_kernel_wasm.js',
    'vectors': {
      for (final file in vectors)
        file.uri.pathSegments.last: file.readAsStringSync(),
    },
  });
}
