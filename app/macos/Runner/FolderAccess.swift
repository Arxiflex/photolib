import Cocoa
import FlutterMacOS

/// Security-scoped bookmarks of the folders the user picked, for app/lib/features/folders/folders.dart (design 10
/// §8.1, ADR-0107). The sandbox lets the app read a picked folder until it quits; a bookmark kept in the user defaults
/// gives it back at the next start. They are resolved as this is made, before the app's Dart starts, so that the
/// data isolate's first scan can read every folder whose bookmark still resolves; the others are lost, and the app
/// offers to pick them again. It also shows a file in Finder, which `open -R` cannot from the sandbox
/// (app/lib/features/download/download_io.dart), and opens a place in Maps (app/lib/features/viewer/handoff.dart).
final class FolderAccess {
  private static let defaultsKey = "org.photolib.folderBookmarks"
  private var bookmarks: [String: Data] {
    get { UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
  }
  /// The folders being read, by path.
  private var open = [String: URL]()

  init() {
    for (path, data) in bookmarks { start(path, data) }
  }

  func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(
      name: "org.photolib/folders", binaryMessenger: registrar.messenger,
      codec: FlutterStandardMethodCodec.sharedInstance()
    ).setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "keep":
      let path = call.arguments as! String
      if open[path] == nil {
        do {
          let data = try bookmark(URL(fileURLWithPath: path, isDirectory: true))
          bookmarks[path] = data
          start(path, data)
        } catch {
          note("warning", "bookmark not made", path, error)
        }
      }
      result(nil)
    case "forget":
      let path = call.arguments as! String
      bookmarks[path] = nil
      open.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
      result(nil)
    case "lost":
      result((call.arguments as! [String]).filter { open[$0] == nil })
    case "reveal":
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: call.arguments as! String)])
      result(nil)
    case "view":
      if let uri = call.arguments as? String, let url = URL(string: uri) { NSWorkspace.shared.open(url) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  /// Starts reading the folder of a bookmark, renewing it when stale; why it cannot goes to the app's log.
  private func start(_ path: String, _ data: Data) {
    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    } catch {
      return note("warning", "bookmark does not resolve", path, error)
    }
    guard url.startAccessingSecurityScopedResource() else { return note("warning", "folder not readable", path) }
    open[path] = url
    guard stale else { return }
    do {
      bookmarks[path] = try bookmark(url)
      note("info", "stale bookmark renewed", path)
    } catch {
      note("warning", "stale bookmark not renewed", path, error)
    }
  }

  private func bookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil,
      relativeTo: nil)
  }

  private func note(_ level: String, _ message: String, _ path: String, _ error: Error? = nil) {
    var fields: [String: Any] = ["folder": path]
    if let error = error as NSError? {
      fields["error"] = "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
    NativeLog.shared.log(level, "folders", message, fields)
  }
}
