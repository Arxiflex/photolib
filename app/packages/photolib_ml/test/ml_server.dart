// The VM side of web_test.dart: fetches the pinned onnxruntime-web and models with tools/ml/fetch.py, serves them from
// another origin, as a static host or the user's server would, and sends the browser their URLs and golden.json.
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

import 'spike.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final selection = Platform.environment['PHOTOLIB_ML_MODELS'];
  final models = [for (final c in selected(selection)) c.model];
  final fetch = await Process.run('python3', [
    '../../../tools/ml/fetch.py',
    'onnxruntime-web',
    ...models,
  ]);
  if (fetch.exitCode != 0) {
    throw StateError('tools/ml/fetch.py failed:\n${fetch.stderr}');
  }
  final files = <String, String>{
    for (final MapEntry(:key, :value)
        in (jsonDecode(fetch.stdout as String) as Map).entries)
      for (final path in value as List)
        key == 'onnxruntime-web'
                ? '/ort/${Uri.file(path as String).pathSegments.last}'
                : '/$key.onnx':
            path as String,
  };

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = files[request.uri.path];
    final response = request.response
      ..headers.set('Access-Control-Allow-Origin', '*');
    if (path == null) {
      response.statusCode = HttpStatus.notFound;
    } else {
      response.headers.contentType = path.endsWith('.wasm')
          ? ContentType('application', 'wasm')
          : path.endsWith('.mjs')
          ? ContentType('text', 'javascript', charset: 'utf-8')
          : ContentType.binary;
      await response.addStream(File(path).openRead());
    }
    await response.close();
  });
  final origin = 'http://${server.address.host}:${server.port}';
  channel.sink.add({
    'module': '$origin/ort/ort.webgpu.bundle.min.mjs',
    'models': {for (final model in models) model: '$origin/$model.onnx'},
    'selection': selection,
    'golden': File('test/golden.json').readAsStringSync(),
  });
}
