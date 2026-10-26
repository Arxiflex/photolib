import AVFoundation
import Cocoa
import FlutterMacOS
import ImageIO

private let viewType = "photolib/hdr"

/// The native HDR leaf of docs/10 §4.5 (ADR-0060): an NSImageView that prefers high dynamic range, with the image
/// decoded to HDR by ImageIO (gain maps applied), or an AVPlayerLayer. Flutter keeps every pointer event and draws its
/// SDR frame on top until the leaf reports `rendered`.
final class HdrLeafFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    registrar.register(HdrLeafFactory(messenger: messenger), withId: viewType)
    FlutterMethodChannel(name: viewType, binaryMessenger: messenger).setMethodCallHandler { call, result in
      if call.method == "support" {
        result(HdrLeafFactory.support())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// NSImageView and ImageIO show HDR from macOS 14; the screens decide whether there is headroom, and low power mode
  /// shows SDR.
  private static func support() -> String {
    guard #available(macOS 14, *) else { return "none" }
    if ProcessInfo.processInfo.isLowPowerModeEnabled { return "sdr" }
    let headroom = NSScreen.screens.map { $0.maximumPotentialExtendedDynamicRangeColorComponentValue }
    return headroom.contains { $0 > 1 } ? "hdr" : "sdr"
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let params = args as? [String: Any] ?? [:]
    return HdrLeaf(
      url: URL(string: params["uri"] as? String ?? "") ?? URL(fileURLWithPath: ""),
      video: params["video"] as? Bool ?? false,
      channel: FlutterMethodChannel(name: "\(viewType)/\(viewId)", binaryMessenger: messenger))
  }
}

private final class HdrLeaf: NSView {
  private let channel: FlutterMethodChannel
  private var playerLayer: AVPlayerLayer?
  private var ready: NSKeyValueObservation?

  init(url: URL, video: Bool, channel: FlutterMethodChannel) {
    self.channel = channel
    super.init(frame: .zero)
    wantsLayer = true
    if video { play(url) } else { show(url) }
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  /// AppKit would deliver pointer events here; declining them leaves them to Flutter.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    playerLayer?.frame = bounds
  }

  private func show(_ url: URL) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let image = decodeHdr(url).map { NSImage(cgImage: $0, size: .zero) }
      DispatchQueue.main.async {
        guard let self else { return }
        guard let image else { return self.channel.invokeMethod("failed", arguments: nil) }
        let view = NSImageView(frame: self.bounds)
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.autoresizingMask = [.width, .height]
        if #available(macOS 14, *) { view.preferredImageDynamicRange = .high }
        self.addSubview(view)
        // On screen after this run loop's commit.
        DispatchQueue.main.async { self.channel.invokeMethod("rendered", arguments: nil) }
      }
    }
  }

  private func play(_ url: URL) {
    let player = AVPlayer(url: url)
    let layer = AVPlayerLayer(player: player)
    layer.frame = bounds
    self.layer?.addSublayer(layer)
    playerLayer = layer
    ready = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
      guard layer.isReadyForDisplay else { return }
      DispatchQueue.main.async { self?.channel.invokeMethod("rendered", arguments: nil) }
    }
    player.play()
  }
}

/// Decodes off the main thread, to HDR from macOS 14 (ImageIO applies Apple and ISO gain maps).
private func decodeHdr(_ url: URL) -> CGImage? {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  var options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
  if #available(macOS 14, *) { options[kCGImageSourceDecodeRequest] = kCGImageSourceDecodeToHDR }
  return decodeUpright(source, options)
}

/// ImageIO's plain decode returns the pixels as stored and ignores the EXIF orientation, so a phone photo (stored
/// landscape, tagged to rotate) would show sideways over its upright SDR thumbnail. A photo with an orientation other
/// than 1 goes through the thumbnail path with the transform flag at its full size; an upright one keeps the plain
/// decode. This function is the same in the iOS leaf (tools/tests/test_hdr_orientation.sh).
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
