import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/servers/sync.dart';
import 'package:photolib_api/photolib_api.dart'
    show GetServerInfoRequest, ServerInfoServiceApi;
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_editor/edit.dart';

/// The capability of a server that keeps edit versions (ADR-0391).
const versionsCapability = 'sync.versions.v1';

/// The server asset [item] is: its own, or the one a device item is linked to
/// by a backup; null for an item the server has no copy of.
Uint8List? serverAssetOf(ThumbnailItem item) {
  if (item.asset case final asset?) return asset;
  final path = item.uri.path;
  final id = path.startsWith('media/') ? path.substring('media/'.length) : '';
  if (item.uri.scheme.isEmpty &&
      RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(id)) {
    return uuidBytes(id);
  }
  return null;
}

/// Whether the server of [link] keeps edit versions.
Future<bool> serverKeepsVersions(Link link) async {
  final info = await ServerInfoServiceApi(link)
      .getServerInfo(null, GetServerInfoRequest());
  return info.capabilities.contains(versionsCapability);
}

/// Whether [item] is a photo only the server has (its tiles are renditions).
bool isServerOnly(ThumbnailItem item) =>
    item.uri.scheme.isEmpty && item.uri.path.startsWith('media/');

/// Whether the editor saves an edit of [item] as a version (ADR-0391): a photo
/// only the server has, for a signed-in account, whose edit goes through the
/// outbox like every other. A file on the device is edited into a copy beside
/// it (ADR-0331), whatever the server holds of it: the app shows the file.
bool canEditVersion(ThumbnailItem item, {required bool signedIn}) =>
    signedIn && !item.video && isServerOnly(item);

/// Saves [edit], made on the picture [item] shows, as a new version of its
/// server asset; returns the version's id, null when the server cannot keep
/// versions. Tests fake it.
typedef SaveVersion = Future<Uint8List?> Function(
  ThumbnailItem item,
  Edit edit,
);

/// The kernel's function for the code of the page: the keyring of the
/// platform's binding, closed with the provider.
final kernelCallProvider = FutureProvider<KernelCall>((ref) async {
  final keyring = (await loadKernel())();
  ref.onDispose(keyring.close);
  return keyring.call;
});

/// How the editor saves a version.
final saveVersionProvider = Provider<SaveVersion>(
  (ref) => (item, edit) async {
    final asset = serverAssetOf(item) ?? (throw StateError('no asset'));
    final link = ref.read(sessionProvider);
    if (link != null && !await serverKeepsVersions(link)) return null;
    final db = await ref.read(replicaProvider.future);
    final outbox = Mutations(db);
    final parent = await outbox.currentVersion(asset);
    final base = await recipeOf(db, parent);
    final recipe = edit.appendedTo(base, tool: toolName);
    final id = await outbox.addVersion(
      asset,
      recipe.writeToBuffer(),
      parent: parent,
    );
    unawaited(ref.read(syncNowProvider)());
    return id;
  },
);

/// The tool that records itself in the recipes it writes.
String get toolName =>
    'photolib (${kIsWeb ? 'web' : defaultTargetPlatform.name})';

/// The recipe of [version] in the replica, if it is an edit.
Future<r.EditRecipe?> recipeOf(Replica db, Uint8List? version) async {
  if (version == null) return null;
  final row = await (db.select(
    db.assetVersion,
  )..where((v) => v.id.equals(version))).getSingleOrNull();
  final bytes = row?.recipe;
  return bytes == null ? null : r.EditRecipe.fromBuffer(bytes);
}
