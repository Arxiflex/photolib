import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:photolib_data/src/folder_indexer.dart';
import 'package:photolib_data/src/folders.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:web/web.dart' as web;

const _log = Logger('photolib.folders');

/// File System Access, which Chromium has on computers; null in other browsers (docs/10-client-app.md §7.1).
final BrowserFolders? browserFolders = globalContext.has('showDirectoryPicker')
    ? const _Picker()
    : null;

/// The directories this browser was given, by root: kept in IndexedDB, they outlive the page (ADR-0082).
const FolderFiles folderFiles = _Handles();

/// The file at [path] in the folder [root], or null when it is gone or no longer allowed.
Future<web.File?> browserFile(String root, String path) async {
  try {
    return await (await _file(root, path))?.getFile().toDart;
  } catch (_) {
    return null;
  }
}

/// The directory [dir] of the folder [root], asked for write access too, or
/// null when it is gone or refused.
Future<web.FileSystemDirectoryHandle?> writableDirectory(
  String root,
  String dir,
) async {
  try {
    final handle = await _dir(root, dir);
    if (handle == null) return null;
    final state = await _Permissions(
      handle,
    ).requestPermission(_Mode(mode: 'readwrite')).toDart;
    return state.toDart == 'granted' ? handle : null;
  } on Object {
    return null;
  }
}

/// Scans every folder of [db] when the page opens, when one is added and when the page is shown again, as browsers
/// report no changes to files (ADR-0082), until the returned function stops it.
/// [db] calls it before it closes: drift's worker fails rolling back a
/// transaction its client left open as it closed (photolib-design#491).
Future<void> Function() watchLibraryFolders(Replica db) {
  final scans = _scans[db] ??= _Scans(db);
  var roots = <String>{};
  // Not onVisibilityChange, which listens for webkitvisibilitychange in Chromium.
  final shown = const web.EventStreamProvider<web.Event>('visibilitychange')
      .forTarget(web.document)
      .where((_) => web.document.visibilityState == 'visible')
      .listen((_) => scans.queue(roots));
  final folders = watchFolders(db).listen((folders) {
    final now = {for (final f in folders) f.root};
    scans.queue(now.difference(roots));
    roots = now;
  }, onError: (Object _) {});
  return () async {
    await shown.cancel();
    await folders.cancel();
    await scans.stop();
  };
}

/// Adds the directory [handle] to the library under its name, numbered when a folder there has it: false, adding
/// nothing, when it is in the library, or inside or around a folder that is.
Future<bool> addFolderHandle(
  Replica db,
  web.FileSystemDirectoryHandle handle,
) async {
  final roots = {for (final f in await db.select(db.mediaSource).get()) f.root};
  final keys = await _idb((s) => s.getAllKeys()) as JSArray<JSString>;
  for (final key in keys.toDart) {
    if (!roots.contains(key.toDart)) {
      await _idb((s) => s.delete(key), write: true);
      continue;
    }
    final other = (await _root(key.toDart))!;
    // Each await a statement of its own: dart2wasm can hang on one inside a condition.
    final inside = await other.resolve(handle).toDart;
    final around = await handle.resolve(other).toDart;
    if (inside != null || around != null) {
      _log.info(
        'folder not added: inside or around one in the library',
        fields: {'folder': handle.name, 'root': key.toDart},
      );
      return false;
    }
  }
  var root = handle.name;
  for (var n = 2; roots.contains(root); n++) {
    root = '${handle.name} ($n)';
  }
  await _idb((s) => s.put(handle, root.toJS), write: true);
  _log.info(
    'folder handle kept',
    fields: {'folder': handle.name, 'root': root},
  );
  return addFolder(db, root);
}

@JS()
external JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker(
  JSObject options,
);

extension type _Permissions(JSObject _) implements JSObject {
  external JSPromise<JSString> requestPermission(JSObject descriptor);
}

/// A permission descriptor: `{mode: …}`.
extension type _Mode._(JSObject _) implements JSObject {
  external factory _Mode({String mode});
}

class _Picker implements BrowserFolders {
  const _Picker();

  @override
  Future<bool?> pick(Replica db) async {
    final web.FileSystemDirectoryHandle handle;
    try {
      handle = await showDirectoryPicker(_read).toDart;
    } catch (e) {
      _log.info('folder picker closed', fields: {'error': '$e'});
      return null; // AbortError: the user closed the picker.
    }
    return addFolderHandle(db, handle);
  }

  @override
  Future<void> allow(Replica db, String root) async {
    final handle = await _root(root);
    if (handle == null) {
      _log.warning('no handle kept for the folder', fields: {'root': root});
      return;
    }
    final state = await _Permissions(handle).requestPermission(_read).toDart;
    _log.info(
      'folder permission',
      fields: {'root': root, 'state': state.toDart},
    );
    if (state.toDart == 'granted') (_scans[db] ??= _Scans(db)).queue([root]);
  }
}

final _read = {'mode': 'read'}.jsify()! as JSObject;

/// The scans of each replica's folders in its page.
final _scans = Expando<_Scans>();

/// Scans folders one at a time until stopped.
class _Scans {
  _Scans(Replica db) : _indexer = FolderIndexer(db);

  final FolderIndexer _indexer;
  final _waiting = <String>{};
  Future<void>? _running;
  var _stopped = false;

  void queue(Iterable<String> roots) {
    if (_stopped) return;
    _waiting.addAll(roots);
    if (_waiting.isNotEmpty) _running ??= _drain();
  }

