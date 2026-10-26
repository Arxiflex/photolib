// The VM side of web_test.dart: the browser test runner bundles no shaders, so this compiles them for the web as
// `flutter build web` does, and builds the kernel's WebAssembly module (tools/kernel/wasm.sh), into test/assets,
// which the test server serves (git-ignored).
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final engine = Directory(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/engine',
  );
  final impellerc = engine
      .listSync()
      .map((dir) => File('${dir.path}/impellerc'))
      .firstWhere((file) => file.existsSync());
  Directory('test/assets/shaders').createSync(recursive: true);
  final spirv = Directory.systemTemp.createTempSync('photolib-editor-');
  for (final shader in Directory(
    'shaders',
  ).listSync().where((f) => f.path.endsWith('.frag'))) {
    final name = shader.uri.pathSegments.last;
    await run(impellerc.path, [
      '--sksl',
      '--iplr',
      '--json',
      '--sl=test/assets/shaders/$name',
      '--spirv=${spirv.path}/$name.spirv',
      '--input=${shader.path}',
      '--input-type=frag',
      '--include=shaders',
      '--include=${impellerc.parent.path}/shader_lib',
    ]);
  }
  spirv.deleteSync(recursive: true);
  await run('bash', ['../../../tools/kernel/wasm.sh', 'test/assets/kernel']);
  channel.sink.add('assets/kernel/photolib_kernel_wasm.js');
}

Future<void> run(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$command ${arguments.join(' ')} failed:\n${result.stderr}',
    );
  }
}
