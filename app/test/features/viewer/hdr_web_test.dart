// The web app's HDR stills in Chrome: `flutter test --platform chrome [--wasm]
// test/features/viewer/hdr_web_test.dart` (the `web` part of tools/check.sh).
// On a display with HDR headroom (`(dynamic-range: high)`) a folder's JPEG or
// AVIF shows through an <img> of its own bytes, which the browser decodes with
// its gain map, under the SDR frame until it has loaded (docs/10 §4.5,
// ADR-0390); on any other display nothing is made.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/hdr_display_web.dart';
import 'package:photolib/features/viewer/hdr_leaf.dart';
import 'package:photolib_data/browser.dart';
import 'package:web/web.dart' as web;

final Finder sdr = find.bySemanticsLabel('sdr');

List<web.HTMLImageElement> images() => List.of(debugHdrImages);

/// Keeps a folder `Hdr` of the file [bytes] as `a.jpg` in this browser's
/// private file system, as the folder picker keeps a folder
/// (browser_folders.dart).
Future<void> keepFolder(Uint8List bytes, String name) async {
  final opfs = await web.window.navigator.storage.getDirectory().toDart;
  final folder = await opfs
      .getDirectoryHandle(
        'Hdr',
        web.FileSystemGetDirectoryOptions(create: true),
      )
      .toDart;
  final file = await folder
      .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
      .toDart;
  final writable = await file.createWritable().toDart;
  await writable.write(bytes.toJS).toDart;
  await writable.close().toDart;
  Future<JSAny?> done(web.IDBRequest request) {
    final result = Completer<JSAny?>();
    request
      ..onsuccess = ((web.Event _) => result.complete(request.result)).toJS
      ..onerror = ((web.Event _) => result.completeError('$request')).toJS;
    return result.future;
  }

  final open = web.window.indexedDB.open('photolib/folders', 1);
  void upgrade(web.Event _) =>
      (open.result! as web.IDBDatabase).createObjectStore('roots');
  open.onupgradeneeded = upgrade.toJS;
  final db = (await done(open))! as web.IDBDatabase;
  await done(
    db
        .transaction('roots'.toJS, 'readwrite')
        .objectStore('roots')
        .put(folder, 'Hdr'.toJS),
  );
  db.close();
}

Future<void> pumpLeaf(
  WidgetTester tester,
  String name, {
  bool show = true,
  bool fresh = true,
}) async {
  // The tree outlives a test: start from nothing, or the last leaf's state
  // stays.
  if (fresh) await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: HdrLeaf(
        uri: Uri(scheme: 'folder', pathSegments: ['Hdr', name]),
        show: show,
        sdr: Semantics(label: 'sdr', child: const SizedBox.expand()),
      ),
    ),
  );
}

/// Pumps frames between short waits in real time until [done]: the browser's
/// files and images answer in real time, and the widget's continuations run in
/// the test's fake zone, which only a pump runs.
Future<void> until(
  WidgetTester tester,
  bool Function() done, [
  String what = 'it',
]) async {
  for (var n = 0; !done(); n++) {
    if (n > 1500) fail('$what: not done after 15 s');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

/// Pumps for a second of real time, for what has to happen to have happened.
Future<void> settle(WidgetTester tester) async {
  for (var n = 0; n < 100; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

double sdrOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.ancestor(of: sdr, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

void main() {
  final jpeg = Uint8List.fromList(
    img.encodeJpg(
      img.Image(width: 8, height: 8)..clear(img.ColorRgb8(255, 0, 0)),
    ),
  );
  setUpAll(() async {
    await keepFolder(jpeg, 'a.jpg');
    await keepFolder(Uint8List.fromList([1, 2, 3]), 'broken.jpg');
    // The browser's folders open their database once, for good: not in a
    // test's fake zone.
    await browserFile('Hdr', 'a.jpg');
  });
  tearDown(() => debugBrowserShowsHdr = null);

  testWidgets('a display without HDR headroom shows the SDR frame alone', (
    tester,
  ) async {
    debugBrowserShowsHdr = false;
    await pumpLeaf(tester, 'a.jpg');
    await tester.pump(HdrLeaf.prewarm * 2);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(images(), isEmpty);
    expect(sdrOpacity(tester), 1);
  });

  testWidgets(
    'a display with HDR headroom shows the file in an <img> of its own bytes, '
    'and the SDR frame goes once it has loaded',
    (tester) async {
      debugBrowserShowsHdr = true;
      await pumpLeaf(tester, 'a.jpg');
      await tester.pump(HdrLeaf.prewarm - const Duration(milliseconds: 1));
      expect(images(), isEmpty, reason: 'nothing before the dwell');
      await tester.pump(const Duration(milliseconds: 1));
      await until(tester, () => images().isNotEmpty, 'the <img>');
      await until(tester, () => images().first.complete, 'its load');
      final shown = images().single;
      expect(shown.src, startsWith('blob:'));
      expect(
        shown.style.pointerEvents,
        'none',
        reason: 'gestures stay with Flutter',
      );
      expect(shown.naturalWidth, 8);
      final bytes = await tester.runAsync(() async {
        final response = await web.window.fetch(shown.src.toJS).toDart;
        return (await response.arrayBuffer().toDart).toDart.asUint8List();
      });
      expect(bytes, jpeg);
      await tester.pump(const Duration(milliseconds: 250));
      expect(sdrOpacity(tester), 0, reason: 'the HDR picture is on screen');
    },
  );

  testWidgets('hiding the leaf takes the <img> away and shows the SDR frame', (
    tester,
  ) async {
    debugBrowserShowsHdr = true;
    await pumpLeaf(tester, 'a.jpg');
    await tester.pump(HdrLeaf.prewarm - const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await until(tester, () => images().isNotEmpty, 'the <img>');
    await pumpLeaf(tester, 'a.jpg', show: false, fresh: false);
    await tester.pump();
    expect(images(), isEmpty);
    expect(sdrOpacity(tester), 1);
  });

  testWidgets(
    'a file the browser cannot show leaves the SDR frame, the page without it',
    (tester) async {
      debugBrowserShowsHdr = true;
      await pumpLeaf(tester, 'broken.jpg');
      await tester.pump(HdrLeaf.prewarm);
      // The <img> may come and go between two pumps: wait out the load.
      await settle(tester);
      expect(images(), isEmpty);
      expect(sdrOpacity(tester), 1);
    },
  );

  testWidgets('a file that is gone leaves the SDR frame', (tester) async {
    debugBrowserShowsHdr = true;
    await pumpLeaf(tester, 'gone.jpg');
    await tester.pump(HdrLeaf.prewarm);
    await settle(tester);
    expect(images(), isEmpty);
    expect(sdrOpacity(tester), 1);
  });
}
