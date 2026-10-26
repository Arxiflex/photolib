import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/info_facts.dart';

/// Facts kept in memory, as M3-01, M3-03, M3-04, M5-10 and M8-08 will keep
/// them: what the panel changed is in [calls].
class FakeFacts extends InfoFacts {
  new({
    super.faces,
    this.retimes = false,
    this.people = const [],
    List<InfoAlbum> albums = const [],
    this.tagAlbumList = const [],
    List<String> tags = const [],
    this.all = const [],
    this.history = const [],
    this.text,
    this.lens,
  }) : _albums = [...albums],
       _tags = [...tags];

  @override
  final bool retimes;

  @override
  bool get savesCopies => true;

  /// The faces on the item.
  final List<InfoFace> people;

  /// The tag albums kept.
  final List<InfoAlbum> tagAlbumList;

  /// The item's versions.
  final List<InfoVersion> history;

  /// The item's description, if one can be kept.
  final String? text;

  /// The item's lens and exposure, if read.
  final Optics? lens;

  final List<InfoAlbum> _albums;
  final List<String> _tags;

  /// Every tag kept.
  final List<String> all;
  final calls = <String>[];
  final _changed = StreamController<void>.broadcast();

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changed.stream) {
      yield read();
    }
  }

  @override
  Stream<String>? description(Uint8List id) =>
      text == null ? null : Stream.value(text!);

  @override
  Stream<Optics>? optics(Uint8List id) =>
      lens == null ? null : Stream.value(lens!);

  @override
  Future<void> describe(Uint8List id, String text) async =>
      calls.add('describe $text');

  @override
  Future<void> retime(Uint8List id, DateTime time) async =>
      calls.add('retime $time');

  @override
  Stream<List<InfoFace>> facesOf(Uint8List id) => Stream.value(people);

  @override
  void openPerson(BuildContext context, InfoFace face) =>
      calls.add('person ${face.name}');

  @override
  Stream<bool> backedUp(Uint8List id) => Stream.value(true);

  @override
  Stream<List<InfoAlbum>> albums(Uint8List id) => _watch(() => [..._albums]);

  @override
  Stream<List<InfoAlbum>> tagAlbums() => Stream.value(tagAlbumList);

  @override
  void openAlbum(BuildContext context, InfoAlbum album) =>
      calls.add('album ${album.name}');

  @override
  Future<void> leave(Uint8List id, InfoAlbum album) async {
    calls.add('leave ${album.name}');
    _albums.remove(album);
    _changed.add(null);
  }

  @override
  Future<void> join(Uint8List id, InfoAlbum album) async {
    calls.add('join ${album.name}');
    _albums.add(album);
    _changed.add(null);
  }

  @override
  Stream<List<String>>? tags(Uint8List id) => _watch(() => [..._tags]);

  @override
  Future<List<String>> allTags() async => all;

  @override
  Future<void> tag(Uint8List id, String path) async {
    calls.add('tag $path');
    _tags.add(path);
    _changed.add(null);
  }

  @override
  Future<void> untag(Uint8List id, String path) async {
    calls.add('untag $path');
    _tags.remove(path);
    _changed.add(null);
  }

  @override
  void openTag(BuildContext context, String path) => calls.add('open $path');

  @override
  Stream<List<InfoVersion>> versions(Uint8List id) => Stream.value(history);

  @override
  Future<void> revert(Uint8List id, InfoVersion version) async =>
      calls.add('revert ${version.label}');

  @override
  Future<void> saveCopy(Uint8List id, InfoVersion version) async =>
      calls.add('copy ${version.label}');
}
