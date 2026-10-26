// The build hook (hook/build.dart) bundles ONNX Runtime's library for the
// target from the official archive that tools/ml/artefacts.json pins, but only
// after the archive's SHA-256 matches the pin. The archives here are fakes with
// the pinned names and layout: each listed library holds its pin's and its
// path's name.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

final Map<String, Map<String, Object?>> pins = (jsonDecode(
  File('../../../tools/ml/artefacts.json').readAsStringSync(),
) as Map).cast<String, Map<String, Object?>>();
late Directory dir;

String basename(String pin) => (pins[pin]!['url']! as String).split('/').last;

List<String> files(String pin) => (pins[pin]!['files']! as List).cast();

Matcher fails(String message) =>
    throwsA(predicate((e) => '$e'.contains(message)));

Uint8List le(int value, int bytes) => (ByteData(
  4,
)..setUint32(0, value, Endian.little)).buffer.asUint8List(0, bytes);

/// A gzip-compressed ustar archive of [files], each after a directory entry.
List<int> tgz(Map<String, String> files) {
  final tar = BytesBuilder();
  void entry(String name, String type, List<int> content) {
    final size = content.length.toRadixString(8).padLeft(11, '0');
    tar
      ..add(
        Uint8List(512)
          ..setAll(0, utf8.encode(name))
          ..setAll(124, ascii.encode(size))
          ..setAll(156, ascii.encode(type))
          ..setAll(257, ascii.encode('ustar\x0000')),
      )
      ..add(content)
      ..add(Uint8List(-content.length % 512));
  }

  for (final MapEntry(key: name, value: content) in files.entries) {
    entry('${File(name).parent.path}/', '5', []);
    entry(name, '0', utf8.encode(content));
  }
  return gzip.encode((tar..add(Uint8List(1024))).takeBytes());
}

/// A zip archive of [files], deflated. The hook trusts the archive's pinned
/// SHA-256, not CRCs, so they are left 0.
List<int> zip(Map<String, String> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  for (final MapEntry(key: name, value: content) in files.entries) {
    final data = utf8.encode(content);
    final packed = ZLibEncoder(raw: true).convert(data);
    final path = utf8.encode(name);
    // From the version needed to extract to the extra field's length: the
    // local and the central headers share these.
    final common = (ByteData(26)
      ..setUint16(4, 8, Endian.little)
      ..setUint32(14, packed.length, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint16(22, path.length, Endian.little));
    central
      ..add(le(0x02014b50, 4))
      ..add(Uint8List(2))
      ..add(common.buffer.asUint8List())
      ..add(Uint8List(10))
      ..add(le(out.length, 4))
      ..add(path);
    out
      ..add(le(0x04034b50, 4))
      ..add(common.buffer.asUint8List())
      ..add(path)
      ..add(packed);
  }
  final (start, size) = (out.length, central.length);
  return (out
        ..add(central.takeBytes())
        ..add(le(0x06054b50, 4))
        ..add(Uint8List(4))
        ..add(le(files.length, 2))
        ..add(le(files.length, 2))
        ..add(le(size, 4))
        ..add(le(start, 4))
        ..add(Uint8List(2)))
      .takeBytes();
}

/// The fake archive of [pin], the macOS one with `./` before each path as the real one has.
List<int> archive(String pin) {
  final prefix = pin == 'ort-macos-arm64' ? './' : '';
  final content = {for (final file in files(pin)) '$prefix$file': '$pin $file'};
  return basename(pin).endsWith('.tgz') ? tgz(content) : zip(content);
}

/// Writes artefacts.json into [dir] with each ONNX Runtime pin's digest that
/// of its fake archive (or of [pinned]) and its URL at [base], and writes the
/// fake archives into [into].
void artefacts({
  String base = 'https://example.org/',
  Directory? into,
  Map<String, List<int>> pinned = const {},
}) {
  final fakes = {
    for (final pin in pins.keys.where(
      (pin) => pin.startsWith('ort-') && pin != 'ort-ios',
    ))
      pin: archive(pin),
  };
  for (final MapEntry(key: pin, value: bytes) in fakes.entries) {
    if (into != null) {
      File('${into.path}/${basename(pin)}').writeAsBytesSync(bytes);
    }
  }
  File('${dir.path}/artefacts.json').writeAsStringSync(
    jsonEncode({
      for (final MapEntry(key: pin, value: bytes) in fakes.entries)
        pin: {
          ...pins[pin]!,
          'url': '$base${basename(pin)}',
          'sha256': sha256.convert(pinned[pin] ?? bytes).toString(),
        },
    }),
  );
}

/// Runs the hook for a target; returns the code assets it declares, each with
/// its file's content, and the files it depends on. The runtime directory is
/// [dir]'s `runtime/` unless [userDefines] say otherwise.
Future<(List<(CodeAsset, String)>, List<Uri>)> runHook({
  OS os = OS.linux,
  Architecture arch = Architecture.x64,
  IOSSdk sdk = IOSSdk.iPhoneOS,
  Map<String, Object?>? userDefines,
}) async {
  late (List<(CodeAsset, String)>, List<Uri>) result;
  await testCodeBuildHook(
    mainMethod: (args) => build(args, hook.bundle),
    targetOS: os,
    targetArchitecture: arch,
    targetIOSSdk: sdk,
    userDefines: PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: userDefines ?? {'runtime': 'runtime/'},
        basePath: dir.uri,
      ),
    ),
    check: (input, output) => result = (
      [
        for (final asset in output.assets.code)
          (asset, File.fromUri(asset.file!).readAsStringSync()),
      ],
      output.dependencies,
    ),
  );
  return result;
}

