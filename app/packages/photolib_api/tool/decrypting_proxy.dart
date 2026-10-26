// The decrypting loopback proxy that tools/playback/bench.mjs measures: `dart run tool/decrypting_proxy.dart <origin>
// <kernel library> <key in hex> <path>...` serves each encrypted original at <origin><path> in plaintext, opened by the
// kernel's DecryptBlob through the C ABI, and prints the URL a player reads it from, one line per path.
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/media_proxy.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/src/gen/photolib/kernel/v1/blob.pb.dart';
import 'package:photolib_api/src/gen/photolib/kernel/v1/call.pb.dart';
import 'package:photolib_api/src/gen/photolib/kernel/v1/keys.pb.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

Future<void> main(List<String> args) async {
  final [origin, library, hex, ...paths] = args;
  final keyring = Kernel.open(library).keyring();
  CallResponse call(Method method, List<int> request) =>
      CallResponse.fromBuffer(
        keyring.call(method.value, Uint8List.fromList(request)),
      );
  final secret = [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  final key = KeyResponse.fromBuffer(
    call(
      Method.METHOD_IMPORT_KEY,
      ImportKeyRequest(secret: secret).writeToBuffer(),
    ).response,
  ).key;
  Uint8List? open(Uint8List header, int first, Uint8List chunks, bool more) {
    final request = DecryptBlobRequest(
      key: key,
      kind: 1,
      envelope:
          (BytesBuilder(copy: false)
                ..add(header)
                ..add(chunks))
              .takeBytes(),
      firstChunk: Int64(first),
      more: more,
    );
    final answer = call(Method.METHOD_DECRYPT_BLOB, request.writeToBuffer());
    if (!answer.hasResponse()) return null;
    return Uint8List.fromList(
      DecryptBlobResponse.fromBuffer(answer.response).plaintext,
    );
  }

  final proxy = await MediaProxy.start(
    Server(NetworkConfig(endpoints: [Uri.parse(origin)])),
  );
  for (final path in paths) {
    print(proxy.decrypted(path, 'video/mp4', open));
  }
}
