import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:photolib/features/map/map_kernel.dart';
import 'package:photolib_api/kernel.dart' show CaptureTime, Face;
import 'package:photolib_data/photolib_data.dart' show LocalAssetData;
import 'package:photolib_editor/edit.dart' show Edit;
import 'package:photolib_kernel/photolib_kernel_web.dart';

/// The keyrings of the kernel's module, which tools/kernel/wasm.sh writes into web/kernel/.
Future<KernelKeyring Function()> loadKernel() async =>
    (await Kernel.load(Uri.base.resolve('kernel/photolib_kernel_wasm.js')))
        .keyring;

/// Browsers open no files outside the library.
Future<LocalAssetData?> readOutside(String path) async => null;

/// A copy and the part of the edited photo it shows.
typedef EditedCopy = ({Uint8List jpeg, Rect? crop});

/// Browsers edit nothing yet.
Future<EditedCopy> editedCopyOf(
  Uint8List original,
  Edit edit,
  CaptureTime? time,
) => throw UnsupportedError('editing in a browser');

/// A browser has no isolates: the map's index lives in the page, in a keyring
/// of its own.
Future<MapKernel> openMapKernel() async {
  final keyring = (await loadKernel())();
  var closed = false;
  return MapKernel(
    (method, request) async {
      if (closed) throw StateError('the map kernel is closed');
      return keyring.call(method, request);
    },
    () async {
      if (closed) return;
      closed = true;
      keyring.close();
    },
  );
}

/// Browsers edit nothing yet, so no face moves with an edit.
Future<List<(Face, bool)>> mapFaces(
  List<Face> faces, {
  required int width,
  required int height,
  required int turns,
  required bool flip,
  required Rect? crop,
  bool back = false,
}) => throw UnsupportedError('editing in a browser');
