import Flutter
import Photos
import UIKit

/// The share sheet, where phones download (app/lib/features/download/download_action.dart, ADR-0128): each PhotoKit
/// asset's current version is written to a temporary folder, from iCloud if need be as the user asked for it (an
/// explicit export, docs/10 §6.2), while Dart shows the download's progress and may cancel it, then offered to other
/// apps; the copies go once the sheet closes. They fill at most 2 GiB or 5 % of the free space, whichever is less
/// (docs/10 §6.2): a share past that stops and answers "tooLarge". Its state is touched on the main thread only.
enum ShareSheet {
  private static var channel: FlutterMethodChannel?
  private static var requests = [PHAssetResourceDataRequestID]()
  private static var cancelled = false
  private static let root = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)

  static func register(with registrar: FlutterPluginRegistrar) {
    // What a share left when the app was killed with its sheet open.
    // deletion-ok: the share's own copies
    try? FileManager.default.removeItem(at: root)
    let channel = FlutterMethodChannel(name: "org.photolib/share", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "share": share(call.arguments as? [String] ?? [], result)
      case "cancel":
        cancel()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    Self.channel = channel
  }

  private static func cancel() {
    cancelled = true
    requests.forEach(PHAssetResourceManager.default().cancelDataRequest)
  }

  /// [file], a shared copy, dated when it was taken, as downloads are.
  private static func dated(_ file: URL, _ taken: Date?) -> URL {
    if let taken {
      try? FileManager.default.setAttributes([.modificationDate: taken], ofItemAtPath: file.path)
    }
    return file
  }

  private static func share(_ ids: [String], _ result: @escaping FlutterResult) {
    let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let free = (try? FileManager.default.temporaryDirectory.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? .max
    let limit = min(2 << 30, free / 20)
    // Bytes arrive on PhotoKit's queues.
    let lock = NSLock()
    var copied: Int64 = 0
    var tooLarge = false
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    let group = DispatchGroup()
    var files = [URL]()
    // How far each asset is; PhotoKit reports progress only while it downloads one from iCloud.
    var fractions = [Double](repeating: 0, count: assets.count)
    var downloading = false
    func report(_ index: Int, _ fraction: Double) {
      fractions[index] = fraction
      guard downloading else { return }
      Self.channel?.invokeMethod("progress", arguments: fractions.reduce(0, +) / Double(fractions.count))
    }
    cancelled = false
    assets.enumerateObjects { asset, index, _ in
      let resources = PHAssetResource.assetResources(for: asset)
      guard
        let resource = resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo })
          ?? resources.first(where: { $0.type == .photo || $0.type == .video })
      else { return }
      // A folder each, so that files of the same name stay apart.
      let file = folder.appendingPathComponent("\(index)", isDirectory: true)
        .appendingPathComponent(resource.originalFilename)
      guard (try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
        FileManager.default.createFile(atPath: file.path, contents: nil),
        let handle = try? FileHandle(forWritingTo: file)
      else { return }
      let options = PHAssetResourceRequestOptions()
      options.isNetworkAccessAllowed = true
      options.progressHandler = { fraction in
        DispatchQueue.main.async {
          downloading = true
          report(index, fraction)
        }
      }
      group.enter()
      Self.requests.append(PHAssetResourceManager.default().requestData(
        for: resource, options: options,
        dataReceivedHandler: { data in
          lock.lock()
          let fits = !tooLarge && copied + Int64(data.count) <= limit
          if fits { copied += Int64(data.count) } else { tooLarge = true }
          lock.unlock()
          if fits { try? handle.write(contentsOf: data) } else { DispatchQueue.main.async(execute: cancel) }
        },
        completionHandler: { error in
          try? handle.close()
          DispatchQueue.main.async {
            if error == nil { files.append(dated(file, asset.creationDate)) }
            report(index, 1)
            group.leave()
          }
        }))
    }
    group.notify(queue: .main) {
      Self.requests = []
      let cancelled = Self.cancelled
      let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
      guard !cancelled, !files.isEmpty, var top = window?.rootViewController else {
        // deletion-ok: the share's own copies
        try? FileManager.default.removeItem(at: folder)
        return result(
          tooLarge
            ? FlutterError(code: "tooLarge", message: nil, details: nil)
            : cancelled
              ? FlutterError(code: "cancelled", message: nil, details: nil)
              : FlutterError(code: "share", message: "no file to share", details: nil))
      }
      while let shown = top.presentedViewController { top = shown }
      let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
      // An iPad shows it as a popover, which needs an anchor.
      sheet.popoverPresentationController?.sourceView = top.view
      sheet.popoverPresentationController?.sourceRect = CGRect(
        x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      // deletion-ok: the share's own copies, once the sheet is done
      sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
      top.present(sheet, animated: true)
      result(nil)
    }
  }
}
