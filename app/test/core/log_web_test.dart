@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/log_web.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;
import 'package:photolib_harness/photolib_harness.dart';
import 'package:web/web.dart' as web;

void main() {
  LogRecord record(int n) => LogRecord(
    time: DateTime.utc(2026),
    level: LogLevel.info,
    logger: 'photolib.test',
    message: 'record $n',
  );

  Future<List<String>> messages(BrowserLog log) async => [
    for (final line in await log.lines()) LogRecord.fromJson(line).message,
  ];

  test('the browser keeps the newest records across a reload', () async {
    final name = 'photolib/log-test-${DateTime.now().microsecondsSinceEpoch}';
    final page = BrowserLog(name: name, capacity: 5);
    for (var n = 0; n < 8; n++) {
      page.add(record(n));
    }
    await page.flushed;
    page.close();
    // A reloaded page has nothing in memory: only IndexedDB holds the records.
    final reloaded = BrowserLog(name: name, capacity: 5);
    expect(await messages(reloaded), [for (var n = 3; n < 8; n++) 'record $n']);
    reloaded.add(record(8));
    expect(await messages(reloaded), [for (var n = 4; n < 9; n++) 'record $n']);
    reloaded.close();
  });

  test('a release build keeps each record an envelope, and deletes the '
      'plaintext records of an earlier build (ADR-0115)', () async {
    final name = 'photolib/log-test-${DateTime.now().microsecondsSinceEpoch}';
    // As builds before sealing left it: version 1, plaintext records only.
    final v1 = web.window.indexedDB.open(name, 1);
    v1.onupgradeneeded = ((web.Event _) {
      (v1.result! as web.IDBDatabase)
          .createObjectStore(
            'records',
            web.IDBObjectStoreParameters(autoIncrement: true),
          )
          .add(record(0).toJson().toJS);
    }).toJS;
    final created = Completer<void>();
    v1.onsuccess = ((web.Event _) {
      (v1.result! as web.IDBDatabase).close();
      created.complete();
    }).toJS;
    await created.future;
    final debug = BrowserLog(name: name);
    expect(await messages(debug), ['record 0']);
    debug.close();
    final sealed = <Uint8List>[];
    final opened = <Uint8List>[];
    LogSeal seal(int key) => (
      seal: (bytes) async {
        sealed.add(Uint8List.fromList([key, for (final b in bytes) b ^ key]));
        return sealed.last;
      },
      unseal: (envelope) async {
        opened.add(envelope);
        // As the vault refuses an envelope of another key.
        if (envelope.first != key) throw KernelError(3, 'commitment_mismatch');
        return Uint8List.fromList([for (final b in envelope.skip(1)) b ^ key]);
      },
    );
    final page = BrowserLog(name: name, capacity: 5, seal: seal(1));
    for (var n = 1; n < 8; n++) {
      page.add(record(n));
    }
    await page.flushed;
    page.close();
    final reloaded = BrowserLog(name: name, capacity: 5, seal: seal(1));
    expect(await messages(reloaded), [for (var n = 3; n < 8; n++) 'record $n']);
    expect(opened, sealed.sublist(2));
    reloaded.close();
    final plain = BrowserLog(name: name);
    expect(await messages(plain), isEmpty);
    plain.close();
    final erased = BrowserLog(name: name, capacity: 5, seal: seal(2))
      ..add(record(8));
    expect(await messages(erased), ['record 8']);
    erased.close();
  });

  test('the console shows each record at its level, grouped by logger', () {
    final console = web.console as JSObject;
    final calls = <String>[];
    final saved = {
      for (final m in ['group', 'groupEnd', 'info', 'warn'])
        m: console.getProperty<JSAny?>(m.toJS),
    };
    for (final m in saved.keys) {
      console.setProperty(
        m.toJS,
        (([JSAny? a, JSAny? b]) => calls.add(
          '$m ${a.dartify() ?? ''} ${b.dartify() ?? ''}'.trim(),
        )).toJS,
      );
    }
    try {
      printLog(record(1));
      printLog(
        LogRecord(
          time: DateTime.utc(2026),
          level: LogLevel.warning,
          logger: 'photolib.other',
          message: 'slow',
          fields: {'decoder': 'vips'},
        ),
      );
    } finally {
      saved.forEach((m, f) => console.setProperty(m.toJS, f));
    }
    expect(calls, [
      'group photolib.test',
      'info record 1 {}',
      'groupEnd',
      'group photolib.other',
      'warn slow {decoder: vips}',
    ]);
  });

  test('script errors, unhandled rejections and CSP violations are logged', () {
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);
    watchPlatform();
    web.window.dispatchEvent(
      web.ErrorEvent(
        'error',
        web.ErrorEventInit(message: 'boom', filename: 'a.js', lineno: 3),
      ),
    );
    final rejected = web.PromiseRejectionEvent(
      'unhandledrejection',
      web.PromiseRejectionEventInit(
        promise: JSPromise(((JSFunction _, JSFunction _) {}).toJS),
        reason: 'nope'.toJS,
      ),
    );
    web.window.dispatchEvent(rejected);
    web.document.dispatchEvent(
      web.SecurityPolicyViolationEvent(
        'securitypolicyviolation',
        web.SecurityPolicyViolationEventInit(
          effectiveDirective: 'connect-src',
          blockedURI: 'https://elsewhere.example',
          disposition: 'enforce',
        ),
      ),
    );
    final browser = heard.where((r) => r.logger == 'photolib.web').toList();
    expect(browser.map((r) => r.message), [
      'browser',
      'script error',
      'unhandled rejection',
      'Content-Security-Policy violation',
    ]);
    expect(browser[1].error, 'boom');
    expect(browser[2].error, 'nope');
    expect(browser[3].fields['directive'], 'connect-src');
    expect(
      takeProblems(),
      unorderedEquals([
        contains('Uncaught error in the page: boom'),
        contains('Unhandled rejection in the page: nope'),
        contains('"message":"script error"'),
        contains('"message":"unhandled rejection"'),
        contains('"message":"Content-Security-Policy violation"'),
      ]),
    );
  });
}
