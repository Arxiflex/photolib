import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:photolib/features/map/map_kernel.dart';
import 'package:photolib_api/develop.dart' as d;
import 'package:photolib_api/kernel.dart'
    show CaptureTime, Face, MapFacesRequest, MapFacesResponse, Method;
import 'package:photolib_api/kernel.dart' as k;
import 'package:photolib_data/extract.dart';
import 'package:photolib_data/photolib_data.dart' show LocalAssetData;
import 'package:photolib_editor/edit.dart';
import 'package:photolib_editor/photolib_editor.dart' show Develop;
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_workers/photolib_workers.dart';

/// The keyrings of the kernel that the build hook bundles.
Future<KernelKeyring Function()> loadKernel() async => Kernel().keyring;

/// The row of the file at [path], outside the library, as extraction reads
/// it, a file of its folder: with the bundled kernel on a worker; null when
/// it cannot be read.
Future<LocalAssetData?> readOutside(String path) async {
  final file = File(path);
  final stat = await FileStat.stat(path);
  final name = file.uri.pathSegments.last;
  final [read] = await kernelExtract(_outside)([
    (root: file.parent.path, path: name),
  ], visible: true);
  return read == null
      ? null
      : LocalAssetData(
          id: Uint8List(0),
          source: 'folder',
          volume: file.parent.path,
          sourceId: '',
          path: name,
          size: stat.size,
          mtime: stat.modified.millisecondsSinceEpoch,
          state: 'present',
          favorite: 0,
          trashed: 0,
          edited: 0,
          folder: 0,
          hidden: 0,
          archived: 0,
          tile: 0,
        ).copyWithCompanion(read);
}

final _outside = WorkerPool(const [readMetadata], size: 1);

/// The copy of [original] that [edit] makes, written by the bundled kernel on
/// a worker (ADR-0331).
Future<Uint8List> editCopyOf(
  Uint8List original,
  Edit edit,
  CaptureTime? time,
) async => (await editedCopyOf(original, edit, time)).jpeg;

/// A copy and the part of the edited photo (in its pixels, as turned and
/// mirrored) that it shows, which a lossless crop moves onto the JPEG's
/// block grid; null when the copy shows the whole.
typedef EditedCopy = ({Uint8List jpeg, Rect? crop});

/// [editCopyOf] and the crop the copy really shows (ADR-0389).
Future<EditedCopy> editedCopyOf(
  Uint8List original,
  Edit edit,
  CaptureTime? time,
) async {
  final [jpeg as Uint8List, ...crop] = await _edits.run(_editCopy, [
    original,
    ..._plain(edit, time),
  ]).result;
  return (
    jpeg: jpeg,
    crop: switch (crop) {
      [final int x, final int y, final int w, final int h] => Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        w.toDouble(),
        h.toDouble(),
      ),
      _ => null,
    },
  );
}

/// [faces] of a photo of [width] × [height] (upright) moved to its copy made
/// by [turns] quarter turns, a [flip] and the pixels [crop] of what that gives
/// (null: the whole) by the kernel, or back to the original with [back]: each
/// face with whether at least half of it is in the copy.
Future<List<(Face, bool)>> mapFaces(
  List<Face> faces, {
  required int width,
  required int height,
  required int turns,
  required bool flip,
  required Rect? crop,
  bool back = false,
}) async {
  final request = MapFacesRequest(
    faces: faces,
    width: width,
    height: height,
    toOriginal: back,
    edit: d.Develop(
      quarterTurns: turns,
      flip: flip,
      crop: crop == null
          ? null
          : d.Rect(
              x: crop.left.round(),
              y: crop.top.round(),
              width: crop.width.round(),
              height: crop.height.round(),
            ),
    ),
  );
  final response = k.CallResponse.fromBuffer(
    (_kernel ??= Kernel()).call(
      Method.METHOD_MAP_FACES.value,
      request.writeToBuffer(),
    ),
  );
  if (response.hasError()) {
    throw FormatException('kernel error ${response.error.code.name}');
  }
  final mapped = MapFacesResponse.fromBuffer(response.response);
  return [for (final (i, f) in mapped.faces.indexed) (f, mapped.visible[i])];
}

List<Object?> _plain(Edit edit, CaptureTime? time) {
  final (c, e) = (edit.crop, edit.enhance);
  return [
    edit.quarterTurns,
    edit.flip,
    ...[c.left, c.top, c.right, c.bottom],
    if (e == null)
      null
    else
      [e.temperature, e.tint, e.exposure, e.contrast, e.saturation],
    time?.localDatetime,
    if (time != null && time.hasOffsetMinutes()) time.offsetMinutes else null,
  ];
}

final _edits = WorkerPool(const [_editCopy], size: 1);
Kernel? _kernel;

const _editCopy = Task<List<Object?>, List<Object?>>('editCopy', _copy);

Future<List<Object?>> _copy(List<Object?> input, TaskContext _) async {
  final [
    original as Uint8List,
    turns as int,
    flip as bool,
    l as double,
    t as double,
    r as double,
    b as double,
    enhance as List<Object?>?,
    local as String?,
    offset as int?,
  ] = input;
  final adjust = enhance?.cast<double>();
  final edit = Edit(
    quarterTurns: turns,
    flip: flip,
    crop: Rect.fromLTRB(l, t, r, b),
    enhance: adjust == null
        ? null
        : Develop(
            temperature: adjust[0],
            tint: adjust[1],
            exposure: adjust[2],
            contrast: adjust[3],
            saturation: adjust[4],
          ),
  );
  final time = local == null
      ? null
      : CaptureTime(localDatetime: local, offsetMinutes: offset);
  final kernel = _kernel ??= Kernel();
  final copy = editCopy(kernel.call, original, edit, time: time);
  return [
    Uint8List.fromList(copy.jpeg),
    if (copy.hasCrop()) ...[
      copy.crop.x,
      copy.crop.y,
      copy.crop.width,
      copy.crop.height,
    ],
  ];
}

/// A kernel on an isolate of its own for the map's index; its calls travel as
/// transferred bytes, so that a million positions cost the UI no copy.
Future<MapKernel> openMapKernel() async {
  final replies = ReceivePort();
  final commands = Completer<SendPort>();
  final pending = <int, Completer<Uint8List>>{};
  var closed = false;
  final worker = await Isolate.spawn(_serveMap, replies.sendPort);
  replies.listen((message) {
    if (message is SendPort) {
      commands.complete(message);
    } else if (message case (final int id, final TransferableTypedData bytes)) {
      pending.remove(id)?.complete(bytes.materialize().asUint8List());
    }
  });
  var next = 0;
  Future<Uint8List> call(int method, Uint8List request) async {
    if (closed) throw StateError('the map kernel is closed');
    final port = await commands.future;
    final answer = Completer<Uint8List>();
    pending[++next] = answer;
    port.send((next, method, TransferableTypedData.fromList([request])));
    return await answer.future;
  }

  return MapKernel(call, () async {
    if (closed) return;
    closed = true;
    worker.kill(priority: Isolate.immediate);
    replies.close();
    for (final waiting in pending.values) {
      waiting.completeError(StateError('the map kernel is closed'));
    }
    pending.clear();
  });
}

void _serveMap(SendPort replies) {
  final commands = ReceivePort();
  final keyring = Kernel().keyring();
  replies.send(commands.sendPort);
  commands.listen((message) {
    final (id, method, bytes) = message as (int, int, TransferableTypedData);
    final answer = keyring.call(method, bytes.materialize().asUint8List());
    replies.send((id, TransferableTypedData.fromList([answer])));
  });
}
