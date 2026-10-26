import FlutterMacOS
import Foundation

/// The platform half of photolib_data's DeletionService on macOS (ADR-0245), for app/lib/core/deletion.dart: files
/// go to the Trash, which Finder lists and restores from, and back from it, or out of it for good.
/// tool/deletion_lint.dart allows file deletes nowhere else in the runner.
enum MediaRequests {
  static func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(name: "org.photolib/media_requests", binaryMessenger: registrar.messenger)
      .setMethodCallHandler(handle)
  }

  private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let paths = call.arguments as? [String] ?? []
    let files = FileManager.default
    do {
      switch call.method {
      // Where each file went, in order.
      case "trash":
        var bins: [String] = []
        for path in paths {
          var bin: NSURL?
          try files.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &bin)
          bins.append(bin?.path ?? "")
        }
        result(bins)
      // Pairs of where each file was and where the Trash keeps it.
      case "restore":
        for index in stride(from: 0, to: paths.count - 1, by: 2) {
          let place = URL(fileURLWithPath: paths[index])
          try files.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
          try files.moveItem(at: URL(fileURLWithPath: paths[index + 1]), to: place)
        }
        result(nil)
      case "purge":
        for path in paths where files.fileExists(atPath: path) {
          try files.removeItem(atPath: path)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "trash", message: "\(error)", details: nil))
    }
  }
}
