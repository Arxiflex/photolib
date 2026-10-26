// The deprecated library is drift's sql.js backend; its port channel is the one drift's own web workers use.
// ignore: deprecated_member_use
import 'package:drift/web.dart' show WebPortToChannel;
import 'package:stream_channel/stream_channel.dart';
import 'package:web/web.dart';

/// [port] as a channel of drift's remote protocol, with the serialization drift's own web workers use, which keeps
/// integers and SQLite errors; both ends call this, and talk with `serialize: false`.
StreamChannel<Object?> portChannel(MessagePort port) => port.channel(
  explicitClose: true,
  webNativeSerialization: true,
  nativeSerializionVersion: 4,
);
