// Model files on the device (design 09 §12.2): downloaded once, resumed after
// a cut, kept only when their SHA-256 is the registry's.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/src/models.dart';
import 'package:test/test.dart';

const _weights = 'the weights of a model';
final _sha = '${sha256.convert(utf8.encode(_weights))}';

/// A mirror that honours ranges, but cuts the first [cut] answers after
/// [after] bytes; [ranges] are the ranges asked for.
class _Mirror {
  _Mirror(this._socket) {
    _socket.listen((client) async {
      final head = await utf8.decoder
          .bind(client)
          .firstWhere((s) => s.contains('\r\n\r\n'));
      paths.add(head.split(' ')[1]);
      final range = RegExp(
        r'range: bytes=(\d+)-',
        caseSensitive: false,
      ).firstMatch(head);
      ranges.add(range?.group(1));
      final from = honoursRange ? int.parse(range?.group(1) ?? '0') : 0;
      final body = utf8.encode(content.substring(from));
      client.write(
        'HTTP/1.1 ${missing
            ? 404
            : from > 0
            ? 206
            : 200} X\r\n'
        'content-length: ${missing ? 0 : body.length}\r\n'
        'connection: close\r\n\r\n',
      );
      if (!missing) client.add(cut-- > 0 ? body.sublist(0, after) : body);
      await client.flush();
      await client.close();
    });
  }

  static Future<_Mirror> start() async =>
      _Mirror(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _socket;
  final ranges = <String?>[];
  final paths = <String>[];
  String content = _weights;
  int cut = 0;
  int after = 4;
  bool honoursRange = true;
  bool missing = false;

  Uri get url => Uri.parse('http://127.0.0.1:${_socket.port}/m.onnx');

  Future<void> close() => _socket.close();
}

void main() {
  late Directory dir;
  late _Mirror mirror;
  late String path;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('models-');
    path = '${dir.path}/m@1/m.onnx';
    mirror = await _Mirror.start();
  });
  tearDown(() async {
    await mirror.close();
    await dir.delete(recursive: true);
  });

  Future<void> install([List<ModelSource>? sources]) => installModel(
    path,
    size: _weights.length,
    sha256: _sha,
    sources: sources ?? [mirrorModel(mirror.url)],
  );

  test('a download cut short resumes from what it kept; the file is kept '
      'once its SHA-256 matches, and not fetched again', () async {
    mirror.cut = 1;
    await expectLater(install(), throwsA(anything));
    expect(File('$path.part').readAsStringSync(), 'the ');
    expect(File(path).existsSync(), isFalse);

    final heard = <int>[];
    await installModel(
      path,
      size: _weights.length,
      sha256: _sha,
      sources: [mirrorModel(mirror.url)],
      progress: heard.add,
    );
    expect(mirror.ranges, ['0', '4']);
    expect(File(path).readAsStringSync(), _weights);
    expect(File('$path.part').existsSync(), isFalse);
    expect(heard.last, _weights.length);

    await install();
    expect(mirror.ranges, hasLength(2));
  });

  test('a file that differs from its pin is deleted, never kept', () async {
    mirror.content = 'the weights of a modem';
    await expectLater(
      install(),
      throwsA(predicate((e) => '$e'.contains('expected $_sha'))),
    );
    expect(File(path).existsSync(), isFalse);
    expect(File('$path.part').existsSync(), isFalse);
  });

  test('a source without the file passes to the next; one that sends the '
      'whole file again starts over', () async {
    final other = await _Mirror.start();
    addTearDown(other.close);
    mirror.missing = true;
    other
      ..honoursRange = false
      ..cut = 1;
    final sources = [mirrorModel(mirror.url), mirrorModel(other.url)];
    await expectLater(install(sources), throwsA(anything));
    expect(File('$path.part').readAsStringSync(), 'the ');

    await install(sources);
    expect(other.ranges, ['0', '4']);
    expect(File(path).readAsStringSync(), _weights);
  });

  test("from the user's server, resumed as from a mirror", () async {
    final server = Server(NetworkConfig(endpoints: [mirror.url.resolve('/')]));
    addTearDown(server.close);
    mirror.cut = 1;
    final sources = [serverModel(server, 'm@1', 'm.onnx')];
    await expectLater(install(sources), throwsA(anything));
    await install(sources);
    expect(mirror.paths, ['/models/m%401/m.onnx', '/models/m%401/m.onnx']);
    expect(mirror.ranges, ['0', '4']);
    expect(File(path).readAsStringSync(), _weights);

    mirror.missing = true;
    await File(path).delete();
    await expectLater(install(sources), throwsA(isA<ModelMissing>()));
  });
}
