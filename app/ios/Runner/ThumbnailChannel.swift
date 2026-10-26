import AVFoundation
import Flutter
import Photos
import UIKit

/// PhotoKit's thumbnails for app/lib/features/library/timeline/platform_thumbnails.dart (design 10 §3.4, T3): the
/// asset of a `ph:` local identifier at the tier from PHCachingImageManager, never from the network, handed over as
/// width, height and upright sRGB pixels in premultiplied BGRA, CoreGraphics' own order (ADR-0040). Cancelling a
/// request cancels it in PhotoKit.
final class ThumbnailChannel {
  private let manager = PHCachingImageManager()
  private let lock = NSLock()
  /// PhotoKit's id of each request in flight, by the app's.
  private var requests = [Int: PHImageRequestID]()

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let thumbnails = ThumbnailChannel()
    FlutterMethodChannel(
      name: "org.photolib/thumbnails", binaryMessenger: messenger, codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?()
    ).setMethodCallHandler(thumbnails.handle)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "load":
      let args = call.arguments as! [Any]
      let id = String((args[0] as! String).dropFirst("ph:".count)).removingPercentEncoding ?? ""
      load(id, tier: args[1] as! Int, request: args[2] as! Int, result)
    case "cancel":
      let request = lock.withLock { requests.removeValue(forKey: call.arguments as! Int) }
      if let request = request { manager.cancelImageRequest(request) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func load(_ id: String, tier: Int, request: Int, _ result: @escaping FlutterResult) {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
      return result(nil)
    }
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = false
    // PhotoKit may answer before requestImage returns: only a request still in flight keeps its id.
    lock.withLock { requests[request] = PHInvalidImageRequestID }
    let id = manager.requestImage(
      for: asset, targetSize: CGSize(width: tier, height: tier), contentMode: .aspectFill, options: options
    ) { image, _ in
      self.lock.withLock { _ = self.requests.removeValue(forKey: request) }
      DispatchQueue.global(qos: .userInitiated).async {
        let pixels = image.flatMap(bgra)
        DispatchQueue.main.async { result(pixels) }
      }
    }
    lock.withLock { if requests[request] != nil { requests[request] = id } }
  }
}

/// The image as it is shown, its orientation applied, converted to sRGB.
private func bgra(_ image: UIImage) -> [Any]? {
  let width = Int(image.size.width * image.scale), height = Int(image.size.height * image.scale)
  guard width > 0, height > 0 else { return nil }
  var pixels = Data(count: width * height * 4)
  let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return false }
    // UIKit draws from the top left.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(context)
    image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
    UIGraphicsPopContext()
    return true
  }
  return drawn ? [width, height, FlutterStandardTypedData(bytes: pixels)] : nil
}

/// The viewer's videos from PhotoKit for app/lib/features/viewer/video.dart (design 10 §4.2, §4.3): the file of a
/// video, which the player reads in place, its frame rate, an image's bytes, which an animation plays, and a Live
/// Photo's paired video, written where the app asks. Like the thumbnails, never from iCloud. A place opens in Maps
/// for app/lib/features/viewer/handoff.dart. AppDelegate.share shares the app's own files on the same channel, and the
/// screen's brightness is set for app/lib/features/viewer/screen.dart; Android's ViewerChannel.kt answers its other
/// methods.
final class ViewerChannel {
  /// The brightness before the viewer set it: iOS keeps an app's after it leaves, so the viewer gives it back.
  private static var saved: CGFloat?

  private static func brightness(_ call: FlutterMethodCall, _ result: FlutterResult) {
    switch call.method {
    case "brightness": result(Double(UIScreen.main.brightness))
    case "setBrightness":
      if let value = call.arguments as? Double {
        saved = saved ?? UIScreen.main.brightness
        UIScreen.main.brightness = CGFloat(value)
      } else if let saved {
        UIScreen.main.brightness = saved
        Self.saved = nil
      }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(name: "org.photolib/viewer", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        if call.method == "share" { return AppDelegate.share(call, result) }
        if call.method.hasSuffix("rightness") { return brightness(call, result) }
        // A place, in Maps.
        if call.method == "view" {
          if let uri = (call.arguments as? [Any])?.first as? String, let url = URL(string: uri) {
            UIApplication.shared.open(url)
          }
          return result(nil)
        }
        guard ["read", "video", "frameRate", "pairedVideo"].contains(call.method), let args = call.arguments as? [Any],
          let uri = args.first as? String
        else { return result(FlutterMethodNotImplemented) }
        let id = String(uri.dropFirst("ph:".count)).removingPercentEncoding ?? ""
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
          return result(nil)
        }
        switch call.method {
        case "read":
          let options = PHImageRequestOptions()
          options.version = .current
          options.isNetworkAccessAllowed = false
          PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            let limit = args.count > 1 ? args[1] as? Int : nil
            let bytes = limit.map { data?.prefix($0) } ?? data
            DispatchQueue.main.async { result(bytes.map { FlutterStandardTypedData(bytes: Data($0)) }) }
          }
        case "video":
          PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { video, _, _ in
            DispatchQueue.main.async { result((video as? AVURLAsset)?.url.path) }
          }
        case "frameRate":
          // Extraction never reads PhotoKit's files; the video track says its rate.
          PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { video, _, _ in
            let rate = video?.tracks(withMediaType: .video).first?.nominalFrameRate
            DispatchQueue.main.async { result(rate.map(Double.init)) }
          }
        case "pairedVideo":
          guard let paired = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .pairedVideo }),
            let path = args.last as? String
          else { return result(nil) }
          let file = URL(fileURLWithPath: path)
          // deletion-ok: the cache's last copy of the paired video, written again
          try? FileManager.default.removeItem(at: file)
          PHAssetResourceManager.default().writeData(for: paired, toFile: file, options: nil) { error in
            DispatchQueue.main.async { result(error == nil ? file.path : nil) }
          }
        default: result(FlutterMethodNotImplemented)
        }
      }
  }
}
