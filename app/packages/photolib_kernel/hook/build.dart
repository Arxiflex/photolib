// Bundles the prebuilt kernel library (kernel/ffi) for the build target after checking its SHA-256 against the one
// prebuilt.json pins: the package's own, which points at a kernel-v* release, or the one in the directory that
// `hooks.user_defines.photolib_kernel.artifacts` names (written by tools/kernel/build.py). It never runs cargo itself;
// a named directory that lacks the target's library is filled by tools/kernel/build.py, which finds cargo on its own
// (ADR-0394), or the build fails with the command that does it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) => build(args, (input, output) async {
  try {
    await bundle(input, output);
  } catch (e) {
    // A BuildError's message is the first line Flutter prints when the hook fails.
    throw BuildError(message: '$e');
  }
});

Future<void> bundle(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets || input.userDefines['bundle'] == false) {
    return;
  }
  final code = input.config.code;
  final os = code.targetOS;
  final simulator =
      os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
  final target =
      '${os.name}${simulator ? '-sim' : ''}-${code.targetArchitecture.name}';
  final library = os.dylibFileName('photolib_kernel_ffi');
  final name = '$target-$library';

  final artifacts = input.userDefines.path('artifacts');
  final manifest =
      (artifacts == null ? input.packageRoot : Directory.fromUri(artifacts).uri)
          .resolve('prebuilt.json');
  output.dependencies.add(manifest);
  var pins = await _pins(manifest);
  if (artifacts != null &&
      pins?['release'] == null &&
      (pins?['sha256'] as Map?)?[name] == null) {
    await _buildLocally(input.packageRoot, artifacts, manifest, target);
    pins = await _pins(manifest);
  }
  final expected =
      (pins?['sha256'] as Map?)?[name] ??
      (throw StateError(
        'no prebuilt kernel for $target in ${manifest.toFilePath()}',
      ));

  final release = pins!['release'] as String?;
  final List<int> bytes;
  if (release == null) {
    final source = manifest.resolve(name);
    output.dependencies.add(source);
    bytes = await File.fromUri(source).readAsBytes();
  } else {
    bytes = await _download(Uri.parse(release).resolve(name));
  }
  final digest = sha256.convert(bytes).toString();
  if (digest != expected) {
    throw StateError('$name: SHA-256 $digest, expected $expected');
  }

  final file = input.outputDirectory.resolve(library);
  await File.fromUri(file).writeAsBytes(bytes);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'photolib_kernel.dart',
      linkMode: DynamicLoadingBundled(),
      file: file,
    ),
  );
}

/// Runs a command; tests replace it.
Future<ProcessResult> Function(String, List<String>) run = Process.run;

Future<Map<String, Object?>?> _pins(Uri manifest) async {
  final file = File.fromUri(manifest);
  return file.existsSync()
      ? jsonDecode(await file.readAsString()) as Map<String, Object?>
      : null;
}

/// Builds [target]'s library into the artifacts directory with
/// tools/kernel/build.py (which finds cargo in rustup's standard places: a
/// hook's environment is filtered) and adds it to the directory's
/// prebuilt.json. A universal macOS build asks for each architecture in turn,
/// so each is built once.
Future<void> _buildLocally(
  Uri packageRoot,
  Uri artifacts,
  Uri manifest,
  String target,
) async {
  final directory = Directory.fromUri(artifacts).path;
  final python = Platform.isWindows ? 'python' : 'python3';
  final tool = File.fromUri(
    packageRoot.resolve('../../../tools/kernel/build.py'),
  );
  String? why;
  if (!tool.existsSync()) {
    why = 'tools/kernel/build.py is not beside this package';
  } else {
    try {
      final result = await run(python, [tool.path, '--out', directory, target]);
      if (result.exitCode != 0) {
        final lines = '${result.stderr}'.trim().split('\n');
        why = lines.last.isEmpty ? 'exit ${result.exitCode}' : lines.last;
      }
    } on ProcessException catch (e) {
      why = e.message;
    }
  }
  if (why != null) {
    throw StateError(
      'no prebuilt kernel for $target in ${manifest.toFilePath()}; '
      'building it failed ($why); build it with: '
      '$python tools/kernel/build.py --out $directory $target',
    );
  }
}

/// The longest wait for the release to answer or to send more of a library; tests shorten it.
Duration downloadTimeout = const Duration(seconds: 60);

Future<List<int>> _download(Uri uri) async {
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = downloadTimeout;
  try {
    final response = await (await client.getUrl(
      uri,
    )).close().timeout(downloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return (await response
            .timeout(downloadTimeout)
            .fold(BytesBuilder(), (b, chunk) => b..add(chunk)))
        .takeBytes();
  } on TimeoutException {
    throw HttpException('no answer within $downloadTimeout', uri: uri);
  } finally {
    client.close(force: true);
  }
}
