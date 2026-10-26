import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/hdr_leaf.dart';
import 'package:photolib/ui/motion.dart';

const apple = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS});
final sdr = find.bySemanticsLabel('sdr');

typedef Call = ({String channel, MethodCall call});

/// Fakes the native side: [support] answers `photolib/hdr`, [hcpp] says whether
/// the engine enables HCPP, and every other message to the engine's
/// platform-view channels lands in the returned list.
List<Call> fakeNative(
  WidgetTester tester, {
  String? support,
  bool hcpp = false,
}) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final calls = <Call>[];
  messenger.setMockMethodCallHandler(
    const MethodChannel('photolib/hdr'),
    support == null ? null : (call) async => support,
  );
  for (final channel in [
    SystemChannels.platform_views,
    SystemChannels.platform_views_2,
  ]) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isSurfaceControlEnabled') return hcpp;
      calls.add((channel: channel.name, call: call));
      return null;
    });
  }
  return calls;
}

Future<void> pumpLeaf(
  WidgetTester tester, {
  bool show = true,
  bool force = false,
  bool reduceMotion = false,
  TransformationController? transform,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: InteractiveViewer(
          transformationController: transform,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: HdrLeaf(
            uri: Uri.file('/media/ultra-hdr.jpg'),
            show: show,
            force: force,
            sdr: Semantics(label: 'sdr', child: const SizedBox.expand()),
          ),
        ),
      ),
    ),
  );
}

Iterable<MethodCall> creates(List<Call> calls) => [
  for (final (:call, channel: _) in calls)
    if (call.method == 'create') call,
];

Map<Object?, Object?> creationParams(MethodCall create) {
  final bytes = (create.arguments as Map)['params'] as Uint8List;
  return const StandardMessageCodec().decodeMessage(ByteData.sublistView(bytes))
      as Map<Object?, Object?>;
}

Future<void> fromNative(WidgetTester tester, MethodCall create, String event) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'photolib/hdr/${(create.arguments as Map)['id']}',
      const StandardMethodCodec().encodeMethodCall(MethodCall(event)),
      (_) {},
    );

double sdrOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.ancestor(of: sdr, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

void main() {
  testWidgets('shows only the SDR frame where the platform has no HDR leaf', (
    tester,
  ) async {
    for (final support in [null, 'none']) {
      final calls = fakeNative(tester, support: support);
      await pumpLeaf(tester, force: true);
      await tester.pump(HdrLeaf.prewarm * 2);
      expect(creates(calls), isEmpty, reason: '$support');
      expect(sdrOpacity(tester), 1);
    }
  }, variant: apple);

  testWidgets('an SDR display gets the native view only when forced', (
    tester,
  ) async {
    for (final force in [false, true]) {
      final calls = fakeNative(tester, support: 'sdr');
      await pumpLeaf(tester, force: force);
      await tester.pump(HdrLeaf.prewarm);
      await tester.pump();
      expect(creates(calls), hasLength(force ? 1 : 0), reason: '$force');
      await tester.pumpWidget(const SizedBox());
    }
  }, variant: apple);

  testWidgets(
    'pre-warms the native view under the SDR frame and cross-fades once it has rendered',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final calls = fakeNative(tester, support: 'hdr');
      await pumpLeaf(tester);
      await tester.pump(HdrLeaf.prewarm - const Duration(milliseconds: 1));
      expect(creates(calls), isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      final create = creates(calls).single;
      expect((create.arguments as Map)['viewType'], 'photolib/hdr');
      expect(creationParams(create), {
        'uri': 'file:///media/ultra-hdr.jpg',
        'video': false,
      });
      await tester.pump(Motion.short);
      expect(sdrOpacity(tester), 1, reason: 'nothing native on screen yet');

      // The headroom comes up over 200 ms (docs/10 §4.6).
      await fromNative(tester, create, 'rendered');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(sdrOpacity(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 20));
      expect(sdrOpacity(tester), 0);
      expect(
        find.semantics.byLabel('sdr'),
        findsOne,
        reason: 'its label still describes the item',
      );
      semantics.dispose();
    },
    variant: apple,
  );

  testWidgets('under reduce motion the SDR frame goes at once', (tester) async {
    final calls = fakeNative(tester, support: 'hdr');
    await pumpLeaf(tester, reduceMotion: true);
    await tester.pump(HdrLeaf.prewarm);
    await tester.pump();
    await fromNative(tester, creates(calls).single, 'rendered');
    await tester.pump();
    expect(sdrOpacity(tester), 0);
  }, variant: apple);

  testWidgets('keeps the SDR frame and drops the native view when it fails', (
    tester,
  ) async {
    final calls = fakeNative(tester, support: 'hdr');
    await pumpLeaf(tester);
    await tester.pump(HdrLeaf.prewarm);
    await tester.pump();
    await fromNative(tester, creates(calls).single, 'failed');
    await tester.pumpAndSettle();

    expect(calls.map((c) => c.call.method), contains('dispose'));
    expect(find.byType(UiKitView), findsNothing);
    expect(sdrOpacity(tester), 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('creates nothing while hidden, dwells once shown, and when '
      'hidden again shows the SDR frame at once and drops the native view', (
    tester,
  ) async {
    final calls = fakeNative(tester, support: 'hdr');
    await pumpLeaf(tester, show: false);
    await tester.pump(HdrLeaf.prewarm * 2);
    expect(creates(calls), isEmpty);

    await pumpLeaf(tester);
    await tester.pump(HdrLeaf.prewarm - const Duration(milliseconds: 1));
    expect(creates(calls), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await fromNative(tester, creates(calls).single, 'rendered');
    await tester.pumpAndSettle();
    expect(sdrOpacity(tester), 0);

    await pumpLeaf(tester, show: false);
    await tester.pump();
    expect(sdrOpacity(tester), 1);
    expect(calls.map((c) => c.call.method), contains('dispose'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('creates nothing for an item left before the pre-warm delay', (
    tester,
  ) async {
    final calls = fakeNative(tester, support: 'hdr');
    await pumpLeaf(tester);
    await tester.pump(HdrLeaf.prewarm ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(HdrLeaf.prewarm * 2);

    expect(calls, isEmpty);
  }, variant: apple);

  testWidgets('gestures over the native view stay with Flutter', (
    tester,
  ) async {
    final calls = fakeNative(tester, support: 'hdr');
    final transform = TransformationController();
    await pumpLeaf(tester, transform: transform);
    await tester.pump(HdrLeaf.prewarm);
    await tester.pump();
    await fromNative(tester, creates(calls).single, 'rendered');
    await tester.pumpAndSettle();

    // The leaf takes no hits by design, so drag at its centre, not on it.
    await tester.dragFrom(
      tester.getCenter(find.byType(HdrLeaf)),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(transform.value.getTranslation().x, lessThan(-50));
  }, variant: apple);

  testWidgets('uses HCPP on Android where the engine enables it, else HC', (
    tester,
  ) async {
    for (final hcpp in [false, true]) {
      final calls = fakeNative(tester, support: 'hdr', hcpp: hcpp);
      await pumpLeaf(tester);
      await tester.pump(HdrLeaf.prewarm);
      await tester.pump();
      final create = calls.singleWhere((c) => c.call.method == 'create');
      expect(
        create.channel,
        hcpp ? 'flutter/platform_views_2' : 'flutter/platform_views',
      );
      expect((create.call.arguments as Map)['hybrid'], isTrue);
      expect(creationParams(create.call)['uri'], 'file:///media/ultra-hdr.jpg');
      await tester.pumpWidget(const SizedBox());
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
