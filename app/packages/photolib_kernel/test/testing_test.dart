@TestOn('vm')
library;

import 'package:photolib_kernel/testing.dart';
import 'package:test/test.dart';

void main() {
  test('the kernel is built as a suite loads, never in a test, whose timeout '
      'cargo may outlast on a loaded machine', () {
    expect(
      buildKernel,
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('main')),
      ),
    );
  });
}