  /// Ends the scan under way before its next directory, as a quit does,
  /// and starts no other.
  Future<void> stop() async {
    _stopped = true;
    await _running;
  }

  Future<void> _drain() async {
    while (_waiting.isNotEmpty && !_stopped) {
      final root = _waiting.first;
      _waiting.remove(root);
      try {
        await _indexer.scan(
          root,
          entering: (_) => _stopped ? throw const _Stopped() : null,
        );
      } on _Stopped {
        _log.info('scan stopped', fields: {'root': root});
      } catch (e) {
        // A failed write: the next visit scans again.
        _log.warning('scan failed', fields: {'root': root}, error: e);
      }
    }
    _running = null;
  }
}

class _Stopped implements Exception {
  const _Stopped();
}

class _Handles implements FolderFiles {
  const _Handles();

  @override
  Future<List<FileEntry>?> list(String root, String dir) async {
    final List<web.FileSystemHandle> handles;
    try {
      final handle = await _dir(root, dir);
      if (handle == null) return null;
      handles = (await _all(handle.callMethod('values'.toJS)).toDart).toDart;
    } catch (e) {
      _log.debug(
        'cannot list',
        fields: {'root': root, 'dir': dir, 'error': '$e'},
      );
      return null; // Gone, or no longer allowed.
    }
    final entries = <FileEntry>[];
    final busy = Stopwatch()..start();
    for (final handle in handles) {
      entries.add(_entry(handle));
      // This runs on the page, which renders between slices of a large directory.
      if (busy.elapsedMilliseconds > 8) {
        await Future<void>.delayed(Duration.zero);
        busy.reset();
      }
    }
    return entries;
  }

  @override
  Future<bool?> isEmpty(String root) async {
    try {
      final next = await (await _dir(root, ''))
          ?.callMethod<JSObject>('values'.toJS)
          .callMethod<JSPromise<JSObject>>('next'.toJS)
          .toDart;
      return next == null ? null : (next['done'] as JSBoolean).toDart;
    } catch (_) {
      return null;
    }
  }

  // Not probed as on desktops, which would list a large folder once more: the platform's default file system decides.
  @override
  Future<bool> caseSensitive(String root) async {
    final agent = web.window.navigator.userAgent;
    return !agent.contains('Windows') && !agent.contains('Macintosh');
  }

  @override
  Future<FileInfo?> stat(String root, String path) async {
    final file = await _file(root, path);
    return file == null ? null : _info(file);
  }

  @override
  Future<String> read(String root, String path) async {
    try {
      final file = await _file(root, path);
      return file == null
          ? ''
          : (await (await file.getFile().toDart).text().toDart).toDart;
    } catch (_) {
      return '';
    }
  }
}

@JS('Array.fromAsync')
external JSPromise<JSArray<web.FileSystemHandle>> _all(JSAny? iterator);

// Not inlined in an async loop, where dart2wasm gives the closures made one shared copy of the loop's variables.
FileEntry _entry(web.FileSystemHandle handle) => (
  name: handle.name,
  dir: handle.kind == 'directory',
  info: () => _info(handle as web.FileSystemFileHandle),
);

/// A browser gives no file ids: size and modification time stand in, which a rename or move keeps (ADR-0082).
Future<FileInfo?> _info(web.FileSystemFileHandle handle) async {
  try {
    final file = await handle.getFile().toDart;
    return (
      size: file.size,
      mtime: file.lastModified,
      id: '${file.size}:${file.lastModified}',
    );
  } catch (_) {
    return null;
  }
}

Future<web.FileSystemDirectoryHandle?> _root(String root) async =>
    await _idb((s) => s.get(root.toJS)) as web.FileSystemDirectoryHandle?;

Future<web.FileSystemDirectoryHandle?> _dir(String root, String dir) async {
  var handle = await _root(root);
  for (final name in dir.isEmpty ? const <String>[] : dir.split('/')) {
    handle = await handle?.getDirectoryHandle(name).toDart;
  }
  return handle;
}

Future<web.FileSystemFileHandle?> _file(String root, String path) async {
  final slash = path.lastIndexOf('/');
  try {
    final dir = await _dir(root, slash < 0 ? '' : path.substring(0, slash));
    return await dir?.getFileHandle(path.substring(slash + 1)).toDart;
  } catch (_) {
    return null;
  }
}

Future<web.IDBDatabase>? _opened;

Future<web.IDBDatabase> _database() => _opened ??= () async {
  final open = (globalContext['indexedDB'] as web.IDBFactory).open(
    'photolib/folders',
    1,
  );
  open.onupgradeneeded = ((web.Event _) {
    (open.result as web.IDBDatabase).createObjectStore('roots');
  }).toJS;
  final db = await _done(open) as web.IDBDatabase;
  // Crypto-erase deletes the database (deleteDatabases), which waits until every connection has closed.
  db.onversionchange = ((web.Event _) {
    db.close();
    _opened = null;
  }).toJS;
  return db;
}();

/// The result of [request] on the store of roots.
Future<JSAny?> _idb(
  web.IDBRequest Function(web.IDBObjectStore) request, {
  bool write = false,
}) async {
  final db = await _database();
  return _done(
    request(
      db
          .transaction('roots'.toJS, write ? 'readwrite' : 'readonly')
          .objectStore('roots'),
    ),
  );
}

Future<JSAny?> _done(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request
    ..onsuccess = ((web.Event _) => done.complete(request.result)).toJS
    ..onerror = ((web.Event _) => done.completeError(
      request.error ?? 'IndexedDB failed',
    )).toJS;
  return done.future;
}
