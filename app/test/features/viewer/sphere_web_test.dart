// The web app's 360° videos at their golden frames in Chrome: `flutter test
// --platform chrome [--wasm] test/features/viewer/sphere_web_test.dart` (the
// `web` part of tools/check.sh). Each corpus twin plays from an object URL
// through BrowserPlayers, as a folder's file does, and the panorama shader
// draws its <video> element's frames.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/viewer/animated.dart';
import 'package:photolib/features/viewer/motion_web.dart';
import 'package:photolib/features/viewer/mpv_web.dart';
import 'package:photolib/features/viewer/sphere_frame.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import '../../support/sphere_goldens.dart';
import '../../support/sphere_twins.dart';

Future<Uint8List> rgba(ui.Image image) async =>
    (await image.toByteData())?.buffer.asUint8List() ?? Uint8List(0);

void main() {
  late List<Object?> twins;
  setUpAll(() async {
    MpvPlayers.register();
    // The VM side asks for the golden filter of each kind of twin it makes.
    final channel = spawnHybridUri('sphere_web_assets.dart');
    await for (final message in channel.stream) {
      if (message case {
        'cube': final bool cube,
        'stereo': final String? stereo,
        'crop': final String? crop,
      }) {
        channel.sink.add(goldenFilter(cube: cube, stereo: stereo, crop: crop));
      } else {
        twins = message! as List<Object?>;
        break;
      }
    }
  });

  test("a folder video's object URL lasts as long as its player", () async {
    final player = BlobPlayer(web.Blob(<JSAny>[].toJS));
    Future<web.Response> fetch() =>
        web.window.fetch(player.dataSource.toJS).toDart;
    expect((await fetch()).ok, isTrue);
    await player.dispose();
    await expectLater(fetch(), throwsA(anything), reason: 'revoked');
  });

  test("a browser folder's animated GIF plays, read from its folder", () async {
    final gif = img.encodeGif(
      img.Image(width: 4, height: 4)
        ..clear(img.ColorRgb8(255, 0, 0))
        ..addFrame(img.Image(width: 4, height: 4)),
    );
    final opfs = await web.window.navigator.storage.getDirectory().toDart;
    final folder = await opfs
        .getDirectoryHandle(
          'animated',
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    final file = await folder
        .getFileHandle('a.gif', web.FileSystemGetFileOptions(create: true))
        .toDart;
    final writable = await file.createWritable().toDart;
    await writable.write(gif.toJS).toDart;
    await writable.close().toDart;
    // Kept by its name, as the folder picker keeps it (browser_folders.dart).
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
          .put(folder, 'Animated'.toJS),
    );
    db.close();
    final codec = await animationOf(
      ThumbnailItem(
        'a',
        Uri(scheme: 'folder', pathSegments: ['Animated', 'a.gif']),
      ),
    );
    expect(codec?.frameCount, 2);
    codec?.dispose();
  });

  test('Safari, which asks the user for the motion sensors, is asked; '
      'other browsers are not', () async {
    final event = globalContext['DeviceMotionEvent']! as JSObject;
    expect(await motionPermission(), isTrue);
    for (final (answer, allowed) in [('denied', false), ('granted', true)]) {
      event['requestPermission'] = () {
        return Future.value(answer.toJS).toJS;
      }.toJS;
      expect(await motionPermission(), allowed, reason: answer);
    }
    event.delete('requestPermission'.toJS);
  });

  testWidgets('every corpus 360° video plays projected from its <video> '
      'element, at its golden frame within the tolerance', (tester) async {
    expect(twins, hasLength(6));
    final differences = <String, Object>{};
    for (final t in twins.cast<Map<Object?, Object?>>()) {
      final sphere = sphereOf(
        cube: t['cube']! as bool,
        stereo: t['stereo'] as String?,
        crop: t['crop'] as String?,
      );
      final twin = base64.decode(t['twin']! as String);
      final url = web.URL.createObjectURL(
        web.Blob([twin.toJS].toJS, web.BlobPropertyBag(type: 'video/mp4')),
      );
      final player = VideoPlayerController.networkUrl(Uri.parse(url));
      final view = ValueNotifier(goldenViewOf(sphere));
      final shown = GlobalKey();
      await tester.runAsync(player.initialize);
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: AppLocalizations.localizationsDelegates,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: shown,
                child: SizedBox.fromSize(
                  size: goldenSize,
                  child: SphereVideo(
                    player: player,
                    poster: null,
                    sphere: sphere,
                    view: view,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => player.seekTo(goldenAt));
      // Until the element has presented the frame and the shader drawn it.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      final boundary =
          shown.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final image = await tester.runAsync(
        () async => await boundary?.toImage(),
      );
      final golden = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          base64.decode(t['golden']! as String),
        );
        return (await codec.getNextFrame()).image;
      });
      differences[t['path']! as String] = image == null || golden == null
          ? 'not shown'
          : frameDifference(
              (await tester.runAsync(() => rgba(image)))!,
              (await tester.runAsync(() => rgba(golden)))!,
            );
      await tester.pumpWidget(const SizedBox());
      view.dispose();
      await tester.runAsync(player.dispose);
      web.URL.revokeObjectURL(url);
    }
    expect(
      differences.values.every((d) => d is double && d <= goldenTolerance),
      isTrue,
      reason: '$differences',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
