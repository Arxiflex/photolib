import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photolib/features/map/map_state.dart';

class _Server extends http.BaseClient {
  new(this.answer);

  final Future<http.StreamedResponse> Function() answer;
  final headers = <Map<String, String>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    headers.add(request.headers);
    return answer();
  }
}

void main() {
  test(
    'a tile that arrives in time is passed on, with the app named',
    () async {
      final server = _Server(
        () async => http.StreamedResponse(const Stream.empty(), 200),
      );
      final client = TileClient(server);
      final response = await client.send(
        http.Request('GET', Uri.parse('https://tile.example/1/0/0.png')),
      );
      expect(response.statusCode, 200);
      expect(server.headers.single['user-agent'], startsWith('Photolib'));
    },
  );

  test('a tile that never arrives is given up after 10 s', () {
    fakeAsync((async) {
      final client = TileClient(
        _Server(() => Completer<http.StreamedResponse>().future),
      );
      Object? failure;
      unawaited(
        client
            .send(
              http.Request('GET', Uri.parse('https://tile.example/1/0/0.png')),
            )
            .catchError((Object e) {
              failure = e;
              return http.StreamedResponse(const Stream.empty(), 500);
            }),
      );
      async.elapse(const Duration(seconds: 9));
      expect(failure, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(failure, isA<TimeoutException>());
    });
  });
}
