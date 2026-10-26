import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib/features/library/timeline/ffmpeg.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart' show GetServerInfoResponse;
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../../../support/pump_app.dart' show MemoryStore;
import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final never = Tile();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('providers');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await dir.delete(recursive: true);
  });

  Future<ThumbnailPipeline> pipeline(TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    final (vault, _) = await scratchVault(
      '${dir.path}/store-${platform.name}',
      Kernel().keyring,
    );
    addTearDown(vault.lock);
    final container = ProviderContainer(
      overrides: [vaultProvider.overrideWith((ref) async => vault)],
    );
    addTearDown(container.dispose);
    final tiers = await container.read(thumbnailPipelineProvider.future);
    // Disposing closes its cache without waiting, then tearDown deletes it.
    if (tiers.cache case final DiskCache cache) addTearDown(cache.close);
    return tiers;
  }

  test('Linux decodes what Flutter refuses with libvips and keeps it in the '
      'disk cache, in the app cache directory', () async {
    final linux = await pipeline(TargetPlatform.linux);
    final cache = linux.cache! as DiskCache;
    expect(cache.dir, '${dir.path}/thumbnails');
    expect(cache.maxBytes, 1 << 30);
    expect(linux.thumbnailers, hasLength(1), reason: 'freedesktop');
    expect(
      [for (final d in linux.decoders) d.name],
      ['mpv', if (await ffmpegPosters() != null) 'ffmpeg', 'vips'],
      reason: 'posters come first from the stack that plays videos',
    );
    final file = File('${dir.path}/a.heic')
      ..writeAsBytesSync(base64.decode(heic));
    final image = await linux.load(ThumbnailItem('h', file.uri), 32, never);
    expect((image.width, image.height), (48, 32));
    await linux.idle;
    expect(linux.cache!.contains('h-32'), isTrue);
  });

  test('macOS and Windows decode files with the platform first, and keep its '
      'tiles', () async {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/thumbnails'),
      (call) async {
        if (call.method != 'load') return null;
        asked.add((call.arguments as List).first as String);
        return [
          1,
          1,
          Uint8List.fromList([9, 9, 9, 255]),
        ];
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('org.photolib/thumbnails'),
        null,
      ),
    );
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      final desktop = await pipeline(platform);
      expect(desktop.thumbnailers, isEmpty);
      final item = ThumbnailItem('$platform', Uri.file('/a.heic'));
      await desktop.load(item, 128, never);
      await desktop.idle;
      expect(desktop.cache!.contains('$platform-128'), isTrue);
    }
    expect(asked, ['file:///a.heic', 'file:///a.heic']);
  });

  test('phones take MediaStore and PhotoKit thumbnails, which the OS keeps, '
      "and keep the server's in the disk cache", () async {
    for (final phone in [TargetPlatform.android, TargetPlatform.iOS]) {
      // A cache directory each: two caches in one race (DiskCache).
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '${dir.path}/${phone.name}',
      );
      final tiers = await pipeline(phone);
      final cache = tiers.cache! as DiskCache;
      expect(
        (cache.dir, cache.maxBytes),
        ('${dir.path}/${phone.name}/thumbnails', 1 << 30),
      );
      expect(tiers.thumbnailers, hasLength(1));
      expect(tiers.decoders, isEmpty);
    }
  });

  test("a server item's tile comes from the signed-in server, once an address "
      'has answered as its instance, with the session; none while signed '
      'out or at another instance', () async {
    // Real connections, which the test binding answers with 400s.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final asked = <String>[];
    final photolibd = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(photolibd.close);
    photolibd.listen((request) async {
      asked.add(
        '${request.uri} ${request.headers.value('authorization')} '
        '${request.headers.value('if-none-match')}',
      );
      final response = request.response;
      if (request.uri.path.endsWith('/GetServerInfo')) {
        response.headers.contentType = ContentType('application', 'proto');
        response.add(GetServerInfoResponse(epoch: 'ours.0').writeToBuffer());
      } else {
        response.headers.set('etag', '"01"');
        response.add(img.encodeJpg(img.Image(width: 384, height: 256)));
      }
      await response.close();
    });
    final (vault, _) = await scratchVault(
      '${dir.path}/store-server',
      Kernel().keyring,
    );
    addTearDown(vault.lock);
    Future<ThumbnailPipeline> signedIn(String instance, {Account? account}) {
      final container = ProviderContainer(
        overrides: [
          vaultProvider.overrideWith((ref) async => vault),
          networkChangesProvider.overrideWithValue(const Stream.empty()),
          serverStoreProvider.overrideWithValue(
            MemoryStore(
              jsonEncode(
                SavedServer(
                  endpoints: [Uri.parse('http://127.0.0.1:${photolibd.port}')],
                  instance: instance,
                  account: account,
                ).toJson(),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      return container
          .read(accountsProvider.future)
          .then((_) => container.read(thumbnailPipelineProvider.future));
    }

    final item = ThumbnailItem.remote(Uint8List(16));
    const ann = Account(name: 'ann', token: 't0k', deviceId: 'd');
    for (final (instance, account) in [('ours', null), ('theirs', ann)]) {
      await expectLater(
        (await signedIn(instance, account: account)).load(item, 256, never),
        throwsA(isA<Pending>()),
      );
    }
    final pipeline = await signedIn('ours', account: ann);
    final image = await pipeline.load(item, 256, never);
    await pipeline.idle;
    expect((image.width, image.height), (384, 256));
    const info = '/photolib.api.v1.ServerInfoService/GetServerInfo null null';
    const media = '/media/00000000-0000-0000-0000-000000000000/thumb_s';
    // Each start with a session also renews it (ADR-0052), alongside the tile
    // and with an instance check of its own: the other instance gets no
    // renewal, and ours answers it with no message, so the session stays.
    expect(
      asked,
      unorderedEquals([
        ...List.filled(4, info),
        '/photolib.api.v1.AuthService/RotateSession Bearer t0k null',
        '$media Bearer t0k null',
      ]),
    );
  });
}
