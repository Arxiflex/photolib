import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/nearby.dart';

Uint8List hex(String file) {
  final text = File('../testdata/discovery/$file').readAsStringSync().trim();
  return Uint8List.fromList([
    for (var at = 0; at < text.length; at += 2)
      int.parse(text.substring(at, at + 2), radix: 16),
  ]);
}

// LAN discovery (OPS-29): the app asks the network for Photolib servers and
// lists what photolibd answers (server/crates/photolib-server/src/discovery.rs,
// whose answer to this question is testdata/discovery/answer.hex).
void main() {
  test(
    'the question is the one photolibd answers, and its answer lists the '
    "server's address on this network, its public URL and its instance",
    () async {
      final responder = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(responder.close);
      final questions = <List<int>>[];
      responder.listen((event) {
        final question = responder.receive();
        if (question == null) return;
        questions.add(question.data);
        for (final reply in [
          hex('answer.hex'),
          Uint8List.fromList([1, 2, 3]),
          hex('answer.hex'),
        ]) {
          responder.send(reply, question.address, question.port);
        }
      });
      final found = await nearbyServers(
        to: InternetAddress.loopbackIPv4,
        port: responder.port,
        wait: const Duration(milliseconds: 500),
      );
      expect(questions, [hex('query.hex')]);
      expect(found, hasLength(1), reason: 'garbage ignored, the same once');
      expect(found.single.name, 'photolib-018f9d2e');
      expect(found.single.instance, '018f9d2e-7c1b-7d6e-9a3f-2b4c5d6e7f80');
      expect(found.single.endpoints, [
        Uri.parse('http://127.0.0.1:8080/photos/'),
        Uri.parse('https://photos.example.org/photos/'),
      ]);
    },
  );

  test('no answer lists nothing', () async {
    final silent = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(silent.close);
    expect(
      await nearbyServers(
        to: InternetAddress.loopbackIPv4,
        port: silent.port,
        wait: const Duration(milliseconds: 200),
      ),
      isEmpty,
    );
  });
}
