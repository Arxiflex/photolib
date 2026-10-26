import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/servers.dart';

void main() {
  test('a phone with less than 4 GiB of memory is constrained', () {
    String meminfo(int kib) => 'MemTotal:       $kib kB\nMemFree: 1 kB\n';
    expect(constrained(meminfo(3 << 20)), isTrue);
    expect(constrained(meminfo(8 << 20)), isFalse);
    expect(constrained(null), isFalse, reason: 'no /proc/meminfo, as on iOS');
  });
}
