import 'dart:typed_data';

import 'package:photolib_data/src/blake3.dart';
import 'package:test/test.dart';

void main() {
  // BLAKE3's own vectors: the input is bytes 0, 1, … 250, 0, 1, … of each
  // length; across one block, one chunk and a tree of chunks.
  const vectors = {
    0: 'af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262',
    1: '2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213',
    63: 'e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b',
    64: '4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98',
    65: 'de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee',
    1023: '10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11',
    1024: '42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7',
    1025: 'd00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444',
    2048: 'e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a',
    2049: '5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030',
    3072: 'b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2',
    3073: '7124b49501012f81cc7f11ca069ec9226cecb8a2c850cfe644e327d22d3e1cd3',
    8193: 'bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b',
    31744: '62b6960e1a44bcc1eb1a611a8d6235b6b4b78f32e7abc4fb4c6cdcce94895c47',
    102400: 'bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085',
  };
  String hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  Uint8List input(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) i % 251]);

  test('hashes as the reference does, in one piece and in pieces', () {
    for (final MapEntry(key: length, value: hash) in vectors.entries) {
      final bytes = input(length);
      expect(hex(blake3(bytes)), hash, reason: '$length bytes');
      final pieces = Blake3();
      for (var at = 0; at < length; at += 1000) {
        final end = (at + 1000).clamp(0, length);
        pieces.add(Uint8List.sublistView(bytes, at, end));
      }
      expect(hex(pieces.close()), hash, reason: '$length bytes in pieces');
    }
  });
}
