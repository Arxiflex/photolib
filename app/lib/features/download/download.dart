import 'dart:async';

import 'package:flutter/foundation.dart';

import 'zip.dart';

/// An item's file as it downloads: its bytes, read once, when it was taken,
/// which it keeps as its modified time, and its size where known.
class DownloadFile {
  const DownloadFile(this.bytes, {required this.modified, this.size});

  final Stream<List<int>> bytes;
  final DateTime modified;
  final int? size;
}

/// An item to download (MIG-15): its original file name, its original's
/// bytes and, where an edit exists, its current version's.
class Download {
  const Download(
    this.name,
    this.original, {
    this.edited,
    this.editedName,
    this.folder,
  });

  final String name;
  final Future<DownloadFile> Function() original;
  final Future<DownloadFile> Function()? edited;

  /// The name of the edited file where it is not [name]: the edited version
  /// of a HEIC is a JPEG (ADR-0391).
  final String? editedName;

  /// The archive's folder it goes in: its album's, when several download.
  final String? folder;
}

/// Where downloads go: a folder the user picks, the browser's downloads.
abstract interface class Destination {
  /// Writes [bytes] as a file called [name] where the user chooses, last
  /// [modified] where the destination keeps that; false when they choose
  /// nowhere. A failure, or a cancel, which [bytes] raise, leaves nothing
  /// there.
  Future<bool> save(String name, Stream<List<int>> bytes, {DateTime? modified});
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// A download of [count] items under way: how far it is, from 0 to 1 when
/// known, and a way to stop it.
class DownloadJob extends ChangeNotifier implements ValueListenable<double?> {
  DownloadJob(this.count);

  final int count;
  var _finished = 0;
  double? _fraction;
  var _cancelled = false;
  void Function()? _stop;

  @override
  double? get value => _finished == count
      ? 1
      : count == 1
      ? _fraction
      : (_finished + (_fraction ?? 0)) / count;

  void cancel() {
    _cancelled = true;
    _stop?.call();
  }

  /// Saves [items] to [to]: one under its own name, several as a zip called
  /// [archive], each item's current version unless [original]. The name
  /// saved, or null when the user chose nowhere.
  Future<String?> save(
    Destination to,
    Stream<Download> items, {
    String? archive,
    bool original = false,
  }) async {
    Future<DownloadFile> open(Download item) =>
        (original ? null : item.edited)?.call() ?? item.original();
    // The name of the file `open` gives: the edited file's own, if it has one.
    String called(Download item) => original || item.edited == null
        ? item.name
        : item.editedName ?? item.name;
    final String name;
    final Stream<List<int>> bytes;
    DateTime? modified;
    if (archive == null) {
      final item = await items.first;
      final file = await open(item);
      name = called(item);
      modified = file.modified;
      bytes = _read(file);
    } else {
      name = archive;
      final used = <String?, Set<String>>{};
      bytes = zip(
        items.asyncMap((item) async {
          final file = await open(item);
          final folder = switch (item.folder) {
            final folder? => '${_safe(folder)}/',
            null => '',
          };
          final names = used.putIfAbsent(item.folder, () => {});
          return (
            name: '$folder${uniqueName(called(item), names)}',
            modified: file.modified,
            bytes: _read(file),
          );
        }),
      );
    }
    return await to.save(name, bytes, modified: modified) ? name : null;
  }

  // Counts [file]'s bytes, and stops at once on a cancel, even while its
  // source waits for more: an async* generator would only see the cancel at
  // its next chunk.
  Stream<List<int>> _read(DownloadFile file) {
    StreamSubscription<List<int>>? source;
    late final StreamController<List<int>> out;
    var got = 0;
    void stop() {
      source?.cancel();
      out
        ..addError(const DownloadCancelled())
        ..close();
    }

    out = StreamController(
      onListen: () {
        if (_cancelled) return stop();
        _stop = stop;
        source = file.bytes.listen(
          (chunk) {
            got += chunk.length;
            if (file.size case final size? when size > 0) {
              _fraction = got / size;
              notifyListeners();
            }
            out.add(chunk);
          },
          onError: out.addError,
          onDone: () {
            _stop = _fraction = null;
            _finished++;
            notifyListeners();
            out.close();
          },
        );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        source?.cancel();
      },
    );
    return out.stream;
  }
}

/// [name] as a file of an archive's folder, or with [file] false a folder,
/// which no unzipper takes for a path, numbered when [used] has it already
/// as file systems that ignore case would see it.
String uniqueName(String name, Set<String> used, {bool file = true}) {
  final safe = _safe(name);
  final dot = file ? safe.lastIndexOf('.') : -1;
  final (stem, extension) = dot > 0
      ? (safe.substring(0, dot), safe.substring(dot))
      : (safe, '');
  var unique = safe;
  for (var n = 2; !used.add(unique.toLowerCase()); n++) {
    unique = '$stem ($n)$extension';
  }
  return unique;
}

String _safe(String name) {
  final safe = name.replaceAll(RegExp(r'[/\\]'), '_');
  return safe.replaceAll('.', '').isEmpty ? '_' : safe;
}
