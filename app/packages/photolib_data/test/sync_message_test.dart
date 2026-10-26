// What a browser's data worker reads of the server's sync batches: dart2js's
// bit operations are 32 bits wide, and a timestamp in milliseconds is not
// (`dart test -p chrome -c dart2js test/sync_message_test.dart`, the `web`
// part of tools/check.sh; the VM runs it with the rest).
import 'dart:typed_data';

import 'package:photolib_data/src/sync_message.dart';
import 'package:test/test.dart';

List<int> varint(int value) {
  final bytes = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    bytes.add(rest % 0x80 | 0x80);
    rest ~/= 0x80;
  }
  return [...bytes, rest];
}

List<int> field(int tag, List<int> body) => [
  tag,
  ...varint(body.length),
  ...body,
];

/// A batch of the stream `assets` with one row that holds [values], as
/// zigzag integers.
Uint8List response(List<int> values) {
  int zigzag(int n) => n >= 0 ? n * 2 : -n * 2 - 1;
  final row = [
    for (final v in values) ...field(0x0a, [0x10, ...varint(zigzag(v))]),
  ];
  final group = [
    ...field(0x0a, 'assets'.codeUnits),
    ...field(0x12, 'id'.codeUnits),
    ...field(0x1a, row),
  ];
  final batch = [...field(0x0a, 'assets'.codeUnits), ...field(0x1a, group)];
  return Uint8List.fromList(field(0x0a, batch));
}

void main() {
  test('integers past 32 bits come out as they went in', () {
    const values = [
      0,
      1,
      -1,
      -2,
      2147483647,
      4294967296,
      1761378075126,
      -1761378075126,
      4503599627370495,
    ];
    final message = SyncMessage(response(values));
    final rows = [
      for (final rows in message.changes)
        for (var i = 0; i < rows.length; i++) rows.values(i),
    ];
    expect(rows.single, values);
  });
}
