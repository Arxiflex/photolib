import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/on_device_faces.dart' show faceNotice;
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/editor/carried.dart';
import 'package:photolib/features/editor/versions.dart'
    show kernelCallProvider, serverAssetOf;
import 'package:photolib/features/folders/items_page.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/sync.dart' show syncNowProvider;
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_api/kernel.dart' show CallResponse, Method;
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_data/photolib_data.dart'
    show LocalMlData, Mutations, Replica, halfFloatsToFloats, unpackFaces;
import 'package:photolib_data/photolib_data.dart' as photolib;
import 'package:photolib_editor/edit.dart' show KernelCall;

/// An album an item is in (docs/04 §5): one it was added to, which it can
/// leave, or a smart or tag album it matches, marked Auto, which it cannot.
@immutable
class InfoAlbum {
  /// The album [name], in the folders [path].
  const new(
    this.id,
    this.name, {
    this.path = const [],
    this.count = 0,
    this.cover,
    this.shared = false,
    this.auto = false,
    this.tag,
    this.removable = true,
  });

  /// What the facts know it by.
  final Object id;

  /// What it is called.
  final String name;

  /// The names of the album folders it is in, from the top.
  final List<String> path;

  /// How many items it holds.
  final int count;

  /// The item its cover shows, if any.
  final ThumbnailItem? cover;

  /// Whether others share it.
  final bool shared;

  /// Whether it fills itself: a smart album, or a tag album.
  final bool auto;

  /// The tag a tag album holds the items of, with those under it.
  final String? tag;

  /// Whether this account may take items out of it.
  final bool removable;
}

/// A face on an item: where, as fractions of the picture, and whose.
@immutable
class InfoFace {
  /// A face in [box], of [person] if known.
  const new(this.box, {this.name, this.person});

  /// Where it is, as fractions of the picture.
  final Rect box;

  /// Whose it is, if named.
  final String? name;

  /// The person, if known.
  final Object? person;
}

/// One version of an item (docs/11 §2.5): its [label], when and on which
/// [device] it was made and what [change]d.
@immutable
class InfoVersion {
  /// A version.
  const new(
    this.label,
    this.time, {
    this.device = '',
    this.change = '',
    this.current = false,
    this.original = false,
    this.item,
    this.id,
    this.changes = const [],
  });

  /// What the version is called.
  final String label;

  /// When it was made.
  final DateTime time;

  /// Where it was made.
  final String device;

  /// What it changed.
  final String change;

  /// Whether it shows now.
  final bool current;

  /// Whether it is the original, which Compare with original shows.
  final bool original;

  /// Its picture, as a thumbnail and to compare.
  final ThumbnailItem? item;

  /// Its id in the replica, which a revert names.
  final Uint8List? id;

  /// What it changed of the version it continues, by the kernel's names of
  /// the steps (`turn`, `flip`, `crop`, `adjust`, `lut`, `local_adjust`,
  /// `inpaint`), in their order.
  final List<String> changes;
}

/// The lens an item was taken through and its exposure: aperture as an
/// f-number, exposure in seconds, ISO and focal length in millimetres.
typedef Optics = ({
  String? lens,
  double? aperture,
  double? exposure,
  int? iso,
  double? focal,
});

/// Where the info panel finds what an item's row does not say (VIEW-43):
/// its description, faces, albums, tags and versions and whether it is
/// backed up, and what changes them. Each section reads null where this
/// install keeps no such data, and is then absent; the data arrives with
/// M3-01, M3-03, M3-04, M5-10 and M8-08, and this base reads the albums of
/// the device's own (ADR-0217) and its backups.
class InfoFacts {
  /// The facts of [db], the replica, if any; [faces] says the user agreed to
  /// find faces (ADR-0389), without which none is shown; [kernel] compares
  /// versions' recipes, and [changed] runs after an edit the user waits for,
  /// such as a revert.
  const new({this.db, this.faces = false, this.kernel, this.changed});

  /// The replica, if open.
  final Replica? db;

  /// The kernel's call, which compares recipes; none lists versions without
  /// what they changed.
  final KernelCall? kernel;

  /// Runs after an edit of the library that the user waits for.
  final Future<void> Function()? changed;

  /// Whether face recognition is on: the user agreed to the notice.
  final bool faces;

  /// Whether [retime] can change when an item was taken.
  bool get retimes => false;

  /// Says [id] was taken at [time].
  Future<void> retime(Uint8List id, DateTime time) async {}

