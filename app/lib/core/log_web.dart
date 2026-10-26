import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:photolib/core/logging.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;
import 'package:web/web.dart' as web;

/// The log of a browser in IndexedDB's database [name], so that it survives
/// reloads: the newest [capacity] records as JSON lines (ADR-0115). Erasing the
/// store deletes it with the other `photolib/` databases. With a [seal], as in
/// release builds, each record is a PLB envelope in `sealed`, and the
/// plaintext records an earlier build kept go.
class BrowserLog implements LogStore {
  /// The log in database [name].
  new({this.name = 'photolib/log', this.capacity = 20000, this.seal});

  /// The IndexedDB database.
  final String name;

  /// How many records are kept.
  final int capacity;

  /// What seals the records at rest, if anything.
  final LogSeal? seal;
  final _waiting = <String>[];
  Future<void> _writes = Future.value();
  Future<web.IDBDatabase>? _opened;

  /// Complete once every record added so far is stored.
  Future<void> get flushed => _writes;

  String get _kept => seal == null ? 'records' : 'sealed';

  @override
  void add(LogRecord record) {
    _waiting.add(record.toJson());
    if (_waiting.length > 1) return;
    _writes = _writes.then((_) => _write()).catchError((Object _) {});
  }

  @override
  Future<List<String>> lines() async {
    await flushed;
    final all = (await _database())
        .transaction(_kept.toJS)
        .objectStore(_kept)
        .getAll();
    final seal = this.seal;
    if (seal == null) {
      return [
        for (final line in (await _done<JSArray<JSString>>(all)).toDart)
          line.toDart,
      ];
    }
    return [
      for (final envelope in (await _done<JSArray<JSUint8Array>>(all)).toDart)
        // Sealed under keys the store no longer has, as before a crypto-erase.
        ?await seal
            .unseal(envelope.toDart)
            .then<String?>(utf8.decode)
            .onError<KernelError>((_, _) => null),
    ];
  }

  /// Closes the database, as a reload would.
  void close() => _opened?.then((db) => db.close());

  // Every request in one go: a transaction ends once nothing waits on it.
  Future<void> _write() async {
    final batch = [..._waiting];
    _waiting.clear();
    final seal = this.seal;
    final values = <JSAny>[
      for (final line in batch)
        if (seal == null)
          line.toJS
        else
          (await seal.seal(utf8.encode(line))).toJS,
    ];
    final transaction = (await _database()).transaction(
      [
        for (final store in {'records', _kept}) store.toJS,
      ].toJS,
      'readwrite',
    );
    // No plaintext at rest in a release build (ADR-0057).
    if (seal != null) transaction.objectStore('records').clear();
    final store = transaction.objectStore(_kept);
    final last = [for (final value in values) store.add(value)].last;
    // Keys count up, so the newest record's tells which are too old.
    last.onsuccess = ((web.Event _) {
      final key = (last.result as JSNumber?)?.toDartInt ?? 0;
      if (key > capacity) {
        store.delete(web.IDBKeyRange.upperBound((key - capacity).toJS));
      }
    }).toJS;
    final done = Completer<void>();
    transaction
      ..oncomplete = ((web.Event _) => done.complete()).toJS
      ..onabort = ((web.Event _) => done.completeError('aborted')).toJS;
    await done.future;
  }

  Future<web.IDBDatabase> _database() => _opened ??= () async {
    // Version 2 adds the sealed records.
    final open = web.window.indexedDB.open(name, 2);
    open.onupgradeneeded = ((web.Event _) {
      final db = open.result as web.IDBDatabase?;
      for (final store in ['records', 'sealed']) {
        if (db != null && !db.objectStoreNames.contains(store)) {
          db.createObjectStore(
            store,
            web.IDBObjectStoreParameters(autoIncrement: true),
          );
        }
      }
    }).toJS;
    final db = await _done<web.IDBDatabase>(open);
    // Erasing the store waits until every connection has closed.
    db.onversionchange = ((web.Event _) {
      db.close();
      _opened = null;
    }).toJS;
    return db;
  }();
}

Future<T> _done<T extends JSAny?>(web.IDBRequest request) {
  final done = Completer<T>();
  request
    ..onsuccess = ((web.Event _) => done.complete(request.result as T)).toJS
    ..onerror = ((web.Event _) => done.completeError(
      request.error ?? 'IndexedDB failed',
    )).toJS;
  return done.future;
}

/// The app's log store, IndexedDB's `photolib/log`.
LogStore openLogStore({LogSeal? seal}) => BrowserLog(seal: seal);

/// The browser, by its user agent.
Map<String, Object?> platformInfo() => {
  'os': 'web',
  'userAgent': web.window.navigator.userAgent,
  'processors': web.window.navigator.hardwareConcurrency,
  'locale': web.window.navigator.language,
};

String? _group;

/// Shows [record] in the browser's console at its level, in a group of its
/// logger's records.
void printLog(LogRecord record) {
  final console = web.console;
  if (record.logger != _group) {
    if (_group != null) console.groupEnd();
    console.group(record.logger.toJS);
    _group = record.logger;
  }
  final json = jsonDecode(record.toJson()) as Map<String, Object?>;
  console.callMethodVarArgs(
    (record.level == LogLevel.warning ? 'warn' : record.level.name).toJS,
    [
      record.message.toJS,
      {
        ...?json['fields'] as Map?,
        'error': ?json['error'],
        'stackTrace': ?json['stackTrace'],
      }.jsify(),
    ],
  );
}

/// Logs what only the browser sees: script errors, unhandled rejections,
/// Content-Security-Policy violations and the service workers' lifecycle.
void watchPlatform() {
  const log = Logger('photolib.web');
  final window = web.window;
  log.info(
    'browser',
    fields: {
      'crossOriginIsolated': window.crossOriginIsolated,
      'imageDecoder': window.has('ImageDecoder'),
      'fileSystemAccess': window.has('showDirectoryPicker'),
    },
  );
  window
    ..addEventListener(
      'error',
      ((web.ErrorEvent e) => log.error(
        'script error',
        fields: {'source': e.filename, 'line': e.lineno, 'column': e.colno},
        error: e.message,
      )).toJS,
    )
    ..addEventListener(
      'unhandledrejection',
      ((web.PromiseRejectionEvent e) => log.error(
        'unhandled rejection',
        error: '${e.reason.dartify()}',
      )).toJS,
    );
  web.document.addEventListener(
    'securitypolicyviolation',
    ((web.SecurityPolicyViolationEvent e) => log.error(
      'Content-Security-Policy violation',
      fields: {
        'directive': e.effectiveDirective,
        'blocked': e.blockedURI,
        'source': e.sourceFile,
        'line': e.lineNumber,
        'disposition': e.disposition,
      },
    )).toJS,
  );
  if (!window.navigator.has('serviceWorker')) return;
  final workers = window.navigator.serviceWorker;
  workers.addEventListener(
    'controllerchange',
    ((web.Event _) => log.info(
      'service worker took control',
      fields: {'script': workers.controller?.scriptURL},
    )).toJS,
  );
  unawaited(
    workers.getRegistrations().toDart.then((registrations) {
      for (final registration in registrations.toDart) {
        void watch(web.ServiceWorker? worker) {
          if (worker == null) return;
          void state() => log.info(
            'service worker',
            fields: {'script': worker.scriptURL, 'state': worker.state},
          );
          state();
          worker.onstatechange = ((web.Event _) => state()).toJS;
        }

        watch(registration.active);
        registration.onupdatefound = ((web.Event _) => watch(
          registration.installing,
        )).toJS;
      }
    }),
  );
}
