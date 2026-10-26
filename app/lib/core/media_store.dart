import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:photolib_data/photolib_data.dart';

import 'device_library.dart';

/// MediaStore through MediaStoreChannel.kt, which queries it on a background
/// thread, and changes it through MediaRequests.kt: MediaStore's trash, which
/// expires items itself, and its favourites.
class MediaStoreChannel implements MediaStore, DeviceLibrary, MediaPlatform {
  const MediaStoreChannel();

  static const _channel = MethodChannel('org.photolib/media_store');
  static const _changes = EventChannel('org.photolib/media_store/changes');
  static const _requests = MethodChannel('org.photolib/media_requests');

  /// Asks for one request per [_batch] items, the most Android 16 takes in
  /// one; each costs at most one system dialog. Returns what each answered.
  Future<List<Object?>> _request(
    String method,
    List<LocalAssetData> items, {
    bool value = true,
  }) async => [
    for (var i = 0; i < items.length; i += _batch)
      ...?await _requests.invokeListMethod<Object?>(method, {
        'uris': [for (final a in items.skip(i).take(_batch)) _uri(a)],
        'value': value,
      }),
  ];

  static const _batch = 2000;

  static String _uri(LocalAssetData a) {
    final kind = (a.mime ?? '').startsWith('video/') ? 'video' : 'images';
    return 'content://media/${a.volume}/$kind/media/${a.sourceId}';
  }

  @override
  bool get expires => true;

  @override
  bool get restores => true;

  /// Unless the user let Photolib manage media.
  @override
  Future<bool> asksFirst() async =>
      !(await _requests.invokeMethod<bool>('canManageMedia') ?? false);

  @override
  Future<List<Binned>> trash(List<LocalAssetData> items) async => [
    for (final expires in await _request('trash', items))
      (bin: null, expires: expires as int?),
  ];

  @override
  Future<void> restore(List<LocalAssetData> items) =>
      _request('trash', items, value: false);

  @override
  Future<void> purge(List<LocalAssetData> items) => _request('delete', items);

  @override
  Future<void> favorite(List<LocalAssetData> items, {required bool value}) =>
      _request('favorite', items, value: value);

  Future<T> _call<T>(String method, [Object? arguments]) async =>
      (await _channel.invokeMethod<T>(method, arguments)) as T;

  @override
  Future<MediaAccess> access() async =>
      MediaAccess.values.byName(await _call('access'));

  @override
  Future<MediaAccess> requestAccess() async =>
      MediaAccess.values.byName(await _call('requestAccess'));

  @override
  Future<void> Function()? get select => null;

  /// Every change MediaStore notifies, volumes included.
  @override
  Stream<void> get changes => _changes.receiveBroadcastStream();

  @override
  Future<void> index(Replica replica) =>
      indexAside(replica, (db) => MediaStoreIndexer(db, this).sync());

  @override
  Future<String> installId() => _call('installId');

  @override
  Future<List<String>> volumes() async =>
      (await _call<List<Object?>>('volumes')).cast();

  @override
  Future<String?> root(String volume) => _call('root', volume);

  @override
  Future<String> version(String volume) => _call('version', volume);

  @override
  Future<int> generation(String volume) => _call('generation', volume);

  @override
  Future<int> count(String volume) => _call('count', volume);

  @override
  Future<List<int>> ids(String volume) => _call<Int64List>('ids', volume);

  /// A page comes as one flat list, [_columns] values per item.
  @override
  Future<List<MediaStoreItem>> items(
    String volume, {
    required int since,
    required int after,
    required int limit,
  }) async {
    final v = await _call<List<Object?>>('items', [
      volume,
      since,
      after,
      limit,
    ]);
    return [
      for (var i = 0; i < v.length; i += _columns)
        MediaStoreItem(
          id: v[i] as int,
          generation: v[i + 1] as int,
          size: v[i + 2] as int,
          modified: v[i + 3] as int,
          name: v[i + 4] as String? ?? '',
          mime: v[i + 5] as String? ?? '',
          path: v[i + 6] as String? ?? '',
          bucketId: v[i + 7] as String? ?? '',
          bucketName: v[i + 8] as String? ?? '',
          taken: v[i + 9] as int?,
          width: v[i + 10] as int?,
          height: v[i + 11] as int?,
          orientation: v[i + 12] as int?,
          durationMs: v[i + 13] as int?,
          favorite: v[i + 14] as bool,
          trashed: v[i + 15] as bool,
          expires: v[i + 16] as int?,
        ),
    ];
  }

  static const _columns = 17;
}
