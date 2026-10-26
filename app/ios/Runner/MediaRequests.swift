import Flutter
import Photos

/// The platform half of photolib_data's DeletionService and of favourites on iOS (docs/10-client-app.md §6.1,
/// ADR-0245), for app/lib/core/photo_kit.dart: a delete is one change request, which Photos confirms once and keeps in
/// Recently Deleted; favourites are written to Photos. tool/deletion_lint.dart allows PhotoKit's deletes nowhere else.
enum MediaRequests {
  static func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(name: "org.photolib/media_requests", binaryMessenger: registrar.messenger())
      .setMethodCallHandler(handle)
  }

  private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "delete":
      let assets = PHAsset.fetchAssets(withLocalIdentifiers: call.arguments as? [String] ?? [], options: nil)
      change({ PHAssetChangeRequest.deleteAssets(assets) }, result)
    case "favorite":
      let arguments = call.arguments as? [String: Any] ?? [:]
      let assets = PHAsset.fetchAssets(withLocalIdentifiers: arguments["ids"] as? [String] ?? [], options: nil)
      let value = arguments["value"] as? Bool ?? true
      change({ assets.enumerateObjects { asset, _, _ in PHAssetChangeRequest(for: asset).isFavorite = value } }, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  /// Applies [changes] in one request; the user's refusal fails it.
  private static func change(_ changes: @escaping () -> Void, _ result: @escaping FlutterResult) {
    PHPhotoLibrary.shared().performChanges(changes) { done, error in
      DispatchQueue.main.async {
        result(done ? nil : FlutterError(code: "refused", message: error.map { "\($0)" }, details: nil))
      }
    }
  }
}
