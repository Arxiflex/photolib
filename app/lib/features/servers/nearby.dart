import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A Photolib server that answered on the local network: its name, its
/// addresses (this network's first, then `public_url`) and its instance.
typedef Nearby = ({String name, List<Uri> endpoints, String instance});

const _service = '_photolib._tcp.local';

/// The Photolib servers on this network, asked while a page shows them; none
/// in a browser, which sends no UDP.
final FutureProvider<List<Nearby>> nearbyProvider = FutureProvider.autoDispose(
  (ref) => kIsWeb ? Future.value(const <Nearby>[]) : nearbyServers(),
);

/// The multicast DNS question for Photolib servers (DNS-SD PTR
/// `_photolib._tcp.local`, OPS-29), which photolibd answers.
final Uint8List discoveryQuery = Uint8List.fromList([
  ...[0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
  for (final label in _service.split('.')) ...[
    label.length,
    ...ascii.encode(label),
  ],
  ...[0, 0, 12, 0, 1],
]);

/// Asks the local network for Photolib servers from an ephemeral port, which
/// responders answer by unicast (RFC 6762 §6.7), and lists each that answers
/// within [wait]: no multicast port to bind, no location permission. Tests
/// ask [to] at [port] instead of the multicast group.
Future<List<Nearby>> nearbyServers({
  InternetAddress? to,
  int port = 5353,
  Duration wait = const Duration(seconds: 2),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final found = <String, Nearby>{};
  final listening = socket.listen((event) {
    final datagram = event == RawSocketEvent.read ? socket.receive() : null;
    if (datagram == null) return;
    if (_read(_Packet(datagram.data), datagram.address) case final server?) {
      found.putIfAbsent(server.instance, () => server);
    }
  });
  socket.send(discoveryQuery, to ?? InternetAddress('224.0.0.251'), port);
  await Future<void>.delayed(wait);
  await listening.cancel();
  socket.close();
  return [...found.values];
}

/// The server an answer from [from] describes; null for anything else.
Nearby? _read(_Packet packet, InternetAddress from) {
  try {
    var at = 12;
    for (var i = packet.u16(4); i > 0; i--) {
      at = packet.name(at).$2 + 4;
    }
    final records = packet.u16(6) + packet.u16(8) + packet.u16(10);
    String? name;
    int? port;
    final txt = <String, String>{};
    for (var i = 0; i < records; i++) {
      final (owner, end) = packet.name(at);
      final (kind, start) = (packet.u16(end), end + 10);
      at = start + packet.u16(end + 8);
      if (!owner.toLowerCase().endsWith('.$_service')) continue;
      name = owner.substring(0, owner.length - _service.length - 1);
      if (kind == 33) port = packet.u16(start + 4);
      for (var entry = start; kind == 16 && entry < at;) {
        final text = packet.text(entry + 1, packet.byte(entry));
        entry += 1 + packet.byte(entry);
        final equals = text.indexOf('=');
        if (equals > 0) {
          txt[text.substring(0, equals)] = text.substring(equals + 1);
        }
      }
    }
    final instance = txt['instance'];
    if (name == null || port == null || instance == null) return null;
    final host = from.type == InternetAddressType.IPv6
        ? '[${from.address}]'
        : from.address;
    return (
      name: name,
      endpoints: [
        Uri.parse('http://$host:$port${txt['path'] ?? '/'}'),
        if (txt['url'] case final url?) Uri.parse(url),
      ],
      instance: instance,
    );
  } on FormatException {
    return null;
  }
}

/// A DNS message whose reads past its end throw a [FormatException].
class _Packet {
  const new(this._bytes);
  final Uint8List _bytes;

  int byte(int at) => at >= 0 && at < _bytes.length
      ? _bytes[at]
      : throw const FormatException('a short packet');

  int u16(int at) => byte(at) << 8 | byte(at + 1);

  String text(int at, int length) {
    byte(at + length - 1);
    return utf8.decode(
      Uint8List.sublistView(_bytes, at, at + length),
      allowMalformed: true,
    );
  }

  /// The name at [start] and where its encoding ends, following compression.
  (String, int) name(int start) {
    final labels = <String>[];
    int? end;
    var at = start;
    for (var jumps = 0; jumps < 128; jumps++) {
      final length = byte(at);
      if (length == 0) return (labels.join('.'), end ?? at + 1);
      if (length & 0xC0 == 0xC0) {
        end ??= at + 2;
        at = (length & 0x3F) << 8 | byte(at + 1);
      } else {
        labels.add(text(at + 1, length));
        at += 1 + length;
      }
    }
    throw const FormatException('a name that loops');
  }
}
