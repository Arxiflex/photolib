// What photolibd sends, for the sync tests and for the stand-in that photolibd.dart runs in a process of its own.
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';

/// The uuid of `n`, as photolibd sends one.
String uuid(int n) =>
    '018f3b52-4b7b-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

/// Its 16 bytes, as the replica keeps them.
Uint8List bytes(int n) => Uint8List.fromList([
  for (var i = 0; i < 32; i += 2)
    int.parse(uuid(n).replaceAll('-', '').substring(i, i + 2), radix: 16),
]);

/// Rows of photolibd's `entity`, the columns of the first.
pb.Rows rows(
  String entity,
  List<Map<String, Object?>> values, {
  bool deleted = false,
}) => pb.Rows(
  entity: entity,
  columns: values.first.keys,
  deleted: deleted,
  rows: [
    for (final row in values)
      pb.Row(
        values: [
          for (final v in row.values)
            switch (v) {
              null => pb.Value(),
              String() => pb.Value(text: v),
              int() => pb.Value(integer: Int64(v)),
              double() => pb.Value(real: v),
              bool() => pb.Value(boolean: v),
              List<int>() => pb.Value(blob: v),
              _ => throw ArgumentError(v),
            },
        ],
      ),
  ],
);

Map<String, Object?> library(int n, {int owner = 100}) => {
  'id': uuid(n),
  'owner_id': uuid(owner),
  'name': 'Library $n',
  'kind': 'managed',
  'privacy': 'standard',
  'access': 'rw',
  'is_upload_target': true,
  'state': 'online',
  'created_at': 1,
  'txid': 7,
};

/// Bob's (200) partner share with Ann (100), of what he took since [since].
Map<String, Object?> partnerShare(String? since) => {
  'owner_id': uuid(200),
  'partner_id': uuid(100),
  'taken_since': since,
  'txid': 6,
};

/// An asset as photolibd sends it: every column but raw_metadata, in table order, as a camera's JPEG has them.
Map<String, Object?> asset(
  int n, {
  int library = 1,
  int owner = 100,
  String? title,
}) => {
  'id': uuid(n),
  'library_id': uuid(library),
  'owner_id': uuid(owner),
  'original_filename': 'IMG_$n.jpg',
  'source': 'upload',
  'source_ref': null,
  'created_at': 1714687200000 + n,
  'content_hash': List.filled(32, n % 256),
  'media_kind': 'image',
  'facets': '["live","raw"]',
  'taken_local': '2024-05-03T00:30:00',
  'tz_offset_min': 60,
  'tz_name': null,
  'taken_utc': 1714687200000 + n,
  'time_source': 'exif',
  'time_confidence': 90,
  'time_precision': 'second',
  'tz_assumed': false,
  'lat': 38.7,
  'lon': -9.1,
  'alt': 80.0,
  'accuracy_m': null,
  'location_source': 'exif',
  'place_id': null,
  'width': 4000,
  'height': 3000,
  'orientation': 1,
  'duration_ms': null,
  'fps': null,
  'codec': null,
  'bitrate': null,
  'color': '{"space": "sRGB"}',
  'file_size_total': 8000000,
  'make': 'Canon',
  'model': 'Canon EOS R5',
  'lens': 'RF24-105mm F4 L IS USM',
  'focal_mm': 50.0,
  'focal_35mm': 50.0,
  'f_number': 4.0,
  'exposure_s': 0.004,
  'iso': 100,
  'flash': 'off',
  'software': 'Firmware 1.8.1',
  'title': title,
  'description': null,
  'rating': 0,
  'color_label': null,
  'archived': false,
  'locked': false,
  'trashed_at': null,
  'field_hlc': '{}',
  'rights': null,
  'stack_id': null,
  'stack_order': null,
  'current_version_id': null,
  'meta_core': null,
  'meta_user': null,
  'meta_ml': null,
  'txid': 9,
  'burst_id': null,
  'thumbhash': List.filled(25, 3),
};

/// An asset's original as photolibd sends it: every column but storage and key.
Map<String, Object?> file(int n, {int asset = 0}) => {
  'id': uuid(1000 + n),
  'asset_id': uuid(asset == 0 ? n : asset),
  'role': 'original',
  'mime': 'image/jpeg',
  'size': 8000000,
  'content_hash': List.filled(32, n % 256),
  'state': 'present',
  'crypto_header': null,
  'render_spec': null,
  'created_at': 1714687200000 + n,
  'txid': 9,
  'byte_offset': null,
};

/// Batch [b] of library [library], encoded as a SyncBatch's changes: a thousand assets with their originals. One batch is encoded once and its ids rewritten for each, as encoding them
/// all would make this stand-in, not the sync, set the pace.
Uint8List photolibdBatch(int library, int b) {
  final batch = Uint8List.fromList(_template.$1);
  for (final (at, n) in _template.$2) {
    final id = switch (n) {
      1 => library,
      >= 10000000 => library * 10000000 + b * 2000 + n - 10000000,
      _ => n,
    };
    batch.setRange(
      at,
      at + 12,
      id.toRadixString(16).padLeft(12, '0').codeUnits,
    );
  }
  return batch;
}

/// Batch 0 of library 1, and where each uuid's number is in it.
final _template = () {
  final assets = [for (var i = 0; i < 1000; i++) 10000000 + i * 2 + 1];
  final bytes = pb.SyncBatch(
    changes: [
      rows('assets', [for (final n in assets) asset(n)]),
      rows('asset_files', [for (final n in assets) file(n)]),
    ],
  ).writeToBuffer();
  final prefix = uuid(0).substring(0, 24);
  final ids = <(int, int)>[];
  for (var at = 0; at + 36 <= bytes.length; at++) {
    if (String.fromCharCodes(bytes, at, at + 24) != prefix) continue;
    ids.add((
      at + 24,
      int.parse(String.fromCharCodes(bytes, at + 24, at + 36), radix: 16),
    ));
    at += 35;
  }
  return (bytes, ids);
}();

/// Makes library [n] Ann's with [assets] assets, in place of library [n] − 1.
void Function(SyncServer) newLibrary(int n, int assets) =>
    (s) => s.streams
      ..['libraries'] = [
        ...s.streams['libraries']!,
        [
          rows('libraries', [library(n)]),
          if (n > 0)
            rows('libraries', [
              {'id': uuid(n - 1)},
            ], deleted: true),
        ],
      ]
      ..['assets/${uuid(n)}'] = Iterable.generate(
        assets ~/ 1000,
        (b) => photolibdBatch(n, b),
      )
      ..['faces/${uuid(n)}'] = [];
