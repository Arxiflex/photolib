@TestOn('vm')
library;

import 'dart:io';

import 'package:photolib_workers/photolib_workers.dart';
import 'package:photolib_workers/src/pool.dart' show poolSize;
import 'package:test/test.dart';

import 'pool_tests.dart';
import 'tasks.dart';

void main() {
  poolTests(({size}) => WorkerPool(tasks, size: size));

  test('has cores − 1 workers, at most 4 on phones and at least 1', () {
    expect(
      [
        for (final cores in [1, 2, 16]) poolSize(cores),
      ],
      [1, 1, 15],
    );
    expect(
      [
        for (final cores in [2, 5, 8]) poolSize(cores, phone: true),
      ],
      [1, 4, 4],
    );
    expect(WorkerPool(tasks).size, poolSize(Platform.numberOfProcessors));
  });
}
