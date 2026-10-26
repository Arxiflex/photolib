import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/share_inbox.dart';

import '../support/pump_app.dart';
import '../support/real_time.dart';

void main() {
  late Directory inbox;
  setUp(() => inbox = Directory.systemTemp.createTempSync('inbox-'));
  tearDown(() => inbox.deleteSync(recursive: true));

  final saved = <List<SharedItem>>[];
  setUp(saved.clear);
  Future<void> save(List<SharedItem> items) async => saved.add(items);

  /// An entry as the share extension writes it: its files, then its manifest.
  Directory entry(String name, Map<String, String> files, {bool done = true}) {
    final dir = Directory('${inbox.path}/$name')..createSync();
    files.forEach(
      (file, _) => File('${dir.path}/$file').writeAsStringSync(file),
    );
    if (done) {
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'items': [
            for (final MapEntry(:key, :value) in files.entries)
              {'file': key, 'kind': value},
          ],
        }),
      );
    }
    return dir;
  }

  test("an entry's photos and videos are saved in one batch, then the entry "
      'goes', () async {
    final shared = entry('A', {'0.heic': 'photo', '1.mov': 'video'});

    await drainInbox(inbox, save);

    expect(saved, [
      [
        (path: '${shared.path}/0.heic', kind: 'photo'),
        (path: '${shared.path}/1.mov', kind: 'video'),
      ],
    ]);
    expect(shared.existsSync(), isFalse);
  });

  test('each entry is a batch of its own', () async {
    entry('A', {'0.jpg': 'photo'});
    entry('B', {'0.mp4': 'video'});

    await drainInbox(inbox, save);

    expect(
      saved.map((batch) => batch.single.kind),
      unorderedEquals(['photo', 'video']),
    );
    expect(inbox.listSync(), isEmpty);
  });

  test('an entry still being written waits, and goes once abandoned', () async {
    final copying = entry('A', {'0.jpg': 'photo'}, done: false);

    await drainInbox(inbox, save);
    expect(saved, isEmpty);
    expect(copying.existsSync(), isTrue);

    await drainInbox(
      inbox,
      save,
      now: DateTime.now().add(const Duration(days: 8)),
    );
    expect(saved, isEmpty);
    expect(copying.existsSync(), isFalse);
  });

  test('an entry whose save fails stays for the next try, until it '
      'expires', () async {
    final shared = entry('A', {'0.jpg': 'photo'});
    Future<void> refuse(List<SharedItem> items) async =>
        throw PlatformException(code: 'inbox', message: 'no access');

    await drainInbox(inbox, refuse);
    expect(shared.existsSync(), isTrue);

    await drainInbox(inbox, save);
    expect(saved, hasLength(1));
    expect(shared.existsSync(), isFalse);

    final again = entry('B', {'0.jpg': 'photo'});
    await drainInbox(
      inbox,
      refuse,
      now: DateTime.now().add(const Duration(days: 8)),
    );
    expect(again.existsSync(), isFalse);
  });

  test('what Photos refuses to take waits, and is counted until it '
      'expires', () async {
    entry('A', {'0.jpg': 'photo', '1.mov': 'video'});
    entry('B', {'0.jpg': 'photo'});
    entry('C', {'0.jpg': 'photo'}, done: false);
    Future<void> deny(List<SharedItem> items) async =>
        throw PlatformException(code: 'denied');
    Future<void> fail(List<SharedItem> items) async =>
        throw PlatformException(code: 'inbox', message: 'disk full');

    expect(await drainInbox(inbox, deny), 3);
    expect(inbox.listSync(), hasLength(3));
    expect(await drainInbox(inbox, fail), 0);
    expect(
      await drainInbox(
        inbox,
        deny,
        now: DateTime.now().add(const Duration(days: 8)),
      ),
      0,
    );
    expect(inbox.listSync(), isEmpty);
  });

  test('no inbox, nothing to save', () async {
    expect(await drainInbox(Directory('${inbox.path}/none'), save), 0);
    expect(saved, isEmpty);
  });

  testWidgets('the library says what waits for access to Photos, and asks '
      'for it', (tester) async {
    final calls = <String>[];
    var allowed = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/inbox'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'folder') return inbox.path;
        if (call.method == 'allow') allowed = true;
        if (call.method == 'save' && !allowed) {
          throw PlatformException(code: 'denied');
        }
        return null;
      },
    );
    Future<void> until(bool Function() done) async {
      await tester.pumpUntil(done);
      await tester.pumpAndSettle();
    }

    entry('A', {'0.jpg': 'photo', '1.mov': 'video'});
    await pumpApp(tester);
    await until(() => calls.contains('save'));
    final waiting = find.textContaining(
      '2 shared photos and videos wait until Photolib may add to your '
      'Photos library',
    );
    expect(waiting, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(MaterialBanner),
        matching: find.text('Allow access'),
      ),
    );
    await until(() => waiting.evaluate().isEmpty);
    expect(calls, containsAllInOrder(['save', 'allow', 'save']));
    expect(inbox.listSync(), isEmpty);
    expect(waiting, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on iOS the inbox drains at start, on every resume and when the '
      'Runner adds to it', (tester) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/inbox'),
      (call) async {
        if (call.method == 'folder') return inbox.path;
        calls.add(call.arguments);
        return null;
      },
    );
    final shared = entry('A', {'0.jpg': 'photo'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      container.read(shareInboxProvider);
      await realUntil(() => !shared.existsSync());
    });
    expect(calls, [
      [
        ['${shared.path}/0.jpg', 'photo'],
      ],
    ]);

    entry('B', {'0.mov': 'video'});
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await realUntil(() => inbox.listSync().isEmpty);
    });
    expect(calls.last, [
      [contains('/B/0.mov'), 'video'],
    ]);

    // Open in Photolib: the Runner adds an entry while the app runs.
    entry('C', {'0.heic': 'photo'});
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'org.photolib/inbox',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('changed'),
        ),
        (_) {},
      );
      await realUntil(() => inbox.listSync().isEmpty);
    });
    expect(calls.last, [
      [contains('/C/0.heic'), 'photo'],
    ]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
