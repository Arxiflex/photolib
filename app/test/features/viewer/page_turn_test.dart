import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/info_panel.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/viewer.dart';

// With the info shown, a page turn keeps the layout: the panel stays while
// the next item's row loads (photolib-design#494).
void main() {
  for (final wide in [true, false]) {
    for (final slow in [false, true]) {
      testWidgets('with the info shown on a ${wide ? 'wide' : 'compact'} '
          'window${slow ? ' and the rows slow' : ''}, a page turn by fling '
          'or key never resizes the pages, builds no other item and keeps '
          'the players', (tester) async {
        final players = FakePlayers();
        VideoPlayerPlatform.instance = players;
        // A photo at 100 beside a video, every fourth item a video; the
        // window of pages from 50.
        final position = await pumpViewer(
          tester,
          size: wide ? const Size(1000, 700) : const Size(400, 800),
          count: 200,
          at: 100,
          video: (p) => p % 4 == 1,
          rows: slow ? const Duration(seconds: 10) : Duration.zero,
          settings: const Settings(toggles: {Toggle.autoplay: true}),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
        await tester.pump();
        final pager = find.byType(PageView);
        double extent() =>
            wide ? tester.getSize(pager).width : tester.getSize(pager).height;
        final viewport = extent();
        final panel = find.byKey(const ValueKey('info'));
        VideoPlayerController? player() => tester
            .widget<VideoView>(
              find.byKey(const ValueKey('101'), skipOffstage: false),
            )
            .player;
        final playing = player();
        expect(playing, isNotNull);
        final made = [...players.uris];

        Future<void> turn(
          int to,
          Future<void> Function(void Function()) by,
        ) async {
          final moves = <int>[];
          void moved() => moves.add(position.value);
          position.addListener(moved);
          void check() {
            expect(extent(), viewport);
            expect(panel, findsOneWidget);
            // Until its row answers, a placeholder.
            expect(
              find.byType(InfoPanel),
              slow ? findsNothing : findsOneWidget,
            );
            final built = [
              for (final s in tester.widgetList<IndexedSemantics>(
                find.descendant(
                  of: pager,
                  matching: find.byType(IndexedSemantics, skipOffstage: false),
                  skipOffstage: false,
                ),
              ))
                50 + s.index,
            ];
            expect(built, everyElement(inInclusiveRange(99, 102)));
            expect(players.uris, made);
            expect(players.calls, isNot(contains(startsWith('dispose'))));
          }

          check();
          await by(check);
          for (var i = 0; tester.binding.hasScheduledFrame; i++) {
            expect(i, lessThan(100), reason: 'never rests');
            await tester.pump(const Duration(milliseconds: 16));
            check();
          }
          position.removeListener(moved);
          expect(moves, [to]);
          expect(player(), same(playing));
        }

        await turn(101, (check) async {
          final drag = await tester.startGesture(tester.getCenter(pager));
          // Within the photo's pan slop, so that the pager wins the drag.
          for (var i = 0; i < 12; i++) {
            await drag.moveBy(const Offset(-30, 0));
            await tester.pump(const Duration(milliseconds: 16));
            check();
          }
          await drag.up();
        });
        expect(players.calls, contains('play 0'));
        await turn(
          100,
          (_) => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
        );
        expect(players.calls, containsAllInOrder(['pause 0', 'seek 0 0']));
        // Every row has answered: the panel shows the item's.
        await tester.pump(const Duration(seconds: 10));
        expect(find.text('100.jpg'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(Duration.zero);
      });
    }
  }

  testWidgets("until the item's row comes, the info panel tells a screen "
      'reader that it loads', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(
      tester,
      size: const Size(400, 800),
      rows: const Duration(seconds: 10),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pump();
    final loading = find.bySemanticsLabel("Loading this item's info");
    expect(loading, findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(loading, findsNothing);
    expect(find.byType(InfoPanel), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