  /// [id]'s lens and exposure, or null until extraction reads them.
  Stream<Optics>? optics(Uint8List id) => null;

  /// [id]'s description, or null where none is kept.
  Stream<String>? description(Uint8List id) => null;

  /// Keeps [text] as [id]'s description.
  Future<void> describe(Uint8List id, String text) async {}

  /// The faces on [id]: those found in it, else those carried to it from the
  /// original it is the copy of (ADR-0389), none until the user agreed.
  Stream<List<InfoFace>> facesOf(Uint8List id) => switch (db) {
    final db? when faces =>
      (db.select(db.localMl)..where(
            (m) =>
                m.localAssetId.equals(id) &
                m.model.like('faces:%') &
                m.model.like(carriedModel).not(),
          ))
          .watch()
          .asyncMap((rows) async {
            final own = _boxes(rows);
            return own.isNotEmpty ? own : _boxes(await _carried(db, id));
          }),
    _ => Stream.value(const []),
  };

  static List<InfoFace> _boxes(List<LocalMlData> rows) => [
    for (final row in rows)
      if (row.vec case final vec?)
        for (final face in unpackFaces(halfFloatsToFloats(vec)))
          InfoFace(Rect.fromLTWH(face.x, face.y, face.width, face.height)),
  ];

  static Future<List<LocalMlData>> _carried(Replica db, Uint8List id) async {
    final row = await (db.select(
      db.localAsset,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    final uri = row == null ? null : uriOf(row);
    if (uri == null) return const [];
    final carried = db.select(db.localMl)
      ..where(
        (m) =>
            m.localAssetId.equals(carryId(uri)) & m.model.equals(carriedModel),
      );
    return await carried.get();
  }

  /// Shows [face]'s person's items.
  void openPerson(BuildContext context, InfoFace face) {}

  /// Whether [id] is backed up.
  Stream<bool> backedUp(Uint8List id) => switch (db) {
    final db? => photolib.backedUp(db, id),
    null => Stream.value(false),
  };

  /// The albums [id] was added to and the smart albums it matches; the tag
  /// albums come from [tagAlbums].
  Stream<List<InfoAlbum>> albums(Uint8List id) => switch (db) {
    final db? =>
      photolib
          .itemAlbums(db, id)
          .map(
            (albums) => [
              for (final a in albums)
                InfoAlbum(
                  a.id,
                  a.title,
                  path: a.path,
                  count: a.items,
                  shared: a.shared,
                ),
            ],
          ),
    null => Stream.value(const []),
  };

  /// The tag albums, each listing its tag's items.
  Stream<List<InfoAlbum>> tagAlbums() => Stream.value(const []);

  /// Shows [album]'s items.
  void openAlbum(BuildContext context, InfoAlbum album) {
    if (album.id case final Uint8List id) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ItemsPage(ItemsSource.album(id, album.name)),
        ),
      );
    }
  }

  /// Takes [id] out of [album].
  Future<void> leave(Uint8List id, InfoAlbum album) async {
    if ((db, album.id) case (final db?, final Uint8List from)) {
      await photolib.removeFromAlbum(db, from, id);
    }
  }

  /// Puts [id] back in [album].
  Future<void> join(Uint8List id, InfoAlbum album) async {
    if ((db, album.id) case (final db?, final Uint8List to)) {
      await photolib.addToAlbum(db, to, [id]);
    }
  }

  /// [id]'s tags, as paths, or null where none are kept.
  Stream<List<String>>? tags(Uint8List id) => null;

  /// Every tag kept, as paths.
  Future<List<String>> allTags() async => const [];

  /// Tags [id] with [path], making the tags on the way that do not exist.
  Future<void> tag(Uint8List id, String path) async {}

  /// Takes the tag [path] off [id].
  Future<void> untag(Uint8List id, String path) async {}

  /// Shows the items tagged [path] or below it.
  void openTag(BuildContext context, String path) {}

  /// [id]'s versions, newest first: the versions of the server asset that
  /// [id] is, or that the device item [id] is linked to (ADR-0391); none for
  /// an item that was never edited.
  Stream<List<InfoVersion>> versions(Uint8List id) {
    final db = this.db;
    if (db == null) return Stream.value(const []);
    return photolib.watchVersions(db, id).map((rows) {
      if (!rows.any((v) => v.kind == 'edit')) return const <InfoVersion>[];
      final all = <InfoVersion>[];
      r.EditRecipe? before;
      for (final v in rows) {
        final bytes = v.recipe;
        final recipe = bytes == null ? null : r.EditRecipe.fromBuffer(bytes);
        all.add(
          InfoVersion(
            v.label,
            v.createdAt,
            original: v.kind == 'original',
            current: v.current,
            id: v.id,
            changes: switch ((kernel, recipe)) {
              (final call?, final recipe?) => changedKinds(
                call,
                before,
                recipe,
              ),
              _ => const [],
            },
          ),
        );
        before = recipe ?? before;
      }
      return all.reversed.toList();
    });
  }

  /// Makes [version] of [id] current again: an edit of the asset, which no
  /// version changes, and then the sync that sends it.
  Future<void> revert(Uint8List id, InfoVersion version) async {
    final db = this.db;
    final to = version.id;
    if (db == null || to == null) return;
    final asset = await photolib.serverAssetIdOf(db, id);
    await Mutations(db).revert(asset, to);
    await changed?.call();
  }

  /// Whether [saveCopy] saves a version as an item of its own.
  bool get savesCopies => false;

  /// Saves [version] of [id] as an item of its own.
  Future<void> saveCopy(Uint8List id, InfoVersion version) async {}
}

