import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/server_pages.dart';
import 'package:photolib/features/servers/server_tile.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart' show Vault;

import '../support/pump_app.dart';

void main() {
  // Signed out, so that nothing calls it.
  final kept = jsonEncode(
    SavedServer(
      endpoints: [Uri.parse('https://photos.example.org')],
      instance: 'instance-a',
    ).toJson(),
  );

  Finder tile(String text) =>
      find.descendant(of: find.byType(ServerList), matching: find.text(text));

  Future<void> settings(
    WidgetTester tester,
    MemoryStore store, {
    Future<Vault> Function()? vault,
  }) async {
    await pumpApp(tester, serverStore: store, vault: vault);
    await tester.tapAndSettle(find.byTooltip('Settings'));
  }

  testWidgets('a kept server shows as being read, never as missing, until '
      'the store answers', (tester) async {
    final answered = Completer<void>();
    await settings(tester, MemoryStore(kept, answered.future));
    expect(find.text('Add a server'), findsNothing);
    await tester.tapAndSettle(tile('Reading the server kept on this device'));
    expect(find.byType(AddServerPage), findsNothing);
    answered.complete();
    await tester.pumpAndSettle();
    expect(tile('photos.example.org'), findsOneWidget);
    expect(tile('Signed out'), findsOneWidget);
  });

  testWidgets('a kept server that cannot be read says so, and trying again '
      'reopens the store', (tester) async {
    final store = _Unreadable(kept, StateError('unreadable'));
    var opens = 0;
    await settings(
      tester,
      store,
      vault: () {
        opens++;
        return Future.error(StateError('no keyring'));
      },
    );
    expect(find.text('Add a server'), findsNothing);
    await tester.scrollTo(
      tile('The server kept on this device cannot be read'),
    );
    expect(
      tile('The server kept on this device cannot be read'),
      findsOneWidget,
    );
    store.error = null;
    await tester.scrollTo(tile('Try again'));
    await tester.tapAndSettle(tile('Try again'));
    expect(opens, 2);
    expect(tile('photos.example.org'), findsOneWidget);
  });

  testWidgets('a kept server shows as being read while a passing failure is '
      'retried', (tester) async {
    final store = _Unreadable(kept, Exception('busy'));
    await settings(tester, store);
    expect(tile('Reading the server kept on this device'), findsOneWidget);
    store.error = null;
    // Riverpod's retries wait 6.4 s at most.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(tile('photos.example.org'), findsOneWidget);
  });
}

/// A store whose reads fail with [error] while it is set.
class _Unreadable extends MemoryStore {
  new(String super.value, this.error);

  Object? error;

  @override
  Future<String?> read() => switch (error) {
    final error? => Future.error(error),
    null => super.read(),
  };
}