/// A loopback server of the fake archives (or of [served]) that counts
/// requests.
Future<(String, List<String>)> serve({Map<String, List<int>>? served}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  final requests = <String>[];
  server.listen((request) async {
    final name = request.uri.pathSegments.last;
    requests.add(name);
    final pin = pins.keys.firstWhere((pin) => basename(pin) == name);
    request.response.add(served?[pin] ?? archive(pin));
    await request.response.close();
  });
  return ('http://127.0.0.1:${server.port}/ort/', requests);
}

void main() {
  final defaultArtefacts = hook.artefacts;
  late Directory runtime;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('onnxruntime');
    runtime = Directory('${dir.path}/runtime')..createSync();
    hook.artefacts = dir.uri.resolve('artefacts.json');
  });
  tearDown(() {
    hook.artefacts = defaultArtefacts;
    dir.deleteSync(recursive: true);
  });

  test('bundles the verified library as the package asset', () async {
    artefacts(into: runtime);
    final (assets, dependencies) = await runHook();
    final (asset, content) = assets.single;
    expect(asset.id, 'package:photolib_ml/onnxruntime.dart');
    expect(asset.linkMode, isA<DynamicLoadingBundled>());
    expect(asset.file!.pathSegments.last, 'libonnxruntime.so');
    expect(content, 'ort-linux-x64 ${files('ort-linux-x64').single}');
    expect(
      dependencies,
      containsAll([
        dir.uri.resolve('artefacts.json'),
        runtime.uri.resolve(basename('ort-linux-x64')),
      ]),
    );
  });

  test('takes the library of each target from its archive', () async {
    artefacts(into: runtime);
    final targets = {
      (OS.linux, Architecture.x64): ('ort-linux-x64', null),
      (OS.linux, Architecture.arm64): ('ort-linux-arm64', null),
      (OS.macOS, Architecture.arm64): ('ort-macos-arm64', null),
      (OS.windows, Architecture.x64): ('ort-windows-x64', null),
      (OS.android, Architecture.arm64): (
        'ort-android',
        'jni/arm64-v8a/libonnxruntime.so',
      ),
      (OS.android, Architecture.arm): (
        'ort-android',
        'jni/armeabi-v7a/libonnxruntime.so',
      ),
      (OS.android, Architecture.x64): (
        'ort-android',
        'jni/x86_64/libonnxruntime.so',
      ),
    };
    for (final MapEntry(key: (os, arch), value: (pin, file))
        in targets.entries) {
      final (assets, _) = await runHook(os: os, arch: arch);
      final (asset, content) = assets.single;
      expect(content, '$pin ${file ?? files(pin).single}', reason: '$os $arch');
      expect(asset.file!.pathSegments.last, os.dylibFileName('onnxruntime'));
    }
  });

  test(
    'bundles nothing on iOS, which links the static xcframework, '
    'nor on Intel Macs, for which ONNX Runtime 1.31.0 has no build',
    () async {
      artefacts(into: runtime);
      for (final (os, arch, sdk) in [
        (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS),
        (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator),
        (OS.iOS, Architecture.x64, IOSSdk.iPhoneSimulator),
        (OS.macOS, Architecture.x64, IOSSdk.iPhoneOS),
      ]) {
        final (assets, _) = await runHook(os: os, arch: arch, sdk: sdk);
        expect(assets, isEmpty, reason: '$os $arch $sdk');
      }
    },
  );

  test('fails when the archive does not match its pin', () async {
    final tampered = tgz({files('ort-linux-x64').single: 'tampered'});
    artefacts(into: runtime, pinned: {'ort-linux-x64': tampered});
    final name = basename('ort-linux-x64');
    final actual = sha256.convert(archive('ort-linux-x64'));
    await expectLater(
      runHook(),
      fails('$name: SHA-256 $actual, expected ${sha256.convert(tampered)}'),
    );
  });

  test('fails for a target without ONNX Runtime', () async {
    artefacts(into: runtime);
    await expectLater(
      runHook(arch: Architecture.riscv64),
      fails('no ONNX Runtime for linux-riscv64'),
    );
  });

  test('reads the pins of tools/ml/artefacts.json by default', () async {
    hook.artefacts = defaultArtefacts;
    File('${runtime.path}/${basename('ort-linux-x64')}')
        .writeAsBytesSync(archive('ort-linux-x64'));
    await expectLater(
      runHook(),
      fails('expected ${pins['ort-linux-x64']!['sha256']}'),
    );
  });

  test('downloads a missing archive into the runtime directory once, '
      'verified', () async {
    final (base, requests) = await serve();
    artefacts(base: base);
    final (assets, _) = await runHook();
    expect(assets.single.$2, startsWith('ort-linux-x64 '));
    expect(requests, [basename('ort-linux-x64')]);
    expect(
      File('${runtime.path}/${basename('ort-linux-x64')}').readAsBytesSync(),
      archive('ort-linux-x64'),
    );

    await runHook();
    expect(requests, hasLength(1));
  });

  test('keeps no download that does not match its pin', () async {
    final (base, _) = await serve(
      served: {
        'ort-linux-x64': tgz({'tampered': ''}),
      },
    );
    artefacts(base: base);
    await expectLater(runHook(), fails('SHA-256'));
    expect(runtime.listSync(), isEmpty);
  });

  test('downloads into its own output without a runtime directory', () async {
    final (base, requests) = await serve();
    artefacts(base: base);
    final (assets, _) = await runHook(
      os: OS.android,
      arch: Architecture.arm64,
      userDefines: {},
    );
    expect(assets.single.$2, 'ort-android jni/arm64-v8a/libonnxruntime.so');
    expect(requests, [basename('ort-android')]);
  });

  test('gives up on a server that stops answering', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final silent = <Socket>[];
    server.listen(silent.add);
    addTearDown(() async {
      for (final socket in silent) {
        socket.destroy();
      }
      await server.close();
    });
    hook.downloadTimeout = const Duration(milliseconds: 200);
    addTearDown(() => hook.downloadTimeout = const Duration(seconds: 60));
    artefacts(base: 'http://127.0.0.1:${server.port}/');
    await expectLater(runHook(), fails('no answer within 0:00:00.200000'));
  });

  test('bundles nothing when told not to', () async {
    final (assets, _) = await runHook(userDefines: {'bundle': false});
    expect(assets, isEmpty);
  });

  test('bundles nothing when no code assets are built', () async {
    await testBuildHook(
      mainMethod: (args) => build(args, hook.bundle),
      extensions: [],
      check: (input, output) => expect(output.assets.encodedAssets, isEmpty),
    );
  });
}