/// What the recipe [after] changes of [before], none being the original, by
/// the kernel's names of the steps (`turn`, `flip`, `crop`, `adjust`, `lut`,
/// `local_adjust`, `inpaint`), in their order; none for a recipe the kernel
/// refuses.
List<String> changedKinds(
  KernelCall call,
  r.EditRecipe? before,
  r.EditRecipe after,
) {
  final answer = CallResponse.fromBuffer(
    call(
      Method.METHOD_COMPARE_RECIPES.value,
      r.CompareRecipesRequest(
        before: before ?? r.EditRecipe(schemaVersion: 1),
        after: after,
      ).writeToBuffer(),
    ),
  );
  if (!answer.hasResponse()) return const [];
  final seen = <String>[];
  for (final c in r.CompareRecipesResponse.fromBuffer(
    answer.response,
  ).changes) {
    // Stored outputs and provenance come with the steps that use them.
    if (c.what == 'output' || c.what == 'provenance') continue;
    if (!seen.contains(c.what)) seen.add(c.what);
  }
  return seen;
}

/// The info panel's facts: the replica's, until a test says otherwise.
final infoFactsProvider = FutureProvider<InfoFacts>(
  (ref) async => InfoFacts(
    db: await ref.watch(replicaProvider.future),
    faces:
        ref.watch(settingsProvider.select((s) => s.faceNotice)) == faceNotice,
    kernel: await ref.watch(kernelCallProvider.future),
    changed: ref.read(syncNowProvider),
  ),
);

/// An item's versions, newest first.
final StreamProviderFamily<List<InfoVersion>, ThumbnailItem> versionsProvider =
    StreamProvider.autoDispose.family<List<InfoVersion>, ThumbnailItem>((
      ref,
      item,
    ) async* {
      final id = item.id ?? serverAssetOf(item);
      if (id == null) return;
      yield* (await ref.watch(infoFactsProvider.future)).versions(id);
    });

/// A tag path as typed, `Travel/Greece/Hydra`: its levels, trimmed, empty
/// ones dropped, joined by `/`.
String tagPath(String typed) => [
  for (final level in typed.split('/'))
    if (level.trim().isNotEmpty) level.trim(),
].join('/');

/// The tags of [all] and every tag above them that match [typed], parents
/// first: a path that starts as typed, or one with a level that contains
/// it, so that a parent's name finds what is under it.
List<String> tagSuggestions(List<String> all, String typed) {
  final query = tagPath(typed).toLowerCase();
  if (query.isEmpty) return const [];
  final paths = <String>{
    for (final tag in all)
      for (var i = 1; i <= tag.split('/').length; i++)
        tag.split('/').take(i).join('/'),
  }.toList()..sort();
  return [
    for (final path in paths)
      if (path.toLowerCase().startsWith(query) ||
          !query.contains('/') &&
              path.toLowerCase().split('/').any((l) => l.contains(query)))
        path,
  ];
}

/// The tag albums of [tagAlbums] that [tags] puts an item in: those of one
/// of its tags or a tag above one.
List<InfoAlbum> matchingTagAlbums(
  List<InfoAlbum> tagAlbums,
  List<String> tags,
) => [
  for (final album in tagAlbums)
    if (album.tag case final tag?)
      if (tags.any((t) => t == tag || t.startsWith('$tag/'))) album,
];
