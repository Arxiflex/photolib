// The app against a real photolibd with PostgreSQL: it adds the server, sets
// it up with the setup token, signs in with the kernel's OPAQUE, keeps the
// session across a restart, lists the admin overview and signs out when the
// console revokes its own session; between, it sets up private libraries.
// main builds photolibd (untimed): setUpAll has 12 minutes whatever @Timeout
// says, which cargo may spend waiting on locks other checkouts share.
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';

import '../support/photolibd.dart';
import '../support/pump_app.dart';

void main() {
  // Real time and real connections, for photolibd and the kernel's Argon2id.
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final binary = Photolibd.build();
  late Photolibd photolibd;
  setUpAll(() async => photolibd = await Photolibd.start(binary));
  tearDownAll(() => photolibd.stop());

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// Pumps frames until [finder] finds something, for a minute of its own
  /// waits, which a stopped process (SIGSTOP) does not run out, then until
  /// page transitions end.
  Future<void> until(WidgetTester tester, Finder finder) async {
    const step = Duration(milliseconds: 100);
    for (
      var waited = Duration.zero;
      finder.evaluate().isEmpty && waited < const Duration(minutes: 1);
      waited += step
    ) {
      await tester.pump(step);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(
      finder,
      findsWidgets,
      reason: [
        for (final text in find.byType(Text).evaluate())
          (text.widget as Text).data,
      ].join(' | '),
    );
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = text == 'Settings'
        ? find.byTooltip(text)
        : find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> fill(WidgetTester tester, Map<String, String> fields) async {
    for (final MapEntry(:key, :value) in fields.entries) {
      await tester.enterText(field(key), value);
    }
  }

  test('photolibd builds only in main, under no timeout', () {
    expect(Photolibd.build, throwsStateError);
  });

  testWidgets(
    'sets up a new photolibd, signs in, administers it and signs out when the '
    'console revokes the session',
    (tester) async {
      final store = MemoryStore();
      await pumpApp(tester, serverStore: store);
      await tap(tester, 'Settings');
      await until(tester, find.text('Add a server'));
      await tap(tester, 'Add a server');
      await until(tester, field('Addresses'));
      await fill(tester, {'Addresses': '${photolibd.url}'});
      await tap(tester, 'Connect');
      await until(tester, find.text('Set up a new server'));

      await tap(tester, 'Set up a new server');
      await until(tester, field('Setup token'));
      await fill(tester, {
        'Setup token': photolibd.setupToken,
        'Sign-in name': 'ann',
        'Name': 'Ann',
        'Email': 'ann@example.org',
        'Password': 'correct horse',
        'Password again': 'correct horse',
      });
      await tap(tester, 'Create administrator');
      await until(tester, find.text('Signed in as ann'));

      await tap(tester, 'Sign out');
      await until(tester, find.text('Email or sign-in name'));
      await fill(tester, {
        'Email or sign-in name': 'ann@example.org',
        'Password': 'correct horse',
      });
      await tap(tester, 'Sign in');
      await until(tester, find.text('Signed in as ann@example.org'));
      final account = Accounts.fromJson(jsonDecode(store.value!) as Map)
          .server!
          .account!;
      expect(account.admin, isTrue);

      // Private libraries: the kernel makes the keys and the recovery kit,
      // photolibd takes them, and counts the kit verified once words of it
      // are typed again.
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      await tap(tester, 'Private libraries');
      await until(tester, find.text('Set up'));
      final password = find.widgetWithText(TextField, 'Password');
      await tester.enterText(password, 'correct horse');
      await tap(tester, 'Set up');
      await until(tester, find.text('I wrote them down'));
      final card = find.byType(Card);
      String word(int n) => tester
          .widget<Text>(
            find
                .descendant(
                  of: find.ancestor(of: find.text('Word $n'), matching: card),
                  matching: find.byType(Text),
                )
                .last,
          )
          .data
          .toString();
      final words = [for (var n = 1; n <= 24; n++) word(n)];
      await tap(tester, 'I wrote them down');
      await until(tester, find.text('Verify'));
      for (final (i, word) in words.indexed) {
        final asked = find.widgetWithText(TextField, 'Word ${i + 1}');
        if (asked.evaluate().isNotEmpty) await tester.enterText(asked, word);
      }
      await tap(tester, 'Verify');
      await until(tester, find.text('Private uploads are on.'));
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));

      // A restart: the session comes back from the store.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, serverStore: store);
      await tap(tester, 'Settings');
      await until(tester, find.text('Theme'));
      await tester.scrollTo(find.text('Diagnostics'));
      await until(tester, find.text('Server administration'));
      await tap(tester, 'Server administration');
      await until(tester, find.text('Overview'));
      await tap(tester, 'Overview');
      await until(tester, find.text('Usage by account'));
      expect(find.text('Database backups'), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));

      await tap(tester, 'Your devices');
      await until(tester, find.textContaining('This device'));
      final ours = find.ancestor(
        of: find.textContaining('This device'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: ours, matching: find.text('Sign out')),
      );
      await until(tester, find.text('You are signed out of the server.'));
      expect(store.value, isNot(contains(account.token)));
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      // The faces section lengthens the settings: back up to the server.
      await tester.scrollUntilVisible(find.text('Signed out'), -100);
      await until(tester, find.text('Signed out'));
    },
  );
}
