import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/commands.dart';

import '../support/pump_app.dart';

const ctrl = [LogicalKeyboardKey.controlLeft];

void main() {
  late List<String> ran;

  Future<void> pumpCommands(
    WidgetTester tester, {
    Widget? child,
    List<(String, ShortcutActivator)> more = const [],
  }) async {
    ran = [];
    Command command(String label, ShortcutActivator? shortcut) =>
        Command(label, () => ran.add(label), shortcut: shortcut);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Commands(
            commands: [
              command(
                'Favourite',
                const SingleActivator(LogicalKeyboardKey.keyF),
              ),
              command('Search', const CharacterActivator('/')),
              command('Undo', primary(LogicalKeyboardKey.keyZ)),
              command('Redo', primary(LogicalKeyboardKey.keyZ, shift: true)),
              command('Settings', null),
              for (final (label, shortcut) in more) command(label, shortcut),
            ],
            child: child ?? const SizedBox(),
          ),
        ),
      ),
    );
  }

  testWidgets('a command runs on its shortcut', (tester) async {
    await pumpCommands(tester);
    expect(await tester.pressKey(LogicalKeyboardKey.keyF), isTrue);
    await tester.pressKey(LogicalKeyboardKey.slash, character: '/');
    await tester.pressKey(LogicalKeyboardKey.keyZ, modifiers: ctrl);
    expect(ran, ['Favourite', 'Search', 'Undo']);
  });

  testWidgets('two commands on one key are a mistake, as only the first '
      'would run', (tester) async {
    await pumpCommands(
      tester,
      more: [('Fisheye', const SingleActivator(LogicalKeyboardKey.keyF))],
    );
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('while typing, only shortcuts with Ctrl, Cmd or Alt run', (
    tester,
  ) async {
    await pumpCommands(tester, child: const TextField());
    await tester.tapAndSettle(find.byType(TextField));
    expect(await tester.pressKey(LogicalKeyboardKey.keyF), isFalse);
    await tester.pressKey(LogicalKeyboardKey.slash, character: '/');
    await tester.pressKey(LogicalKeyboardKey.keyZ, modifiers: ctrl);
    expect(ran, ['Undo']);
  });

  testWidgets('? shows every shortcut', (tester) async {
    await pumpCommands(tester);
    await tester.pressKey(
      LogicalKeyboardKey.slash,
      modifiers: [LogicalKeyboardKey.shiftLeft],
      character: '?',
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    for (final (label, keys) in [
      ('Keyboard shortcuts', '?'),
      ('Favourite', 'F'),
      ('Search', '/'),
      ('Undo', 'Ctrl+Z'),
      ('Redo', 'Ctrl+Shift+Z'),
      ('Command palette', 'Ctrl+K'),
    ]) {
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, label),
          matching: find.text(keys),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('the primary modifier is Cmd on Apple systems', (tester) async {
    await pumpCommands(tester);
    await tester.pressKey(
      LogicalKeyboardKey.keyZ,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    final apple = {
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);
    expect(ran, apple ? ['Undo'] : isEmpty);

    final context = tester.element(find.byType(Commands));
    expect(
      keysLabel(primary(LogicalKeyboardKey.keyK), AppLocalizations.of(context)),
      apple ? 'Cmd+K' : 'Ctrl+K',
    );
  }, variant: TargetPlatformVariant.all());

  group('the command palette', () {
    Future<void> openPalette(WidgetTester tester) =>
        tester.pressKey(LogicalKeyboardKey.keyK, modifiers: ctrl);

    testWidgets('opens on Ctrl+K and lists every command', (tester) async {
      await pumpCommands(tester);
      await openPalette(tester);
      for (final label in [
        'Favourite',
        'Search',
        'Undo',
        'Redo',
        'Settings',
        'Keyboard shortcuts',
      ]) {
        expect(find.widgetWithText(ListTile, label), findsOneWidget);
      }
    });

    testWidgets('filters as you type and runs the first match on Enter', (
      tester,
    ) async {
      await pumpCommands(tester);
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'DO');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Undo'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Redo'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Search'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(ran, ['Undo']);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('stays open when Enter matches nothing', (tester) async {
      await pumpCommands(tester);
      await openPalette(tester);
      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(ran, isEmpty);
    });

    testWidgets('runs a tapped command', (tester) async {
      await pumpCommands(tester);
      await openPalette(tester);
      await tester.tapAndSettle(find.text('Settings'));
      expect(ran, ['Settings']);
    });
  });
}
