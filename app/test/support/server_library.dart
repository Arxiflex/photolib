import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show scratchVault;
import 'package:photolib_harness/photolib_harness.dart' show thawed;
import 'package:photolib_kernel/photolib_kernel.dart' show Kernel;

import 'photolibd.dart';
import 'pump_app.dart' show MemoryStore;

/// An app signed in to a [Photolibd] whose administrator has an external
/// library of photos (docs/admin/configuration.md), which the server reads
/// and renders, and its [items].
class ServerLibrary {
  new _(this.photolibd, this.app, this.items, this._dir, this._vault);

  final Photolibd photolibd;

  /// The app's providers, signed in.
  final ProviderContainer app;

  /// Its assets as the timeline has them, synced into a replica once each has
  /// its thumbnails, newest first.
  final List<ThumbnailItem> items;
  final Directory _dir;
  final Vault _vault;

  /// [count] photos of 1024 × 768, served by [binary] ([Photolibd.build]).
  static Future<ServerLibrary> start(String binary, int count) async {
    final dir = await Directory.systemTemp.createTemp('photolib-library-');
    final photos = Directory('${dir.path}/photos')..createSync();
    await Isolate.run(() {
      for (var i = 0; i < count; i++) {
        final photo = img.Image(width: 1024, height: 768);
        for (final p in photo) {
          p.setRgb((p.x + 7 * i) % 256, (p.y * i) % 256, 255 - i % 256);
        }
        File('${photos.path}/$i.jpg').writeAsBytesSync(img.encodeJpg(photo));
      }
    });
    final photolibd = await Photolibd.start(
      binary,
      workers: true,
      externalRoot: dir.path,
    );
    final probe = Server(NetworkConfig(endpoints: [photolibd.url]));
    final instance = (await probe.selectEndpoint()).epoch.split('.').first;
    probe.close();
    final (vault, _) = await scratchVault(
      '${dir.path}/store',
      Kernel().keyring,
    );
    final app = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(MemoryStore()),
        networkChangesProvider.overrideWithValue(const Stream.empty()),
        vaultProvider.overrideWith((ref) async => vault),
      ],
    );
    final server = app.read(accountsProvider.notifier);
    await app.read(accountsProvider.future);
    await server.add(
      SavedServer(endpoints: [photolibd.url], instance: instance),
    );
    await server.setUp(
      photolibd.setupToken,
      User(handle: 'ann', displayName: 'Ann', email: 'ann@example.org'),
      'correct horse battery',
    );
    final session = app.read(sessionProvider)!;
    final me = (await UserServiceApi(
      session,
    ).listUsers(null, ListUsersRequest())).users.single.userId;
    await AdminServiceApi(session).createExternalLibrary(
      null,
      CreateExternalLibraryRequest(
        ownerUserId: me,
        name: 'Photos',
        root: photos.path,
      ),
    );
    final saved = app.read(serverProvider).requireValue!;
    final items = await _synced(
      Server(saved.config, instance: instance),
      count,
    );
    return ServerLibrary._(photolibd, app, items, dir, vault);
  }

  /// The library's assets, once each has its thumbnails, newest first.
  static Future<List<ThumbnailItem>> _synced(Server server, int count) async {
    final db = Replica(NativeDatabase.memory());
    try {
      // Five minutes of its own waits, which a stop (SIGSTOP) does not run
      // out; a sync whose call a stop timed out runs again.
      for (var waited = 0; ; waited++) {
        await thawed(() => SyncEngine(db, server).run());
        final assets = await (db.select(
          db.asset,
        )..orderBy([(a) => OrderingTerm.desc(a.takenUtc)])).get();
        final files = await db.select(db.assetFile).get();
        final items = [
          for (final a in assets)
            ThumbnailItem.remote(
              a.id,
              version: a.currentVersionId,
              video: a.mediaKind == 'video',
              hash: a.thumbhash,
              renditions: {
                for (final f in files)
                  if (listEquals(f.assetId, a.id) &&
                      f.state == 'present' &&
                      f.role.startsWith('thumb_'))
                    f.role: ?f.contentHash,
              },
            ),
        ];
        if (items.length == count &&
            items.every((i) => i.renditions!.length == 2)) {
          return items;
        }
        if (waited == 300) {
          throw StateError('${items.length} of $count assets rendered');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      server.close();
      await db.close();
    }
  }

  Future<void> stop() async {
    app.dispose();
    await _vault.lock();
    await photolibd.stop();
    await _dir.delete(recursive: true);
  }
}
