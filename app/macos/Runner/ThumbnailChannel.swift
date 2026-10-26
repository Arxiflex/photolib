import AVFoundation
import Cocoa
import FlutterMacOS
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Thumbnails of files for app/lib/features/library/timeline/platform_thumbnails.dart (design 10 §3.4, T4, ADR-0107):
/// a still through ImageIO's CGImageSourceCreateThumbnailAtIndex, QuickLook for what ImageIO cannot read, a video's
/// first frame through AVAssetImageGenerator. Each runs on a queue of cores − 1 threads, never the main or raster
/// thread, and is handed over as width, height and premultiplied RGBA with its short side at the tier, never larger
/// than the source. A file none of them reads is refused with the error that says why, which the Dart side passes to
/// libvips; a cancelled request and a URL that names no file are said so, never answered with nil.
final class ThumbnailChannel {
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    queue.qualityOfService = .userInitiated
    return queue
  }()
  private let lock = NSLock()
  /// The requests in flight, which a cancel removes.
  private var requests = Set<Int>()

  static func register(with registrar: FlutterPluginRegistrar) {
    let thumbnails = ThumbnailChannel()
    FlutterMethodChannel(
      name: "org.photolib/thumbnails", binaryMessenger: registrar.messenger,
      codec: FlutterStandardMethodCodec.sharedInstance()
    ).setMethodCallHandler(thumbnails.handle)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "load":
      let args = call.arguments as! [Any]
      guard let url = URL(string: args[0] as! String), url.isFileURL else {
        return result(FlutterError(code: "unreadable-url", message: args[0] as? String, details: nil))
      }
      let tier = args[1] as! Int, request = args[2] as! Int
      lock.withLock { _ = requests.insert(request) }
      queue.addOperation {
        let live = { self.lock.withLock { self.requests.contains(request) } }
        self.load(url, tier: tier, live: live) { reply in
          self.lock.withLock { _ = self.requests.remove(request) }
          DispatchQueue.main.async { result(reply) }
        }
      }
    case "cancel":
      lock.withLock { _ = requests.remove(call.arguments as! Int) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func load(_ url: URL, tier: Int, live: () -> Bool, _ reply: @escaping (Any?) -> Void) {
    guard live() else {
      return reply(FlutterError(code: "cancelled", message: url.lastPathComponent, details: nil))
    }
    let answer = { (image: CGImage?, error: Error?) in
      if let image, let pixels = rgba(image, tier: tier) { reply(pixels) } else { reply(refused(url, error)) }
    }
    if UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) == true {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: tier * 4, height: tier * 4)
      return generator.generateCGImageAsynchronously(for: .zero) { image, _, error in answer(image, error) }
    }
    if let image = still(url, tier: tier) { return answer(image, nil) }
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: tier, height: tier), scale: 1, representationTypes: .thumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
      answer(thumbnail?.cgImage, error)
    }
  }
}

/// ImageIO's thumbnail, upright, decoded to fit the tier from a header within 300 MP (design 08 §8.2).
private func still(_ url: URL, tier: Int) -> CGImage? {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
    let header = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let width = header[kCGImagePropertyPixelWidth] as? Int, let height = header[kCGImagePropertyPixelHeight] as? Int,
    width > 0, height > 0, width * height <= 300_000_000
  else { return nil }
  let long = Double(max(width, height)) * min(1, Double(tier) / Double(min(width, height)))
  return CGImageSourceCreateThumbnailAtIndex(
    source, 0,
    [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(long.rounded()),
    ] as CFDictionary)
}

/// The refusal of [url], naming the error and the one under it by domain and code, as AVFoundation's
/// `AVFoundationErrorDomain -11829` and its `NSOSStatusErrorDomain`.
private func refused(_ url: URL, _ error: Error?) -> FlutterError {
  let errors = [error as NSError?, (error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap { $0 }
  let why = errors.map { "\($0.domain) \($0.code): \($0.localizedDescription)" }.joined(separator: "; ")
  return FlutterError(
    code: "refused", message: "\(url.lastPathComponent): \(why.isEmpty ? "unreadable" : why)", details: nil)
}

/// [image] with its short side at the tier, at most its own size, in sRGB.
private func rgba(_ image: CGImage, tier: Int) -> [Any]? {
  let scale = min(1, Double(tier) / Double(min(image.width, image.height)))
  let width = max(1, Int((Double(image.width) * scale).rounded()))
  let height = max(1, Int((Double(image.height) * scale).rounded()))
  var pixels = Data(count: width * height * 4)
  let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
  }
  return drawn ? [width, height, FlutterStandardTypedData(bytes: pixels)] : nil
}
