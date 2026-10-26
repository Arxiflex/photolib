import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/memory.dart';

void main() {
  test('reads the RAM', () {
    final total = RegExp(r'MemTotal:\s+(\d+) kB')
        .firstMatch(File('/proc/meminfo').readAsStringSync())!;
    expect(physicalMemory(), int.parse(total[1]!) * 1024);
  }, testOn: 'linux');
}
