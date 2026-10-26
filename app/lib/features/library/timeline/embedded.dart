import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib_api/kernel.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_workers/photolib_workers.dart';

/// The JPEG a file holds as a picture of itself (docs/10-client-app.md §3.4,
/// T2.5): EXIF's thumbnail, a RAW's preview, as the kernel finds it without
/// decoding the original; its [largest], which the viewer shows of a RAW
/// (§4.1). Turned as the file is; read on two workers; null when the file has
/// none.
Future<Uint8List?> embeddedPreview(
  ThumbnailItem item, {
  bool largest = false,
}) => item.video || !item.uri.isScheme('file')
    ? Future.value()
    : _pool.run(largest ? _largest : _smallest, item.uri.toFilePath()).result;

/// The largest JPEG the file at [path] holds, turned as the file is: what a
/// desktop shows of a RAW (docs/08-media-pipeline.md §2.1); null when there
/// is none.
Future<Uint8List?> largestPreview(String path) =>
    _pool.run(_largest, path).result;

final _pool = WorkerPool([_smallest, _largest], size: 2);
const _smallest = Task<String, Uint8List?>('embeddedPreview', _readSmallest);
const _largest = Task<String, Uint8List?>('largestPreview', _readLargest);
final _kernel = Kernel();

Future<Uint8List?> _readSmallest(String path, TaskContext _) =>
    _read(path, (meta) => meta.hasPreview() ? meta.preview : null, 4 << 20);

Future<Uint8List?> _readLargest(String path, TaskContext _) => _read(
  path,
  (meta) => meta.hasLargestPreview() ? meta.largestPreview : null,
  64 << 20,
  whole: true,
);

/// [jpeg] with its EXIF segments replaced by one that holds EXIF
/// [orientation] alone: a preview is stored as its file is, so turns as it
/// does (docs/08-media-pipeline.md §4.2), whatever it says itself.
Uint8List oriented(Uint8List jpeg, int orientation) {
  if (orientation < 1 || orientation > 8) return jpeg;
  final out = BytesBuilder(copy: false)
    ..add(jpeg.sublist(0, 2))
    ..add([0xff, 0xe1, 0, 34, ...'Exif'.codeUnits, 0, 0])
    ..add([...'MM'.codeUnits, 0, 42, 0, 0, 0, 8, 0, 1])
    ..add([1, 0x12, 0, 3, 0, 0, 0, 1, 0, orientation, 0, 0, 0, 0, 0, 0]);
  var at = 2;
  // The segments before the scan, but EXIF's.
  while (at + 4 <= jpeg.length && jpeg[at] == 0xff && jpeg[at + 1] != 0xda) {
    final end = at + 2 + (jpeg[at + 2] << 8 | jpeg[at + 3]);
    if (end > jpeg.length) break;
    final exif =
        jpeg[at + 1] == 0xe1 &&
        String.fromCharCodes(jpeg, at + 4, min(end, at + 8)) == 'Exif';
    if (!exif) out.add(Uint8List.sublistView(jpeg, at, end));
    at = end;
  }
  return (out..add(Uint8List.sublistView(jpeg, at))).takeBytes();
}

// The first 64 KiB, then what the kernel asks for, in at most four rounds as
// metadata extraction reads, then the preview [pick] chooses, of at most
// [limit] bytes; after every round when [whole], as a larger one may follow.
Future<Uint8List?> _read(
  String path,
  ByteSpan? Function(ReadMetadataResponse) pick,
  int limit, {
  bool whole = false,
}) async {
  final file = await File(path).open();
  try {
    final size = await file.length();
    Future<FileRange> range(int at, int length) async => FileRange(
      offset: Int64(at),
      data: await (await file.setPosition(at)).read(length),
    );
    final ranges = [await range(0, min(size, 64 << 10))];
    for (var round = 0; round < 4; round++) {
      final answer = CallResponse.fromBuffer(
        _kernel.call(
          Method.METHOD_READ_METADATA.value,
          ReadMetadataRequest(
            ranges: ranges,
            size: Int64(size),
          ).writeToBuffer(),
        ),
      );
      if (!answer.hasResponse()) return null;
      final meta = ReadMetadataResponse.fromBuffer(answer.response);
      final missing = [
        for (final span in meta.missing)
          if (span.offset < size) span,
      ];
      if (pick(meta) case final span?
          when !whole || missing.isEmpty || round == 3) {
        final length = span.length.toInt();
        if (length > limit || span.offset + length > size) return null;
        final preview = await range(span.offset.toInt(), length);
        return oriented(Uint8List.fromList(preview.data), meta.orientation);
      }
      if (missing.isEmpty) return null;
      for (final span in missing) {
        final at = span.offset.toInt();
        ranges.add(await range(at, min(span.length.toInt(), size - at)));
      }
    }
    return null;
  } finally {
    await file.close();
  }
}
