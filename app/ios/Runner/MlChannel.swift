import Accelerate
import BackgroundTasks
import Flutter
import Network
import Photos
import UIKit
import Vision

/// The device's state for app/lib/core/device_health.dart on Android's scales (DeviceHealth.kt): the thermal state as
/// Android's thermal status, Low Power Mode as battery saver, and an expensive or constrained network as metered.
enum DeviceHealth {
  /// The network's state, kept from the monitor's updates on the main queue; not metered until the first one.
  private static var metered = false
  private static let monitor: NWPathMonitor = {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      metered = path.status == .satisfied && (path.isExpensive || path.isConstrained)
    }
    monitor.start(queue: .main)
    return monitor
  }()

  static func register(with messenger: FlutterBinaryMessenger) {
    _ = monitor
    FlutterMethodChannel(name: "org.photolib/device_health", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "state" else { return result(FlutterMethodNotImplemented) }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        result([
          // The simulator knows no level.
          "battery": device.batteryLevel < 0 ? 100 : Int((device.batteryLevel * 100).rounded()),
          "charging": device.batteryState == .charging || device.batteryState == .full,
          "powerSaving": ProcessInfo.processInfo.isLowPowerModeEnabled,
          "thermal": thermal(),
          "temperature": 0.0,
          "memory": Int(ProcessInfo.processInfo.physicalMemory),
          "metered": metered
        ] as [String: Any])
      }
  }

  /// Fair is Android's moderate, below which background work runs (design 09 §3.4).
  private static func thermal() -> Int {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return 0
    case .fair: return 2
    case .serious: return 3
    case .critical: return 4
    @unknown default: return 4
    }
  }
}

/// On-device ML for app/lib/core/ml.dart (ADR-0254): `decode` hands the indexer a PhotoKit image upright, in sRGB and
/// straight RGBA, its short side at most `size`, never from iCloud, or nil; `recognize` reads the same image's text
/// with Vision and `textSupport` names it; `schedule` leaves the backlog to a
/// BGProcessingTask on external power (design 09 §3.4), which MlBackground asks for, and `cancel` takes it back.
enum MlChannel {
  /// The app's engine's, on which MlBackground asks for the backlog.
  private(set) static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.photolib/ml", binaryMessenger: messenger, codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?())
    Self.channel = channel
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "decode":
        decode(arguments?["id"] as? String ?? "", size: arguments?["size"] as? Int ?? 0, result)
      case "textSupport":
        result(PlatformText.engine)
      case "recognize":
        recognize(arguments?["id"] as? String ?? "", size: arguments?["size"] as? Int ?? 0, result)
      case "schedule":
        MlBackground.schedule()
        result(nil)
      case "cancel":
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: MlBackground.identifier)
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func decode(_ id: String, size: Int, _ result: @escaping FlutterResult) {
    image(id, size: size, what: "decode") { image in
      let pixels = image.flatMap { rgba($0, size: size) }
      DispatchQueue.main.async { result(pixels) }
    }
  }

  /// The text Vision reads in the image, or nil: the platform's own recognition (ADR-0388), whose models are the
  /// system's, so nothing downloads. What it reads is untrusted text; the data isolate cleans it before it is kept.
  private static func recognize(_ id: String, size: Int, _ result: @escaping FlutterResult) {
    image(id, size: size, what: "recognize") { image in
      let text = image.flatMap { PlatformText.read($0) }
      DispatchQueue.main.async { result(text) }
    }
  }

  /// The image PhotoKit gives for `id` with its short side about `size`, never from iCloud, told to `then` on a
  /// utility queue, or nil.
  private static func image(_ id: String, size: Int, what: String, then: @escaping (UIImage?) -> Void) {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
      asset.pixelWidth > 0, asset.pixelHeight > 0, size > 0
    else {
      NativeLog.shared.log("warning", "ml", "\(what) found no image", ["id": id])
      return then(nil)
    }
    let scale = min(1, Double(size) / Double(min(asset.pixelWidth, asset.pixelHeight)))
    let target = CGSize(
      width: (Double(asset.pixelWidth) * scale).rounded(), height: (Double(asset.pixelHeight) * scale).rounded())
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .exact
    options.isNetworkAccessAllowed = false
    options.isSynchronous = false
    let manager = PHImageManager.default()
    manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { image, info in
      DispatchQueue.global(qos: .utility).async {
        if image == nil {
          let fields: [String: Any] = [
            "id": id, "error": "\(info?[PHImageErrorKey] ?? "none")",
            "inCloud": info?[PHImageResultIsInCloudKey] as? Bool ?? false
          ]
          NativeLog.shared.log("warning", "ml", "\(what) failed", fields)
        }
        then(image)
      }
    }
  }

  /// The image as it is shown, its orientation applied, in sRGB, its short side at most `size` whatever PhotoKit gave.
  private static func rgba(_ image: UIImage, size: Int) -> [String: Any]? {
    let shown = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    let scale = min(1, CGFloat(size) / min(shown.width, shown.height))
    let width = Int((shown.width * scale).rounded()), height = Int((shown.height * scale).rounded())
    guard width > 0, height > 0, let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    var pixels = Data(count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return false }
      // UIKit draws from the top left.
      context.translateBy(x: 0, y: CGFloat(height))
      context.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(context)
      image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
      UIGraphicsPopContext()
      // CoreGraphics draws premultiplied; the indexer takes straight colour, as Android's getPixels gives it.
      var buffer = vImage_Buffer(
        data: bytes.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
      return vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags)) == kvImageNoError
    }
    return drawn ? ["width": width, "height": height, "rgba": FlutterStandardTypedData(bytes: pixels)] : nil
  }
}

