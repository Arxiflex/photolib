import CoreLocation
import Flutter
import Photos
import UIKit

/// PhotoKit for app/lib/core/photo_kit.dart (ADR-0095): reads the library on a background task queue, never the
/// platform thread, and hands pages of assets over as the JSON rows photolib_data's photo_kit.dart writes. Hidden
/// assets stay out, and nothing is ever downloaded from iCloud.
final class PhotoKitChannel: NSObject, FlutterStreamHandler, PHPhotoLibraryChangeObserver {
  private let library = PHPhotoLibrary.shared()
  /// The library as the first page of a full read saw it, which later pages read (task queue only).
  private var snapshot: PHFetchResult<PHAsset>?
  private var events: FlutterEventSink?
  private var observing = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = PhotoKitChannel()
    FlutterMethodChannel(
      name: "org.photolib/photo_kit", binaryMessenger: messenger, codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?()
    ).setMethodCallHandler(channel.handle)
    FlutterEventChannel(name: "org.photolib/photo_kit/changes", binaryMessenger: messenger).setStreamHandler(channel)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "access": result(access())
      case "requestAccess": requestAccess(result)
      case "select": select(result)
      case "installId": result(try installId())
      case "token":
        result(try NSKeyedArchiver.archivedData(withRootObject: library.currentChangeToken, requiringSecureCoding: true)
          .base64EncodedString())
      case "changedSince": result(try changed(since: call.arguments as! String))
      case "assets":
        let page = call.arguments as! [Int]
        if page[0] == 0 || snapshot == nil { snapshot = PHAsset.fetchAssets(with: options()) }
        let all = snapshot!
        let range = min(page[0], all.count)..<min(page[0] + page[1], all.count)
        result(try rows(all.objects(at: IndexSet(integersIn: range))))
      case "assetsOf":
        let found = PHAsset.fetchAssets(withLocalIdentifiers: call.arguments as! [String], options: options())
        result(try rows(found.objects(at: IndexSet(integersIn: 0..<found.count)).filter { !$0.isHidden }))
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "photo_kit", message: "\(error)", details: nil))
    }
  }

  private func access() -> String {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized: return "full"
    case .limited: return "partial"
    default: return "none"
    }
  }

  /// iOS asks once; after that only Settings change the answer, which the app reads again on resume.
  private func requestAccess(_ result: @escaping FlutterResult) {
    guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else {
      DispatchQueue.main.async {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        result(self.access())
      }
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
      DispatchQueue.main.async {
        self.observe()
        result(self.access())
      }
    }
  }

  /// The system's picker that changes a limited selection; the change observer hears the new one.
  private func select(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
      guard let root = window?.rootViewController else { return result(nil) }
      self.library.presentLimitedLibraryPicker(from: root.presentedViewController ?? root) { _ in result(nil) }
    }
  }

  /// A random id in a keychain item that never leaves this phone, so app data restored onto another one meets a new
  /// id. Fails rather than make a new one while the item cannot be read (before the first unlock).
  private func installId() throws -> String {
    let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "install_id"]
    var data: CFTypeRef?
    let read = SecItemCopyMatching(item.merging([kSecReturnData as String: true]) { $1 } as CFDictionary, &data)
    if read == errSecSuccess, let data = data as? Data { return String(decoding: data, as: UTF8.self) }
    guard read == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(read)) }
    let id = UUID().uuidString
    let added = SecItemAdd(item.merging([
      kSecValueData as String: Data(id.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]) { $1 } as CFDictionary, nil)
    guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
    return id
  }

  /// The assets inserted, updated or deleted since the archived token; nil when the history no longer reaches it.
  private func changed(since archived: String) throws -> [String]? {
    guard let data = Data(base64Encoded: archived),
      let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    else { return nil }
    var ids = Set<String>()
    do {
      for change in try library.fetchPersistentChanges(since: token) {
        let details = try change.changeDetails(for: .asset)
        ids.formUnion(details.insertedLocalIdentifiers)
        ids.formUnion(details.updatedLocalIdentifiers)
        ids.formUnion(details.deletedLocalIdentifiers)
      }
    } catch let error as PHPhotosError
      where error.code == .persistentChangeTokenExpired || error.code == .persistentChangeDetailsUnavailable
    {
      return nil
    }
    return Array(ids)
  }

  /// The library's photos and videos newest first, every frame of a burst included, shared albums left out.
  private func options() -> PHFetchOptions {
    let options = PHFetchOptions()
    options.includeAllBurstAssets = true
    options.includeAssetSourceTypes = [.typeUserLibrary, .typeiTunesSynced]
    options.predicate = NSPredicate(
      format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    return options
  }

  /// A JSON row per asset, in the order photo_kit.dart reads it; bit 32 of the subtypes marks the frame that represents
  /// its burst, bit 33 one the user picked, bit 34 an animated image (FMT-13).
  private func rows(_ assets: [PHAsset]) throws -> String {
    let clouds = library.cloudIdentifierMappings(forLocalIdentifiers: assets.map(\.localIdentifier))
    let rows = assets.map { asset -> [Any] in
      let video = asset.mediaType == .video
      return [
        asset.localIdentifier,
        json(try? clouds[asset.localIdentifier]?.get().stringValue),
        video,
        ms(asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0)),
        json(asset.creationDate.map(ms)),
        asset.pixelWidth,
        asset.pixelHeight,
        json(video ? Int64(asset.duration * 1000) : nil),
        json(asset.location?.coordinate.latitude),
        json(asset.location?.coordinate.longitude),
        Int64(asset.mediaSubtypes.rawValue) | (asset.representsBurst ? 1 << 32 : 0)
          | (asset.burstSelectionTypes.contains(.userPick) ? 1 << 33 : 0)
          | (asset.playbackStyle == .imageAnimated ? 1 << 34 : 0),
        json(asset.burstIdentifier),
        asset.isFavorite,
        asset.hasAdjustments,
      ]
    }
    return String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.events = events
    observe()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    if observing { library.unregisterChangeObserver(self) }
    observing = false
    return nil
  }

  /// Once the user has answered (main thread).
  private func observe() {
    guard events != nil, !observing, access() != "none" else { return }
    library.register(self)
    observing = true
  }

  func photoLibraryDidChange(_ changeInstance: PHChange) {
    DispatchQueue.main.async { self.events?(nil) }
  }
}

private func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

private func json(_ value: Any?) -> Any { value ?? NSNull() }
