import CoreLocation
import Photos
import UIKit
import XCTest

/// The iOS backup spike's measurements (docs/dev/ios-backup-spike.md). tools/ios/photokit_probe.sh runs it with
/// PROBE_RUN, PROBE_SEED and PROBE_SINK and collects one `PROBE {json}` line per result.
final class PhotoKitProbe: XCTestCase {
  private let env = ProcessInfo.processInfo.environment
  private let library = PHPhotoLibrary.shared()

  func testProbe() throws {
    try XCTSkipUnless(env["PROBE_RUN"] == "1", "run by tools/ios/photokit_probe.sh")
    continueAfterFailure = false
    authorize()
    try seed(to: Int(env["PROBE_SEED"] ?? "") ?? 0)
    let assets = enumerate()
    cloudIdentifiers(assets)
    let grid = Array(assets.prefix(2_000))
    thumbnails("thumb_fast", grid, .fastFormat)
    thumbnails("thumb_quality", grid, .highQualityFormat)
    try observeChanges(Array(assets.prefix(20)))
    livePhotosAndBursts(assets)
    icloudOriginals(Array(assets.suffix(500)))
    guard let sink = env["PROBE_SINK"].flatMap({ URL(string: $0) }) else { return }
    try upload("upload_background_8m", to: sink, mib: 8, background: true)
    try upload("upload_foreground_8m", to: sink, mib: 8, background: false)
    try upload("upload_background_32m", to: sink, mib: 32, background: true)
    try upload("upload_foreground_32m", to: sink, mib: 32, background: false)
  }

  private func report(_ metric: String, _ count: Int, seconds: Double, bytes: Int = 0) {
    let time = String(format: "%.3f", seconds)
    print("PROBE {\"metric\":\"\(metric)\",\"count\":\(count),\"seconds\":\(time),\"bytes\":\(bytes)}")
  }

