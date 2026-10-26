// The build hook (hook/build.dart) bundles the prebuilt kernel library for the target, but only after its SHA-256
// matches the one prebuilt.json pins.
import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

const linux = 'linux-x64-libphotolib_kernel_ffi.so';
late Directory dir;

String digest(String content) =>
    sha256.convert(utf8.encode(content)).toString();

Matcher fails(String message) =>
    throwsA(predicate((e) => '$e'.contains(message)));

/// Writes the files into [dir] with a prebuilt.json that pins [pinned] (default: the files' own digests).
void artifacts(
  Map<String, String> files, {
  Map<String, String>? pinned,
  String? release,
}) {
  for (final MapEntry(:key, :value) in files.entries) {
    File('${dir.path}/$key').writeAsStringSync(value);
  }
  pinned ??= files.map((name, content) => MapEntry(name, digest(content)));
  File(
    '${dir.path}/prebuilt.json',
  ).writeAsStringSync(jsonEncode({'release': ?release, 'sha256': pinned}));
}

/// Runs the hook for a target; returns the code assets it declares, each with its file's content, and the files it
/// depends on.
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
        defines: userDefines ?? {'artifacts': dir.path},
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

void main() {
  setUp(() {
    dir = Directory.systemTemp.createTempSync('prebuilt');
    hook.run = (exe, args) => throw StateError('unexpected: $exe $args');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('bundles the verified library as the package asset', () async {
    artifacts({linux: 'kernel'});
    final (assets, dependencies) = await runHook();
    final (asset, content) = assets.single;
    expect(asset.id, 'package:photolib_kernel/photolib_kernel.dart');
    expect(asset.linkMode, isA<DynamicLoadingBundled>());
    expect(asset.file!.pathSegments.last, 'libphotolib_kernel_ffi.so');
    expect(content, 'kernel');
    expect(
      dependencies,
      containsAll([dir.uri.resolve('prebuilt.json'), dir.uri.resolve(linux)]),
    );
  });

  final targets =
      {
        (OS.android, Architecture.arm64, null): 'android-arm64-lib*.so',
        (OS.android, Architecture.arm, null): 'android-arm-lib*.so',
        (OS.android, Architecture.x64, null): 'android-x64-lib*.so',
        (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS): 'ios-arm64-lib*.dylib',
        (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator):
            'ios-sim-arm64-lib*.dylib',
        (OS.iOS, Architecture.x64, IOSSdk.iPhoneSimulator):
            'ios-sim-x64-lib*.dylib',
        (OS.macOS, Architecture.arm64, null): 'macos-arm64-lib*.dylib',
        (OS.macOS, Architecture.x64, null): 'macos-x64-lib*.dylib',
        (OS.windows, Architecture.x64, null): 'windows-x64-*.dll',
        (OS.linux, Architecture.x64, null): 'linux-x64-lib*.so',
        (OS.linux, Architecture.arm64, null): 'linux-arm64-lib*.so',
      }.map(
        (key, name) =>
            MapEntry(key, name.replaceAll('*', 'photolib_kernel_ffi')),
      );

  test('takes the artifact of each native target', () async {
    artifacts({for (final name in targets.values) name: name});
    for (final MapEntry(key: (os, arch, sdk), value: name) in targets.entries) {
      final (assets, _) = await runHook(
        os: os,
        arch: arch,
        sdk: sdk ?? IOSSdk.iPhoneOS,
      );
      final (asset, content) = assets.single;
      expect(content, name);
      expect(name, endsWith(asset.file!.pathSegments.last));
    }
  });

  test('fails when the library does not match its checksum', () async {
    artifacts({linux: 'tampered'}, pinned: {linux: digest('kernel')});
    await expectLater(
      runHook(),
      fails(
        '$linux: SHA-256 ${digest('tampered')}, expected ${digest('kernel')}',
      ),
    );
  });

  test(
    'builds the kernel itself when the artifacts hold no prebuilt.json',
    () async {
      final commands = <List<String>>[];
      hook.run = (exe, args) async {
        commands.add([exe, ...args]);
        artifacts({'macos-arm64-libphotolib_kernel_ffi.dylib': 'built'});
        return ProcessResult(0, 0, '', '');
      };
      final (assets, _) = await runHook(os: OS.macOS, arch: Architecture.arm64);
      expect(assets.single.$2, 'built');
      expect(commands, hasLength(1));
      expect(commands.single.first, Platform.isWindows ? 'python' : 'python3');
      expect(commands.single.sublist(1, 3), [
        endsWith('tools/kernel/build.py'),
        '--out',
      ]);
      expect(commands.single.sublist(3), [dir.path, 'macos-arm64']);
      expect(File(commands.single[1]).existsSync(), isTrue);
    },
  );

  test('builds the missing architecture of a local set, and only it', () async {
    final commands = <List<String>>[];
    hook.run = (exe, args) async {
      commands.add(args);
      artifacts({
        'macos-arm64-libphotolib_kernel_ffi.dylib': 'a',
        'macos-x64-libphotolib_kernel_ffi.dylib': 'x',
      });
      return ProcessResult(0, 0, '', '');
    };
    artifacts({'macos-arm64-libphotolib_kernel_ffi.dylib': 'a'});
    final (assets, _) = await runHook(os: OS.macOS);
    expect(assets.single.$2, 'x');
    expect(commands.single.last, 'macos-x64');
    commands.clear();
    await runHook(os: OS.macOS, arch: Architecture.arm64);
    expect(commands, isEmpty, reason: 'a pinned library is never rebuilt');
  });

  test('a failed local build fails with the command that does it', () async {
    hook.run = (exe, args) async =>
        ProcessResult(0, 1, '', 'build.py: cargo not found');
    await expectLater(
      runHook(arch: Architecture.arm64),
      fails(
        'no prebuilt kernel for linux-arm64 in ${dir.path}/prebuilt.json; '
        'building it failed (build.py: cargo not found); build it with: '
        'python3 tools/kernel/build.py --out ${dir.path} linux-arm64',
      ),
    );
  });

  test('never builds a target the pinned release is to provide', () async {
    hook.run = (exe, args) => throw StateError('must not run');
    artifacts({}, release: 'http://127.0.0.1:1/', pinned: {linux: 'x'});
    await expectLater(
      runHook(arch: Architecture.arm64),
      fails('no prebuilt kernel for linux-arm64'),
    );
  });

  test('downloads from the release and verifies the download', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var served = 'kernel';
    server.listen(
      (request) => request.response
        ..write(request.uri.path == '/kernel-v1/$linux' ? served : '')
        ..close(),
    );
    artifacts(
      {},
      release: 'http://127.0.0.1:${server.port}/kernel-v1/',
      pinned: {linux: digest('kernel')},
    );
    final (assets, _) = await runHook();
    expect(assets.single.$2, 'kernel');

    served = 'tampered';
    await expectLater(runHook(), fails('$linux: SHA-256'));
  });

  test('gives up on a release that stops answering', () async {
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
    artifacts(
      {},
      release: 'http://127.0.0.1:${server.port}/kernel-v1/',
      pinned: {linux: digest('kernel')},
    );
    await expectLater(runHook(), fails('no answer within 0:00:00.200000'));
  });

  test('reads the prebuilt.json of the package by default', () async {
    await expectLater(
      runHook(arch: Architecture.riscv64, userDefines: {}),
      fails(
        'no prebuilt kernel for linux-riscv64 in '
        '${Directory.current.path}/prebuilt.json',
      ),
    );
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
