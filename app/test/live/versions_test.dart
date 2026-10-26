// An edit as a version of a server photo (ADR-0391) against a real photolibd:
// the app's replica adds a crop through the outbox, the server applies it and
// follows it with the renditions and the export, and a revert in the same way
// brings the photo back.
// main builds photolibd (untimed), as photolibd_test.dart does.
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_data/photolib_data.dart';

import '../support/photolibd.dart';
import '../support/server_library.dart';

void main() {
  // Real time and real connections, for photolibd and the kernel's Argon2id.
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final binary = Photolibd.build();
  late ServerLibrary library;
  setUpAll(() async => library = await ServerLibrary.start(binary, 1));
  tearDownAll(() => library.stop());

  /// The one asset of the library, as the server has it.
  Future<Uint8List> assetId() async => Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(library.items.single.key.substring(i, i + 2), radix: 16),
  ]);

  /// The size of the picture at [role], once [ready] says it is the one wanted.
  Future<(int, int)> sizeOf(
    String role,
    bool Function(int width, int height) ready,
  ) async {
    final asset = uuidOf(await assetId());
    final media = library.app.read(mediaProvider)!;
    for (var waited = 0; ; waited++) {
      final file = await media('media/$asset/$role', const {});
      final image = file.status == 200 ? img.decodeImage(file.bytes) : null;
      if (image != null && ready(image.width, image.height)) {
        return (image.width, image.height);
      }
      if (waited == 120) {
        throw StateError('$role: ${file.status} ${image?.width}');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  test('a crop added as a version shows in the thumbnails and the export, '
      'and a revert brings the photo back', () async {
    final saved = library.app.read(serverProvider).requireValue!;
    final server = Server(saved.config, instance: saved.instance);
    final db = Replica(NativeDatabase.memory());
    addTearDown(() async {
      server.close();
      await db.close();
    });
    await SyncEngine(db, server).run();
    final asset = await assetId();
    final original = await Mutations(db).currentVersion(asset);
    expect(original, isNotNull);
    final (width, height) = await sizeOf('thumb_m', (_, _) => true);
    expect(width / height, closeTo(4 / 3, 0.02));

    final mutations = Mutations(db);
    final crop = r.EditRecipe(
      schemaVersion: 1,
      operations: [
        r.Operation(
          operationId: 'crop',
          crop: r.CropOperation(x: 0.5, y: 0, width: 0.5, height: 1),
        ),
      ],
    );
    final version = await mutations.addVersion(
      asset,
      crop.writeToBuffer(),
      label: 'Right half',
    );
    await mutations.push(server);
    expect(await db.select(db.outbox).get(), isEmpty, reason: 'all accepted');

    final (cw, ch) = await sizeOf('thumb_m', (w, h) => w < h);
    expect(cw / ch, closeTo(2 / 3, 0.02), reason: 'the thumbnail is cropped');
    final (ew, eh) = await sizeOf('edit_export', (_, _) => true);
    expect((ew, eh), (512, 768), reason: 'the export is the edited picture');

    await mutations.revert(asset, original!);
    await mutations.push(server);
    final (bw, bh) = await sizeOf('thumb_m', (w, h) => w > h);
    expect(bw / bh, closeTo(4 / 3, 0.02), reason: 'the original is back');

    await SyncEngine(db, server).run();
    expect(await mutations.currentVersion(asset), original);
    final versions = await db.select(db.assetVersion).get();
    expect(
      versions.map((v) => uuidOf(v.id)),
      containsAll([uuidOf(original), uuidOf(version)]),
      reason: 'a revert keeps every version',
    );
  });
}
