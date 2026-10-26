import Flutter
import Photos
import UniformTypeIdentifiers
import WidgetKit

/// The App Group's inbox, which the share extension fills (ShareViewController.swift, ADR-0143), for
/// app/lib/core/share_inbox.dart: where it is, and saving an entry's photos and videos into the Photos library in one
/// change, which PhotoKitChannel's observer then hears; `denied` while Photolib may not add to it, until `allow`.
/// Photos and videos opened in Photolib, from Files or another app (CFBundleDocumentTypes), join the inbox as an entry
/// of their own, and the app hears `changed`. `reloadWidgets` has WidgetKit reload the home screen widgets, which read
/// the App Group's Widgets/ (WidgetExtension).
final class ShareInbox: NSObject, FlutterSceneLifeCycleDelegate {
  private static let inbox = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.org.photolib.photolib")?
    .appendingPathComponent("Inbox", isDirectory: true)
  private static let denied = FlutterError(code: "denied", message: nil, details: nil)
  private let channel: FlutterMethodChannel

  private init(_ channel: FlutterMethodChannel) { self.channel = channel }

  static func register(with registrar: FlutterPluginRegistrar) {
    let inbox = ShareInbox(FlutterMethodChannel(name: "org.photolib/inbox", binaryMessenger: registrar.messenger()))
    inbox.channel.setMethodCallHandler { call, result in
      switch call.method {
      case "folder": result(Self.inbox?.path)
      case "save":
        guard let items = call.arguments as? [[String]] else { return result(FlutterMethodNotImplemented) }
        save(items, result)
      case "allow": allow(result)
      case "reloadWidgets":
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    registrar.addSceneDelegate(inbox)
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions?) -> Bool {
    open(options?.urlContexts ?? [])
  }

  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) -> Bool { open(contexts) }

  /// Moves each photo and video of [contexts], copies the system made for the app (LSSupportsOpeningDocumentsInPlace
  /// is false), into a new entry, then writes its manifest.
  private func open(_ contexts: Set<UIOpenURLContext>) -> Bool {
    guard let inbox = Self.inbox else { return false }
    let entry = inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var items = [[String: String]]()
    for (index, url) in contexts.map(\.url).filter(\.isFileURL).enumerated() {
      guard let type = UTType(filenameExtension: url.pathExtension),
        type.conforms(to: .image) || type.conforms(to: .movie)
      else { continue }
      // A folder each, so that files of the same name stay apart.
      let folder = entry.appendingPathComponent("\(index)", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
      } catch { continue }
      items.append(["file": "\(index)/\(url.lastPathComponent)", "kind": type.conforms(to: .movie) ? "video" : "photo"])
    }
    do {
      guard !items.isEmpty else { throw CocoaError(.fileReadUnknown) }
      try JSONSerialization.data(withJSONObject: ["items": items])
        .write(to: entry.appendingPathComponent("manifest.json"), options: .atomic)
    } catch {
      // deletion-ok: the inbox entry the app failed to finish
      try? FileManager.default.removeItem(at: entry)
      return false
    }
    channel.invokeMethod("changed", arguments: nil)
    return true
  }

  private static func save(_ items: [[String]], _ result: @escaping FlutterResult) {
    if [.denied, .restricted].contains(PHPhotoLibrary.authorizationStatus(for: .addOnly)) { return result(denied) }
    PHPhotoLibrary.shared().performChanges {
      for item in items {
        PHAssetCreationRequest.forAsset().addResource(
          with: item[1] == "video" ? .video : .photo, fileURL: URL(fileURLWithPath: item[0]), options: nil)
      }
    } completionHandler: { saved, error in
      DispatchQueue.main.async {
        if saved { return result(nil) }
        // The system asked, and the user said no.
        if (error as? PHPhotosError)?.code == .accessUserDenied { return result(denied) }
        result(FlutterError(code: "inbox", message: error?.localizedDescription, details: nil))
      }
    }
  }

  /// iOS asks once; after that only Settings change the answer, which the app tries again on resume.
  private static func allow(_ result: @escaping FlutterResult) {
    guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined else {
      if let settings = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(settings) }
      return result(nil)
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in DispatchQueue.main.async { result(nil) } }
  }
}
