// Bundles ONNX Runtime's library (ADR-0050) for the build target from the
// official archive that tools/ml/artefacts.json pins, after checking the
// archive's SHA-256 against the pin. The archive is read from the directory
// that `hooks.user_defines.photolib_ml.runtime` names, else from the hook's
// shared output, and downloaded there when missing.
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
    // A BuildError's message is the first line Flutter prints when the hook
    // fails.
    throw BuildError(message: '$e');
  }
});

/// tools/ml/artefacts.json, relative to the package's root; tests point it
/// at their own.
Uri artefacts = Uri.parse('../../../tools/ml/artefacts.json');

/// Each target's pin, and where its library's path starts in an archive that
/// holds one per ABI (Android's AAR).
const _pins = {
  'linux-x64': ('ort-linux-x64', ''),
  'linux-arm64': ('ort-linux-arm64', ''),
  'macos-arm64': ('ort-macos-arm64', ''),
  'windows-x64': ('ort-windows-x64', ''),
  'android-arm64': ('ort-android', 'jni/arm64-v8a/'),
  'android-arm': ('ort-android', 'jni/armeabi-v7a/'),
  'android-x64': ('ort-android', 'jni/x86_64/'),
};

Future<void> bundle(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets || input.userDefines['bundle'] == false) {
    return;
  }
  final os = input.config.code.targetOS;
  final target = '${os.name}-${input.config.code.targetArchitecture.name}';
  // iOS has only a static xcframework, linked into the app, where Dart finds
  // OrtGetApiBase in the process (ADR-0050); ONNX Runtime 1.31.0 has no build
  // for Intel Macs, which run no on-device ML.
  if (os == OS.iOS || target == 'macos-x64') return;
  final (pin, abi) =
      _pins[target] ?? (throw StateError('no ONNX Runtime for $target'));

  final manifest = input.packageRoot.resolveUri(artefacts);
  output.dependencies.add(manifest);
  final pins = jsonDecode(await File.fromUri(manifest).readAsString()) as Map;
  final {
    'url': String url,
    'sha256': String expected,
    'files': List<Object?> files,
  } = pins[pin] as Map;
  final member = files.cast<String>().singleWhere((f) => f.startsWith(abi));

  final name = url.split('/').last;
  final archive = File.fromUri(
    (input.userDefines.path('runtime') ?? input.outputDirectoryShared).resolve(
      name,
    ),
  );
  final cached = archive.existsSync();
  final bytes = cached
      ? await archive.readAsBytes()
      : await _download(Uri.parse(url));
  final digest = sha256.convert(bytes).toString();
  if (digest != expected) {
    throw StateError('$name: SHA-256 $digest, expected $expected');
  }
  if (!cached) {
    final part = File('${archive.path}.part');
    await part.create(recursive: true);
    await part.writeAsBytes(bytes);
    await part.rename(archive.path);
  }
  output.dependencies.add(archive.uri);

  final file = input.outputDirectory.resolve(os.dylibFileName('onnxruntime'));
  await File.fromUri(file).writeAsBytes(
    bytes[0] == 0x1f
        ? _untar(gzip.decode(bytes), member)
        : _unzip(bytes, member),
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'onnxruntime.dart',
      linkMode: DynamicLoadingBundled(),
      file: file,
    ),
  );
}

/// The regular file at [path] in a ustar archive.
List<int> _untar(List<int> tar, String path) {
  for (var at = 0; tar[at] != 0;) {
    String field(int start, int length) => utf8
        .decode(tar.sublist(at + start, at + start + length))
        .split('\x00')
        .first;
    final size = int.parse(field(124, 12).trim(), radix: 8);
    final type = tar[at + 156];
    if ((type == 0x30 || type == 0) &&
        field(0, 100).replaceFirst(RegExp(r'^\./'), '') == path) {
      return tar.sublist(at + 512, at + 512 + size);
    }
    at += 512 + (size + 511) ~/ 512 * 512;
  }
  throw StateError('no $path in the archive');
}

/// The file at [path] in a zip archive, found through its central directory.
List<int> _unzip(List<int> bytes, String path) {
  final zip = Uint8List.fromList(bytes);
  final data = ByteData.sublistView(zip);
  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);
  var end = zip.length - 22;
  while (u32(end) != 0x06054b50) {
    end--;
  }
  for (var (at, n) = (u32(end + 16), u16(end + 10)); n > 0; n--) {
    final length = u16(at + 28);
    if (utf8.decode(zip.sublist(at + 46, at + 46 + length)) == path) {
      final local = u32(at + 42);
      final start = local + 30 + u16(local + 26) + u16(local + 28);
      final packed = zip.sublist(start, start + u32(at + 20));
      return u16(at + 10) == 0
          ? packed
          : ZLibDecoder(raw: true).convert(packed);
    }
    at += 46 + length + u16(at + 30) + u16(at + 32);
  }
  throw StateError('no $path in the archive');
}

/// The longest wait for the server to answer or to send more of an archive;
/// tests shorten it.
Duration downloadTimeout = const Duration(seconds: 60);

Future<List<int>> _download(Uri uri) async {
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = downloadTimeout;
  try {
    final response = await (await client.getUrl(uri))
        .close()
        .timeout(downloadTimeout);
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
