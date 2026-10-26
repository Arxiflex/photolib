import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/ml.dart';
import 'package:photolib_data/photolib_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?> Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(
      mlChannel,
      handler == null
          ? null
          : (call) {
              calls.add(call);
              return handler(call);
            },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(mlChannel, null));
  }

  LocalAssetData item(String id) => _Item(id);

  setUp(calls.clear);

  test('the engine is what the platform says: ML Kit or Vision', () async {
    answer((call) async => 'mlkit');
    expect(await platformEngine(), 'mlkit');
    expect(calls.single.method, 'textSupport');
  });

  test('a build without text recognition says none: the libre flavour, or a '
      'platform that does not answer', () async {
    answer((call) async => throw PlatformException(code: 'unavailable'));
    expect(await platformEngine(), isNull);
    answer(null);
    expect(await platformEngine(), isNull);
  });

  test('an item is read by its source id, at the text size, and the answer '
      'is the platform text as it is', () async {
    answer((call) async => '<b>Lisboa</b>');
    final token = RootIsolateToken.instance!;
    expect(
      await platformRecogniser(token, photoKit: false)(item('42')),
      '<b>Lisboa</b>',
    );
    expect(
      await platformRecogniser(token, photoKit: true)(item('7')),
      '<b>Lisboa</b>',
    );
    expect([for (final c in calls) c.method], ['recognize', 'recognize']);
    expect(
      [for (final c in calls) c.arguments],
      [
        {'source': 'mediastore', 'id': '42', 'size': 1024},
        {'source': 'photokit', 'id': '7', 'size': 1024},
      ],
    );
  });
}

/// An item of which only the source's id is read.
class _Item implements LocalAssetData {
  new(this.sourceId);

  @override
  final String sourceId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