  private func authorize() {
    if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
      let answered = expectation(description: "photo access")
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in answered.fulfill() }
      wait(for: [answered], timeout: 300)
    }
    XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized, "allow full photo access")
  }

  /// Simulators only: small JPEGs, dated back from now over 15 years per 100k, until the library holds `target`.
  private func seed(to target: Int) throws {
    let missing = target - PHAsset.fetchAssets(with: nil).count
    guard missing > 0 else { return }
    let size = CGSize(width: 256, height: 192)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("probe-seed.jpg")
    try UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.8) { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }.write(to: file)
    let start = now()
    for first in stride(from: 0, to: missing, by: 500) {
      try library.performChangesAndWait {
        for index in first..<min(first + 500, missing) {
          let request = PHAssetCreationRequest.forAsset()
          request.addResource(with: .photo, fileURL: file, options: nil)
          request.creationDate = Date(timeIntervalSinceNow: -Double(index) * 4_730)
        }
      }
    }
    report("seed", missing, seconds: now() - start)
  }

  /// Every asset with the fields the index keeps (design 10 §6.1), newest first, burst frames included.
  private func enumerate() -> [PHAsset] {
    let start = now()
    let options = PHFetchOptions()
    options.includeAllBurstAssets = true
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let result = PHAsset.fetchAssets(with: options)
    var assets = [PHAsset]()
    assets.reserveCapacity(result.count)
    result.enumerateObjects { asset, _, _ in
      _ = (asset.localIdentifier, asset.creationDate, asset.modificationDate, asset.location, asset.mediaSubtypes,
           asset.burstIdentifier, asset.pixelWidth, asset.pixelHeight, asset.duration, asset.isFavorite,
           asset.hasAdjustments)
      assets.append(asset)
    }
    report("enumerate", assets.count, seconds: now() - start)
    return assets
  }

  /// Cloud identifiers: an asset's identity across devices and reinstalls (design 05 §6).
  private func cloudIdentifiers(_ assets: [PHAsset]) {
    let start = now()
    let ids = assets.map(\.localIdentifier)
    var mapped = 0
    for first in stride(from: 0, to: ids.count, by: 1_000) {
      let batch = Array(ids[first..<min(first + 1_000, ids.count)])
      mapped += library.cloudIdentifierMappings(forLocalIdentifiers: batch).values.filter {
        if case .success = $0 { return true } else { return false }
      }.count
    }
    report("cloud_ids", mapped, seconds: now() - start)
  }

  /// Grid thumbnails, all requested at once as a scrolling grid does, never from the network.
  private func thumbnails(_ metric: String, _ assets: [PHAsset], _ mode: PHImageRequestOptionsDeliveryMode) {
    guard !assets.isEmpty else { return }
    let options = PHImageRequestOptions()
    options.deliveryMode = mode
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = false
    let done = expectation(description: metric)
    done.expectedFulfillmentCount = assets.count
    let lock = NSLock()
    var delivered = 0
    let start = now()
    for asset in assets {
      PHImageManager.default().requestImage(
        for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFill, options: options
      ) { image, _ in
        lock.lock()
        if image != nil { delivered += 1 }
        lock.unlock()
        done.fulfill()
      }
    }
    wait(for: [done], timeout: 600)
    report(metric, delivered, seconds: now() - start)
  }

  /// How soon the observer hears of a change, and how long reading the persistent history that replays it after a
  /// relaunch takes. Toggles favourites and restores them, so a phone's library ends as it began.
  private func observeChanges(_ assets: [PHAsset]) throws {
    guard !assets.isEmpty else { return }
    let token = library.currentChangeToken
    let observer = ChangeObserver(expectation(description: "change"))
    library.register(observer)
    defer { library.unregisterChangeObserver(observer) }
    let start = now()
    try setFavourite(assets, restore: false)
    wait(for: [observer.changed], timeout: 60)
    report("observe", assets.count, seconds: (observer.at ?? now()) - start)
    try setFavourite(assets, restore: true)
    let read = now()
    var updated = Set<String>()
    for change in try library.fetchPersistentChanges(since: token) {
      try updated.formUnion(change.changeDetails(for: .asset).updatedLocalIdentifiers)
    }
    report("persistent_changes", updated.count, seconds: now() - read)
  }

  private func setFavourite(_ assets: [PHAsset], restore: Bool) throws {
    try library.performChangesAndWait {
      for asset in assets {
        PHAssetChangeRequest(for: asset).isFavorite = restore ? asset.isFavorite : !asset.isFavorite
      }
    }
  }

  /// Live Photos with their paired video, and burst frames by burst: the resources backup commits as one asset.
  private func livePhotosAndBursts(_ assets: [PHAsset]) {
    let live = assets.filter { $0.mediaSubtypes.contains(.photoLive) }.prefix(500)
    var start = now()
    let paired = live.filter { asset in
      PHAssetResource.assetResources(for: asset).contains { $0.type == .pairedVideo }
    }.count
    report("live_resources", paired, seconds: now() - start)
    let options = PHFetchOptions()
    options.includeAllBurstAssets = true
    start = now()
    let frames = Set(assets.compactMap(\.burstIdentifier)).prefix(100).reduce(0) {
      $0 + PHAsset.fetchAssets(withBurstIdentifier: $1, options: options).count
    }
    report("burst_frames", frames, seconds: now() - start)
  }

  /// Up to 20 originals that iCloud Photos keeps off the device, found among the oldest photos and downloaded one at a
  /// time, as backup does (design 10 §6.2). A simulator has none.
  private func icloudOriginals(_ oldest: [PHAsset]) {
    let offline = PHImageRequestOptions()
    offline.isNetworkAccessAllowed = false
    var inCloud = [PHAsset]()
    for asset in oldest where asset.mediaType == .image && inCloud.count < 20 {
      let checked = expectation(description: "on device")
      PHImageManager.default().requestImageDataAndOrientation(for: asset, options: offline) { data, _, _, info in
        if data == nil, info?[PHImageResultIsInCloudKey] as? Bool == true { inCloud.append(asset) }
        checked.fulfill()
      }
      wait(for: [checked], timeout: 60)
    }
    let network = PHAssetResourceRequestOptions()
    network.isNetworkAccessAllowed = true
    var bytes = 0
    let start = now()
    for asset in inCloud {
      let resources = PHAssetResource.assetResources(for: asset)
      guard let original = resources.first(where: { $0.type == .photo }) else { continue }
      let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let downloaded = expectation(description: "download")
      PHAssetResourceManager.default().writeData(for: original, toFile: file, options: network) { _ in
        downloaded.fulfill()
      }
      wait(for: [downloaded], timeout: 600)
      bytes += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      try? FileManager.default.removeItem(at: file)
    }
    report("icloud_download", inCloud.count, seconds: now() - start, bytes: bytes)
  }

  /// Four appends of `mib` MiB at once to the sink, through a background session (transfers that outlive the app) or
  /// an in-process one. ADR-0032 sends 8 MiB appends; the design allows up to 32.
  private func upload(_ metric: String, to sink: URL, mib: Int, background: Bool) throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(mib)m")
    try Data(count: mib << 20).write(to: file)
    let configuration: URLSessionConfiguration =
      background ? .background(withIdentifier: "org.photolib.probe.\(metric)") : .ephemeral
    let delegate = UploadDelegate(expectation(description: metric), tasks: 4)
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: sink.appendingPathComponent("upload/\(mib)"))
    request.httpMethod = "POST"
    let start = now()
    for _ in 0..<4 { session.uploadTask(with: request, fromFile: file).resume() }
    wait(for: [delegate.done], timeout: 600)
    XCTAssertEqual(delegate.failures, 0, "uploads to \(sink) failed")
    report(metric, 4, seconds: now() - start, bytes: 4 * mib << 20)
  }
}

private func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
  let changed: XCTestExpectation
  private(set) var at: Double?

  init(_ changed: XCTestExpectation) { self.changed = changed }

  func photoLibraryDidChange(_ changeInstance: PHChange) {
    guard at == nil else { return }
    at = now()
    changed.fulfill()
  }
}

private final class UploadDelegate: NSObject, URLSessionTaskDelegate {
  let done: XCTestExpectation
  private(set) var failures = 0

  init(_ done: XCTestExpectation, tasks: Int) {
    done.expectedFulfillmentCount = tasks
    self.done = done
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if error != nil || (task.response as? HTTPURLResponse)?.statusCode != 201 { failures += 1 }
    done.fulfill()
  }
}