/// The backlog in a BGProcessingTask on external power, on the app's engine (docs/10 §1.5): asks its Dart for
/// `background` on org.photolib/ml and completes the task with the answer, asking for another when it says `more`;
/// when the task expires, `stop` gives it a few seconds. A launch in the background starts no engine yet, so the task
/// then fails and is asked for again.
enum MlBackground {
  static let identifier = "org.photolib.ml"

  /// Before the app finishes launching, as BGTaskScheduler requires.
  static func registerTask() {
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { run($0) }
    if !registered { NativeLog.shared.log("error", "ml", "background task not registered") }
  }

  static func schedule() {
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = false
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // As in the simulator, which runs no background tasks.
      NativeLog.shared.log("warning", "ml", "background task not scheduled", ["error": "\(error)"])
    }
  }

  /// On the main queue, as registered.
  private static func run(_ task: BGTask) {
    guard let channel = MlChannel.channel else {
      NativeLog.shared.log("info", "ml", "background task without an engine")
      schedule()
      return task.setTaskCompleted(success: false)
    }
    var completed = false
    /// An answer without `more` is a failure, or the Dart did not answer in time.
    func complete(_ answer: Any?) {
      guard !completed else { return }
      completed = true
      task.expirationHandler = nil
      let more = (answer as? [String: Any])?["more"] as? Bool
      if more != false { schedule() }
      task.setTaskCompleted(success: more != nil)
    }
    task.expirationHandler = {
      DispatchQueue.main.async {
        channel.invokeMethod("stop", arguments: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { complete(nil) }
      }
    }
    channel.invokeMethod("background", arguments: nil) { complete($0) }
  }
}

/// The phone's own text recognition for app/lib/core/ml.dart (ADR-0388): Vision's accurate recognition, which detects
/// the language itself (Latin, Cyrillic, Chinese, Japanese and more since iOS 16, the deployment target).
enum PlatformText {
  static let engine = "vision"

  /// The lines Vision reads in `image`, joined by newlines, or nil when it reads none or fails.
  static func read(_ image: UIImage) -> String? {
    guard let cgImage = image.cgImage else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.revision = VNRecognizeTextRequestRevision3
    request.automaticallyDetectsLanguage = true
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(image.imageOrientation))
    do {
      try handler.perform([request])
    } catch {
      NativeLog.shared.log("warning", "ml", "Vision failed", ["error": "\(error)"])
      return nil
    }
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private static func orientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .upMirrored: return .upMirrored
    case .down: return .down
    case .downMirrored: return .downMirrored
    case .left: return .left
    case .leftMirrored: return .leftMirrored
    case .right: return .right
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
