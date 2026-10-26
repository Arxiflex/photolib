import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/deletion.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_data/photolib_data.dart' hide Stack;

import '../../support/media_platform.dart';
import '../../support/pump_app.dart';
import '../../support/server_app.dart';

/// ORG-17: an album of the account's library hides from the timeline and from
/// memories by an edit that waits in the outbox, and shows as checked.
void main() {
  late Replica db;
  final trip = Uint8List(16)..[15] = 9;
  setUp(() {
    db = Replica(NativeDatabase.memory());
  });
  tearDown(() => db.close());
  setUpServerApp();

  Future<void> open(WidgetTester tester, {bool signedIn = true}) async {
    await db.customStatement(
      'INSERT INTO album (id, owner_id, title, created_at) '
      "VALUES (?, x'0102', 'Trip', 1)",
      [trip],
    );
    if (signedIn) keep(ann);
    await pumpServerApp(
      tester,
      replica: db,
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => ThumbnailPipeline(),
        ),
        mediaPlatformProvider.overrideWithValue((_) => FakePlatform()),
      ],
    );
    await tester.tapAndSettle(find.text('Collections'));
    await tester.tapAndSettle(find.text('Albums'));
    await tester.tapAndSettle(find.text('Trip'));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<List<String>> waiting() async => [
    for (final o in await db.pendingOutbox(1 << 62, 10).get())
      [
        o.entity,
        ...pb.Mutation.fromBuffer(o.mutation).edit.fields.entries
            .map((e) => '${e.key}=${e.value.boolean}'),
      ].join(' '),
  ];

  testWidgets('hiding an album from the timeline and from memories are edits '
      'of its own that show checked, and showing it again undoes each', (
    tester,
  ) async {
    await open(tester);
    await tester.tapAndSettle(find.byTooltip('Hide'));
    await tester.tapAndSettle(find.text('Hide from timeline'));
    expect(await waiting(), ['album_user_state hide_from_timeline=true']);
    await tester.tapAndSettle(find.byTooltip('Hide'));
    expect(
      tester
          .widget<CheckedPopupMenuItem<String>>(
            find.widgetWithText(
              CheckedPopupMenuItem<String>,
              'Hide from timeline',
            ),
          )
          .checked,
      isTrue,
    );
    await tester.tapAndSettle(find.text('Hide from memories'));
    await tester.tapAndSettle(find.byTooltip('Hide'));
    await tester.tapAndSettle(find.text('Hide from timeline'));
    expect(await waiting(), [
      'album_user_state hide_from_timeline=true',
      'album_user_state hide_from_memories=true',
      'album_user_state hide_from_timeline=false',
    ]);
    await unmount(tester);
  });

  testWidgets("signed out, an album is the device's alone: nothing to hide "
      'on a server', (tester) async {
    await open(tester, signedIn: false);
    expect(find.byTooltip('Hide'), findsNothing);
    await unmount(tester);
  });
}
