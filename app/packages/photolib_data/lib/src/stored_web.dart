import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Everything this origin stores, by place: the files of its origin-private file system and the values of every
/// IndexedDB database, as a copy of the browser profile holds them. A browser stores by origin, not by [location].
Future<Map<String, Uint8List>> storedBytes(String location) async {
  final stored = <String, Uint8List>{};
  Future<void> walk(JSObject dir, String path) async {
    final entries = dir.callMethod<JSObject>('values'.toJS);
    while (true) {
      final next = await entries
          .callMethod<JSPromise<JSObject>>('next'.toJS)
          .toDart;
      if ((next['done'] as JSBoolean).toDart) return;
      final handle = next['value'] as FileSystemHandle;
      final name = '$path/${handle.name}';
      if (handle.kind == 'directory') {
        await walk(handle, name);
      } else {
        stored[name] = await _retry(
          () async =>
              _bytes(await (handle as FileSystemFileHandle).getFile().toDart),
        );
      }
    }
  }

  await walk(await window.navigator.storage.getDirectory().toDart, 'opfs:');
  for (final info in (await window.indexedDB.databases().toDart).toDart) {
    final open = window.indexedDB.open(info.name);
    final opened = Completer<IDBDatabase>();
    open.onsuccess = (Event _) {
      opened.complete(open.result as IDBDatabase);
    }.toJS;
    final db = await opened.future;
    final stores = db.objectStoreNames;
    for (var i = 0; i < stores.length; i++) {
      final store = stores.item(i)!;
      final request = db.transaction(store.toJS).objectStore(store).getAll();
      final done = Completer<void>();
      request.onsuccess = (Event _) {
        done.complete();
      }.toJS;
      await done.future;
      final values = (request.result as JSArray).toDart;
      for (var j = 0; j < values.length; j++) {
        stored['indexeddb:${info.name}/$store/$j'] = await _bytes(values[j]);
      }
    }
    db.close();
  }
  return stored;
}

Future<Uint8List> _bytes(JSAny? value) async {
  if (value.isA<Blob>()) {
    return (await (value as Blob).arrayBuffer().toDart).toDart.asUint8List();
  }
  if (value.isA<JSArrayBuffer>()) {
    return (value as JSArrayBuffer).toDart.asUint8List();
  }
  if (value.isA<JSUint8Array>()) return (value as JSUint8Array).toDart;
  if (value.isA<JSString>()) return utf8.encode((value as JSString).toDart);
  return utf8.encode(
    (globalContext['JSON'] as JSObject)
            .callMethod<JSString?>('stringify'.toJS, value)
            ?.toDart ??
        '',
  );
}

/// A file a closing database still holds cannot be read for a moment.
Future<T> _retry<T>(Future<T> Function() read) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } catch (_) {
      if (attempt == 50) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
