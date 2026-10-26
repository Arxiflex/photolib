import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'package:photolib_api/src/diagnose.dart';
import 'package:photolib_api/src/network.dart';

/// The browser's fetch: the browser owns TLS, so a private CA or a client certificate must be installed in the
/// browser or the operating system, and the browser's proxy settings apply.
http.Client stack(NetworkConfig config) => BrowserClient();

/// The browser decides which certificates it trusts.
Future<String?> certificate(NetworkConfig config, Uri url) async => null;

/// [host] if it is an address, loopback for `localhost`, which browsers
/// keep there; nothing for another name, which the browser resolves without
/// saying to what.
Future<List<List<int>>> addresses(String host) async {
  if (host == 'localhost') return [Uri.parseIPv4Address('127.0.0.1')];
  try {
    final parse = host.contains(':')
        ? Uri.parseIPv6Address
        : Uri.parseIPv4Address;
    return [parse(host)];
  } on FormatException {
    return [];
  }
}

/// The browser resolves, connects and shakes hands unseen: the steps before the
/// server's answer do not run.
Stream<Finding> reach(NetworkConfig config, Uri endpoint, DateTime now) =>
    Stream.fromIterable([
      for (final step in [CheckStep.dns, CheckStep.tcp, CheckStep.tls])
        Finding(step, ran: false),
    ]);

/// The gzip [data] inflates to, through the browser's DecompressionStream; a
/// FormatException when it is broken or would exceed [limit] bytes.
Future<Uint8List> gunzip(Uint8List data, int limit) async {
  final reader = _Response(data.toJS).body
      .pipeThrough(_Decompression('gzip'))
      .getReader();
  final out = BytesBuilder(copy: false);
  try {
    while (out.length <= limit) {
      final chunk = await reader.read().toDart;
      if (chunk.done) return out.takeBytes();
      if (chunk.value case final value?) out.add(value.toDart);
    }
  } on Object {
    throw const FormatException('a broken gzip message');
  }
  reader.cancel();
  throw const FormatException('gzip past its limit');
}

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external new(JSUint8Array body);
  external _Stream get body;
}

@JS('DecompressionStream')
extension type _Decompression._(JSObject _) implements JSObject {
  external new(String format);
}

extension type _Stream._(JSObject _) implements JSObject {
  external _Stream pipeThrough(_Decompression transform);
  external _Reader getReader();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_Chunk> read();
  external JSPromise<JSAny?> cancel();
}

extension type _Chunk._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}
