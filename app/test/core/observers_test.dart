import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/observers.dart';
import 'package:photolib_harness/photolib_harness.dart';

void main() {
  test('a provider that fails is logged with its error and stack, '
      'once a try, while Riverpod retries it', () async {
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);
    final vault = FutureProvider<int>((ref) async {
      await Future<void>.delayed(Duration.zero);
      throw Exception('no keyring');
    });
    final hard = FutureProvider<int>((ref) => throw StateError('broken'));
    final container = ProviderContainer(observers: const [StateLog()]);
    addTearDown(container.dispose);
    container
      ..listen(vault, (_, _) {})
      ..listen(hard, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final failed = heard.where((r) => r.message == 'provider failed').toList();
    expect(failed.map((r) => '${r.error}'), [
      'Bad state: broken',
      'Exception: no keyring',
    ]);
    for (final r in failed) {
      expect(r.logger, 'photolib.state');
      expect(r.level, LogLevel.error);
      expect(r.stackTrace, isNotNull);
    }
    expect(failed.last.fields, containsPair('retrying', true));
    expect(takeProblems(), [
      contains('Bad state: broken'),
      contains('Exception: no keyring'),
    ]);
  });
}
