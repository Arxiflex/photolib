import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// One address of a server: photolibd's GetServerInfo and media, after
/// [delay]; while [down], connections drop, as when the phone left its network.
class Address {
  new _(this._http, this.delay);
  final HttpServer _http;
  final Duration delay;
  bool down = false;
  final served = <String>[];

  static Future<Address> start(Duration delay) async {
    final address = Address._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      delay,
    );
    address._http.listen((request) async {
      if (address.down) {
        final socket = await request.response.detachSocket();
        return socket.destroy();
      }
      await Future<void>.delayed(delay);
      final response = request.response;
      if (request.uri.path.endsWith('GetServerInfo')) {
        response.headers.contentType = ContentType('application', 'proto');
        response.add(
          GetServerInfoResponse(epoch: 'instance-a.0').writeToBuffer(),
        );
      } else {
        address.served.add(request.uri.path);
        response.add([1, 2, 3]);
      }
      await response.close();
    });
    return address;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${_http.port}/');

  Future<void> close() => _http.close(force: true);
}

// MOB-16: the app switches between a server's LAN and WAN addresses as the
// device's network changes, within 2 s, without waiting for a call to fail.
void main() {
  // flutter_test answers every HTTP request 400 unless told not to.
  setUp(() => HttpOverrides.global = null);

  test('a network change picks the address again at once', () async {
    final (lan, wan) = (
      await Address.start(Duration.zero),
      await Address.start(const Duration(milliseconds: 300)),
    );
    addTearDown(lan.close);
    addTearDown(wan.close);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final link = container.read(connectProvider)(
      NetworkConfig(endpoints: [lan.url, wan.url]),
      'instance-a',
    );
    addTearDown(link.close);
    Future<void> fetch() async {
      await (await link.media('media/1')).bytes.drain<void>();
    }

    await fetch();
    expect(lan.served, ['/media/1']);
    expect(wan.served, isEmpty);

    lan.down = true;
    link.networkChanged();
    final took = Stopwatch()..start();
    await fetch();
    expect(took.elapsed, lessThan(const Duration(seconds: 2)));
    expect(wan.served, ['/media/1'], reason: 'on the WAN, with no failure');

    lan.down = false;
    link.networkChanged();
    await Future<void>.delayed(const Duration(seconds: 2));
    await fetch();
    expect(lan.served, ['/media/1', '/media/1'], reason: 'home again');
  });

  test('the session hears every network change', () async {
    final server = FakeServer();
    final changes = StreamController<Object?>();
    final container = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(
          MemoryStore(
            '{"endpoints": ["https://photos.example.org"], "instance": "i", '
            '"headers": {}, "account": {"name": "ann", "token": "t", '
            '"device": "d", "admin": false}}',
          ),
        ),
        connectProvider.overrideWithValue((config, instance) => server),
        networkChangesProvider.overrideWithValue(changes.stream),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountsProvider.future);
    expect(container.read(sessionProvider), isNotNull);
    changes
      ..add(null)
      ..add(null);
    await Future<void>.delayed(Duration.zero);
    expect(server.networkChanges, 2);
  });
}
