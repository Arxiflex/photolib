import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:photolib_data/src/vault.dart';
import 'package:web/web.dart';

/// The files of the store, in this origin's IndexedDB.
StoreFiles storeFiles(String location) => _IndexedDbFiles();

/// The browser's keystore: non-extractable WebCrypto HMAC keys in IndexedDB, whose signature of a fixed label is the
/// key's 32 bytes (ADR-0057). A copy of the browser profile holds the keys only as the browser stores them.
DeviceKeystore webKeystore() => _WebKeystore();

final Future<IDBDatabase> _db = () {
  final open = window.indexedDB.open('photolib-store', 1);
  open.onupgradeneeded = (Event _) {
    final db = open.result as IDBDatabase;
    db.createObjectStore('files');
    db.createObjectStore('keys');
  }.toJS;
  return _done<IDBDatabase>(open);
}();

Future<T> _done<T extends JSAny?>(IDBRequest request) {
  final done = Completer<T>();
  request.onsuccess = (Event _) {
    done.complete(request.result as T);
  }.toJS;
  request.onerror = (Event _) {
    done.completeError(StateError('IndexedDB: ${request.error?.message}'));
  }.toJS;
  return done.future;
}

Future<T> _in<T extends JSAny?>(
  String store,
  IDBRequest Function(IDBObjectStore store) use,
) async {
  final db = await _db;
  return _done<T>(
    use(db.transaction(store.toJS, 'readwrite').objectStore(store)),
  );
}

class _IndexedDbFiles implements StoreFiles {
  @override
  Future<Uint8List?> read(String name) async =>
      (await _in<JSUint8Array?>('files', (s) => s.get(name.toJS)))?.toDart;

  @override
  Future<void> write(String name, Uint8List bytes) =>
      _in<JSAny?>('files', (s) => s.put(bytes.toJS, name.toJS));

  @override
  Future<void> delete(String name) =>
      _in<JSAny?>('files', (s) => s.delete(name.toJS));

  @override
  Future<void> deleteAll(String prefix) => _in<JSAny?>(
    'files',
    (s) => prefix.isEmpty
        ? s.clear()
        : s.delete(IDBKeyRange.bound(prefix.toJS, '$prefix\uffff'.toJS)),
  );

  @override
  Future<List<String>> list(String prefix) async => [
    for (final key in (await _in<JSArray<JSAny?>>(
      'files',
      (s) => s.getAllKeys(IDBKeyRange.bound(prefix.toJS, '$prefix\uffff'.toJS)),
    )).toDart)
      '${key.dartify()}',
  ];
}

class _WebKeystore implements DeviceKeystore {
  static final _label = utf8.encode('photolib/v1/local/keystore').toJS;

  @override
  Future<Uint8List?> read(String name) async {
    final key = await _in<CryptoKey?>('keys', (s) => s.get(name.toJS));
    if (key == null) return null;
    final signature = await window.crypto.subtle
        .sign('HMAC'.toJS, key, _label)
        .toDart;
    return (signature as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<Uint8List> create(String name) async {
    final key = await window.crypto.subtle
        .generateKey(
          {'name': 'HMAC', 'hash': 'SHA-256'}.jsify() as JSObject,
          false,
          ['sign'.toJS].toJS,
        )
        .toDart;
    await _in<JSAny?>('keys', (s) => s.put(key, name.toJS));
    return (await read(name))!;
  }

  @override
  Future<void> delete(String name) =>
      _in<JSAny?>('keys', (s) => s.delete(name.toJS));
}
