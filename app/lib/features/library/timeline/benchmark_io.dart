import 'dart:io';
import 'dart:typed_data';

import 'package:photolib/core/kernel.dart';
import 'package:photolib_data/testing.dart' show scratchVault;

import 'disk_cache.dart';
import 'native_pipeline.dart';
import 'pipeline.dart';
import 'thumbnails.dart';

/// The desktop thumbnail pipeline over the JPEGs as files: an asset's first
/// decode reads its file (T4) and writes its tile to a disk cache (T2). The
/// second value removes the files.
Future<(Map<String, ThumbnailSource>, Future<void> Function())> platformSources(
  List<Uint8List> jpegs,
) async {
  final scratch = await Directory.systemTemp.createTemp('timeline-bench');
  for (var i = 0; i < jpegs.length; i++) {
    await File('${scratch.path}/$i.jpg').writeAsBytes(jpegs[i]);
  }
  final (vault, cipher) = await scratchVault(
    '${scratch.path}/store',
    await loadKernel(),
  );
  final cache = await DiskCache.open(
    '${scratch.path}/cache',
    cipher,
    maxBytes: 256 << 20,
  );
  final pipeline = await desktopPipeline(cache);
  return (
    {
      'pipeline': (Object asset, int tier, Tile tile) => pipeline.load(
        ThumbnailItem(
          '$asset',
          Uri.file('${scratch.path}/${(asset as int) % jpegs.length}.jpg'),
        ),
        tier,
        tile,
      ),
    },
    () async {
      await pipeline.idle;
      await cache.close();
      await vault.lock();
      // deletion-ok: the benchmark's scratch cache
      await scratch.delete(recursive: true);
    },
  );
}
