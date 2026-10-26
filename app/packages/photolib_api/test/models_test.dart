// Models from the user's server (design 09 §12.2) and vectors handed off at
// upload (§3.2), as photolibd expects them on the wire.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_api/photolib_api.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer photolibd;
  final seen = <HttpRequest>[];
  late Server server;
  setUp(() async {
    seen.clear();
    photolibd = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        seen.add(request);
        final response = request.response;
        if (request.uri.path == '/models/m%401/a.onnx') {
          response
            ..statusCode = HttpStatus.partialContent
            ..write('ights');
        } else if (request.method == 'POST') {
          response
            ..statusCode = HttpStatus.created
            ..headers.set('location', '/upload/1');
        } else {
          response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
    server = Server(
      NetworkConfig(
        endpoints: [Uri.parse('http://127.0.0.1:${photolibd.port}/')],
        session: 'token',
      ),
    );
  });
  tearDown(() async {
    server.close();
    await photolibd.close(force: true);
  });

  test('a model file is asked for from an offset, as the signed-in user; '
      'one the server has not installed is null', () async {
    final response = (await server.modelFile('m@1', 'a.onnx', 2))!;
    expect(response.statusCode, HttpStatus.partialContent);
    expect(await response.stream.bytesToString(), 'ights');
    expect(seen.single.headers.value('range'), 'bytes=2-');
    expect(seen.single.headers.value('authorization'), 'Bearer token');

    expect(await server.modelFile('m@1', 'b.onnx', 0), isNull);
  });

  test("an upload hands off the device's vector as half floats", () async {
    await server.createUpload(
      'library-1',
      1,
      'af13',
      ml: (
        model: 'm@1',
        runtime: 'onnxruntime 1.31.0 CPU fp16',
        // As local_ml keeps it.
        vector: halfFloats(
          Float32List.fromList([1, -2, .5, 65504, .1, 1e-7, 1e6]),
        ),
      ),
    );
    final headers = seen.single.headers;
    expect(headers.value('photolib-ml-model'), 'm@1');
    expect(headers.value('photolib-ml-runtime'), 'onnxruntime 1.31.0 CPU fp16');
    // 0x3c00 0xc000 0x3800 0x7bff 0x2e66 0x0002 (subnormal) 0x7c00 (infinity)
    expect(headers.value('photolib-ml-vector'), 'ADwAwAA4/3tmLgIAAHw=');

    seen.clear();
    await server.createUpload('library-1', 1, 'af13');
    expect(seen.single.headers.value('photolib-ml-vector'), isNull);
  });
}
