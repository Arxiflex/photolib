import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:photolib_data/photolib_data.dart';

/// The model name the faces carried to a copy are kept under in `local_ml`,
/// which the user's withdrawal deletes with every other `faces:` row.
const carriedModel = 'faces:carried';

/// The id the faces carried to the copy at [copy] are kept under until the
/// copy is indexed and finds its own: the first 16 bytes of the SHA-1 of its
/// URI, which the index's row of the copy gives again ([uriOf]).
Uint8List carryId(Uri copy) =>
    Uint8List.fromList(sha1.convert(utf8.encode('$copy')).bytes.sublist(0, 16));

/// The URI of the original of an indexed [row], as the viewer's items have it.
Uri? uriOf(LocalAssetData row) => switch (row.source) {
  'folder' => Uri.file('${row.volume}/${row.path}'),
  'mediastore' => Uri.parse(
    'content://media/${row.volume}/images/media/${row.sourceId}',
  ),
  _ => null,
};
