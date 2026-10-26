// Runs the kernel's conformance vectors (kernel/testvectors) through the C ABI, as tests/vectors.rs does in Rust, and
// measures it against its budgets (bench.dart). With --dart-define=vectors=<dir> it runs the vectors in that
// directory through the kernel the build hook bundles (tools/kernel/probe.sh); otherwise through kernel/ffi built in
// release mode, as apps get it, from this checkout.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:test/test.dart';

import 'bench.dart';
import 'cases.dart';

const vectors = String.fromEnvironment(
  'vectors',
  defaultValue: '../../../kernel/testvectors/',
);

Keys keys(Kernel kernel) {
  final keyring = kernel.keyring();
  return (
    call: keyring.call,
    open: (method, request) {
      final stream = keyring.openStream(method, request);
      return (push: stream.push, finish: stream.finish);
    },
    close: keyring.close,
  );
}

void main() {
  final kernel = const bool.hasEnvironment('vectors')
      ? Kernel()
      : Kernel.open(buildKernel());
  final files =
      Directory.fromUri(Directory.current.uri.resolve(vectors))
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('there are vectors', () => expect(files, isNotEmpty));
  test('a panic fails only its call', () {
    final keyring = kernel.keyring();
    expect(kernel.call(panicProbe, Uint8List(0)), kernelPanic);
    expect(keyring.call(panicProbe, Uint8List(0)), kernelPanic);
    expect(keyring.openStream(panicProbe, Uint8List(0)).finish(), kernelPanic);
    expect(keyring.call(3, Uint8List(0)), [0x0a, 0x00]);
    keyring.close();
  });
  test('the kernel meets its budgets', () {
    pinToFastestCores(pid);
    final results = benchmark(
      keys(kernel),
      {
        for (final file in files)
          file.uri.pathSegments.last: file.readAsStringSync(),
      },
      web: false,
      clock: threadClock(),
    );
    print(jsonEncode({'target': '${Abi.current()}', ...results}));
  }, tags: 'timing');
  for (final file in files) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    group(file.uri.pathSegments.last, () {
      for (final c in (json['cases'] as List).cast<Map<String, dynamic>>()) {
        test(
          c['name'],
          () => expect(run(keys(kernel), c, json), equals(expected(c))),
        );
      }
    });
  }
}
