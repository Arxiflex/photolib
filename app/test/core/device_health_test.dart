import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/device_health.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background work needs 20% battery or a charger, no saver and no '
      'heat; with charging only, a charger', () {
    const fine = {
      'battery': 20,
      'charging': false,
      'powerSaving': false,
      'thermal': 2, // moderate
      'temperature': 42.0,
    };
    expect(backgroundHold(fine), isNull);
    expect(backgroundHold({...fine, 'battery': 19}), Hold.battery);
    expect(backgroundHold({...fine, 'battery': 5, 'charging': true}), isNull);
    expect(backgroundHold({...fine, 'powerSaving': true}), Hold.powerSaving);
    expect(backgroundHold({...fine, 'thermal': 3}), Hold.heat);
    expect(backgroundHold({...fine, 'temperature': 42.1}), Hold.heat);
    expect(backgroundHold(fine, chargingOnly: true), Hold.charger);
    expect(
      backgroundHold({...fine, 'charging': true}, chargingOnly: true),
      isNull,
    );
    // Heat holds it back first: a charger warms the device further.
    expect(
      backgroundHold({
        ...fine,
        'thermal': 4,
        'battery': 3,
        'powerSaving': true,
      }, chargingOnly: true),
      Hold.heat,
    );
  });

  test('the user may move the battery threshold and allow power saving; '
      'never heat', () {
    const fine = {
      'battery': 35,
      'charging': false,
      'powerSaving': true,
      'thermal': 0,
      'temperature': 30.0,
    };
    expect(backgroundHold(fine, allowSaver: true), isNull);
    expect(backgroundHold(fine, allowSaver: true, battery: 40), Hold.battery);
    expect(backgroundHold(fine, battery: 10), Hold.powerSaving);
    expect(
      backgroundHold({...fine, 'thermal': 3}, allowSaver: true, battery: 0),
      Hold.heat,
    );
  });

  test('lite mode below 4 GB of RAM; downloads wait for an unmetered '
      'network unless allowed', () {
    // A 4 GB phone reports a little less, its kernel's share.
    expect(liteMode({'memory': 3800000000}), isFalse);
    expect(liteMode({'memory': 2900000000}), isTrue);
    expect(liteMode({}), isFalse);
    expect(meteredHold({'metered': true}), isTrue);
    expect(meteredHold({'metered': true}, allowMetered: true), isFalse);
    expect(meteredHold({'metered': false}), isFalse);
    expect(meteredHold({}), isFalse);
  });

  testWidgets(
    'iOS and macOS are asked too',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        deviceHealthChannel,
        (call) async => {'battery': 50, 'thermal': 2},
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          deviceHealthChannel,
          null,
        ),
      );
      final reported = <Map<Object?, Object?>>[];
      final timer = watchDeviceHealth(reported.add)!;
      await tester.pump();
      expect(reported, [
        {'battery': 50, 'thermal': 2},
      ]);
      timer.cancel();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('Android is asked at once and every minute', (tester) async {
    var battery = 80;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      deviceHealthChannel,
      (call) async => {
        'battery': battery,
        'charging': false,
        'powerSaving': false,
        'thermal': 0,
        'temperature': 30.0,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        deviceHealthChannel,
        null,
      ),
    );
    final reported = <Hold?>[];

    final timer = watchDeviceHealth((s) => reported.add(backgroundHold(s)))!;
    await tester.pump();
    expect(reported, [null]);
    battery = 10;
    await tester.pump(const Duration(minutes: 1));
    expect(reported, [null, Hold.battery]);
    timer.cancel();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('an engine without the channel reports nothing', (tester) async {
    final reported = <Object>[];
    final timer = watchDeviceHealth(reported.add)!;
    await tester.pump();
    expect(reported, isEmpty);
    timer.cancel();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'elsewhere nothing is asked: the device always allows it',
    (tester) async => expect(watchDeviceHealth((_) => fail('asked')), isNull),
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
