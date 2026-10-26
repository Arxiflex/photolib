import 'package:flutter/services.dart';
import 'package:photolib_data/photolib_data.dart';

import 'device_library.dart';

/// PhotoKit through PhotoKitChannel.swift, which reads it on a background
/// queue and hands pages of assets over as the JSON text that SQLite writes;
/// changed through MediaRequests.swift. Its trash is Photos' Recently Deleted,
/// which Photos confirms and empties, and only Photos restores from.
class PhotoKitChannel implements PhotoKit, DeviceLibrary, MediaPlatform {
  const PhotoKitChannel();

  static const _channel = MethodChannel('org.photolib/photo_kit');
  static const _changes = EventChannel('org.photolib/photo_kit/changes');
  static const _requests = MethodChannel('org.photolib/media_requests');

  @override
  bool get expires => true;

  @override
  bool get restores => false;

  @override
  Future<bool> asksFirst() async => true;

  /// One change request: one confirmation of Photos for all [items].
  @override
  Future<List<Binned>> trash(List<LocalAssetData> items) async {
    await _requests.invokeMethod<void>('delete', [
      for (final a in items) a.sourceId,
    ]);
    return [for (final _ in items) (bin: null, expires: null)];
  }

  @override
  Future<void> restore(List<LocalAssetData> items) =>
      throw UnsupportedError('only Photos restores from Recently Deleted');

  /// Nothing of Photolib's trash is in Recently Deleted, which Photos empties.
  @override
  Future<void> purge(List<LocalAssetData> items) async {}

  @override
  Future<void> favorite(List<LocalAssetData> items, {required bool value}) =>
      _requests.invokeMethod<void>('favorite', {
        'ids': [for (final a in items) a.sourceId],
        'value': value,
      });

  Future<T> _call<T>(String method, [Object? arguments]) async =>
      (await _channel.invokeMethod<T>(method, arguments)) as T;

  @override
  Future<MediaAccess> access() async =>
      MediaAccess.values.byName(await _call('access'));

  /// iOS asks once; then only Settings grant more than a limited selection.
  @override
  Future<MediaAccess> requestAccess() async =>
      MediaAccess.values.byName(await _call('requestAccess'));

  @override
  Future<void> Function() get select =>
      () => _call<void>('select');

  /// Every change PHPhotoLibraryChangeObserver hears, selections included.
  @override
  Stream<void> get changes => _changes.receiveBroadcastStream();

  @override
  Future<void> index(Replica replica) =>
      indexAside(replica, (db) => PhotoKitIndexer(db, this).sync());

  @override
  Future<String> installId() => _call('installId');

  @override
  Future<String> token() => _call('token');

  @override
  Future<List<String>?> changedSince(String token) async =>
      (await _call<List<Object?>?>('changedSince', token))?.cast();

  @override
  Future<String> assets(int offset, int limit) =>
      _call('assets', [offset, limit]);

  @override
  Future<String> assetsOf(List<String> ids) => _call('assetsOf', ids);
}
