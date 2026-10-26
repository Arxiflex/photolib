import FlutterMacOS
import Foundation

/// The runner's diagnostics for app/lib/core/logging.dart's listenToNativeLog (ADR-0115): records wait, at most 1000,
/// until the app asks with `listen`, which they answer; later ones go one at a time as `log` on the main thread.
/// FolderAccess logs before the app's Dart starts.
final class NativeLog {
  static let shared = NativeLog()
  private let lock = NSLock()
  private var waiting = [[Any]]()
  private var channel: FlutterMethodChannel?

  func register(with registrar: FlutterPluginRegistrar) {
    let opened = FlutterMethodChannel(
      name: "org.photolib/log", binaryMessenger: registrar.messenger,
      codec: FlutterStandardMethodCodec.sharedInstance())
    opened.setMethodCallHandler { [self] call, result in
      guard call.method == "listen" else { return result(FlutterMethodNotImplemented) }
      result(
        lock.withLock {
          channel = opened
          defer { waiting.removeAll() }
          return waiting
        })
    }
  }

  /// Logs from any thread; `level` is debug, info, warning or error.
  func log(_ level: String, _ logger: String, _ message: String, _ fields: [String: Any] = [:]) {
    let record: [Any] = [Int(Date().timeIntervalSince1970 * 1000), level, logger, message, fields]
    let live = lock.withLock {
      if channel == nil, waiting.count < 1000 { waiting.append(record) }
      return channel
    }
    guard let live else { return }
    DispatchQueue.main.async { live.invokeMethod("log", arguments: record) }
  }
}
