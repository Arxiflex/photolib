import AVFoundation
import Flutter
import ImageIO
import Photos
import UIKit

private let viewType = "photolib/hdr"

/// The native HDR leaf of docs/10 §4.5 (ADR-0060): a UIImageView that prefers high dynamic range, with the image
/// decoded to HDR by ImageIO (gain maps applied), or an AVPlayerLayer. Flutter keeps every gesture and draws its SDR
/// frame on top until the leaf reports `rendered`.
final class HdrLeafFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    registrar.register(HdrLeafFactory(messenger: messenger), withId: viewType)
    FlutterMethodChannel(name: viewType, binaryMessenger: messenger).setMethodCallHandler { call, result in
      if call.method == "support" {
        result(HdrLeafFactory.support())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// UIImageView and ImageIO show HDR from iOS 17; the screen decides whether there is headroom, and low power mode
  /// shows SDR.
  private static func support() -> String {
    guard #available(iOS 17, *) else { return "none" }
    if ProcessInfo.processInfo.isLowPowerModeEnabled { return "sdr" }
    let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }
    return screens.contains { $0.potentialEDRHeadroom > 1 } ? "hdr" : "sdr"
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    return HdrLeaf(
      frame: frame, uri: params["uri"] as? String ?? "",
      video: params["video"] as? Bool ?? false,
      channel: FlutterMethodChannel(name: "\(viewType)/\(viewId)", binaryMessenger: messenger))
  }
}

private final class HdrLeaf: NSObject, FlutterPlatformView {
  private let root: LeafView
  private let channel: FlutterMethodChannel
  private var ready: NSKeyValueObservation?

  init(frame: CGRect, uri: String, video: Bool, channel: FlutterMethodChannel) {
    root = LeafView(frame: frame)
    self.channel = channel
    super.init()
    root.isUserInteractionEnabled = false
    if video {
      play(URL(string: uri) ?? URL(fileURLWithPath: ""))
    } else if uri.hasPrefix("ph:") {
      showAsset(String(uri.dropFirst("ph:".count)).removingPercentEncoding ?? "")
    } else {
      show { URL(string: uri).flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) } }
    }
  }

  func view() -> UIView { root }

  /// A PhotoKit asset's original data, never from iCloud, as ThumbnailChannel reads it.
  private func showAsset(_ id: String) {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
      // After the view's creation has answered, so that Flutter hears it.
      return DispatchQueue.main.async { self.channel.invokeMethod("failed", arguments: nil) }
    }
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = false
    PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
      self.show { data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) } }
    }
  }

  private func show(_ source: @escaping () -> CGImageSource?) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let image = source().flatMap(decodeHdr).map { UIImage(cgImage: $0) }
      DispatchQueue.main.async {
        guard let self else { return }
        guard let image else { return self.channel.invokeMethod("failed", arguments: nil) }
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        if #available(iOS 17, *) { view.preferredImageDynamicRange = .high }
        self.root.addSubview(view)
        self.root.setNeedsLayout()
        // On screen after this run loop's commit.
        DispatchQueue.main.async { self.channel.invokeMethod("rendered", arguments: nil) }
      }
    }
  }

  private func play(_ url: URL) {
    let player = AVPlayer(url: url)
    let layer = AVPlayerLayer(player: player)
    root.layer.addSublayer(layer)
    ready = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
      guard layer.isReadyForDisplay else { return }
      DispatchQueue.main.async { self?.channel.invokeMethod("rendered", arguments: nil) }
    }
    player.play()
  }
}

/// Sizes the image view or player layer to the leaf, which Flutter resizes.
private final class LeafView: UIView {
  override func layoutSubviews() {
    super.layoutSubviews()
    layer.sublayers?.forEach { $0.frame = bounds }
  }
}

/// Decodes off the main thread, to HDR from iOS 17 (ImageIO applies Apple and ISO gain maps).
private func decodeHdr(_ source: CGImageSource) -> CGImage? {
  var options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
  if #available(iOS 17, *) { options[kCGImageSourceDecodeRequest] = kCGImageSourceDecodeToHDR }
  return decodeUpright(source, options)
}

/// ImageIO's plain decode returns the pixels as stored and ignores the EXIF orientation, so a phone photo (stored
/// landscape, tagged to rotate) would show sideways over its upright SDR thumbnail. A photo with an orientation other
/// than 1 goes through the thumbnail path with the transform flag at its full size; an upright one keeps the plain
/// decode. This function is the same in the macOS leaf (tools/tests/test_hdr_orientation.sh).
private func decodeUpright(_ source: CGImageSource, _ options: [CFString: Any]) -> CGImage? {
  var options = options
  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
  let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
  guard orientation != 1, let width = properties?[kCGImagePropertyPixelWidth] as? Int,
    let height = properties?[kCGImagePropertyPixelHeight] as? Int
  else { return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) }
  options[kCGImageSourceCreateThumbnailFromImageAlways] = true
  options[kCGImageSourceCreateThumbnailWithTransform] = true
  options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
  return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}
