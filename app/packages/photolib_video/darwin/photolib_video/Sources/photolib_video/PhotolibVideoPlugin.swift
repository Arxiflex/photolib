import AVFoundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// AVFoundation runs the plans of photolib_video; the planner and its rules are Dart (lib/src/plan.dart).
public class PhotolibVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "org.photolib.video", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(PhotolibVideoPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        switch call.method {
        case "probe":
          result(try await Self.probe(URL(fileURLWithPath: call.arguments as! String)))
        case "execute":
          let args = call.arguments as! [String: Any]
          try await Self.execute(
            args["plan"] as! [String: Any], paths: args["paths"] as! [String: String],
            out: URL(fileURLWithPath: args["out"] as! String))
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "video", message: "\(error)", details: nil))
      }
    }
  }

  enum VideoError: Error { case noVideoTrack, exportFailed }

  static let transfers: [String: String] = [
    kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String: "arib-std-b67",
    kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String: "smpte2084",
  ]
  /// QuickTime metadata keys, by the FFmpeg names that plans use.
  static let keys: [String: AVMetadataIdentifier] = [
    "com.apple.quicktime.creationdate": .quickTimeMetadataCreationDate,
    "com.apple.quicktime.location.ISO6709": .quickTimeMetadataLocationISO6709,
    "com.apple.quicktime.make": .quickTimeMetadataMake,
    "com.apple.quicktime.model": .quickTimeMetadataModel,
    "com.apple.quicktime.content.identifier": .quickTimeMetadataContentIdentifier,
    "location": .quickTimeUserDataLocationISO6709,
  ]

  static func probe(_ url: URL) async throws -> [String: Any] {
    let asset = AVURLAsset(url: url)
    guard let video = try await asset.loadTracks(withMediaType: .video).first else {
      throw VideoError.noVideoTrack
    }
    let (size, transform, frame, formats) = try await video.load(
      .naturalSize, .preferredTransform, .minFrameDuration, .formatDescriptions)
    let transfer = CMFormatDescriptionGetExtension(
      formats[0], extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
    var tags: [String: String] = [:]
    if let date = try await asset.load(.creationDate)?.load(.dateValue) {
      tags["creation_time"] = ISO8601DateFormatter().string(from: date)
    }
    for item in try await asset.load(.metadata) {
      if let key = keys.first(where: { $0.value == item.identifier })?.key,
        let value = try await item.load(.stringValue)
      {
        tags[key] = value
      }
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    reader.startReading()
    var keyframes: [Int] = []
    while let sample = output.copyNextSampleBuffer() {
      guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
      if attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true {
        keyframes.append(us(CMSampleBufferGetPresentationTimeStamp(sample)))
      }
    }
    let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    return [
      "width": Int(size.width), "height": Int(size.height), "rotation": (degrees + 360) % 360,
      "fps": "\(frame.timescale)/\(frame.value)",
      "transfer": transfers[transfer ?? ""] ?? "bt709",
      "hasAudio": !(try await asset.loadTracks(withMediaType: .audio).isEmpty),
      "durationUs": us(try await asset.load(.duration)), "keyframesUs": keyframes, "tags": tags,
    ]
  }

  static func execute(_ plan: [String: Any], paths: [String: String], out: URL) async throws {
    let cuts = plan["cuts"] as! [[String: Any]]
    let session: AVAssetExportSession
    if let video = plan["video"] as? [String: Any] {
      session = try await transcode(cuts, video: video, audio: plan["audio"] as! Bool, paths: paths)
    } else {
      // Passthrough copies the samples; the planner put the start on a keyframe.
      let asset = AVURLAsset(url: URL(fileURLWithPath: paths[cuts[0]["assetId"] as! String]!))
      session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)!
      session.timeRange = range(cuts[0])
    }
    session.metadata = metadata(plan["tags"] as! [String: String])
    session.outputURL = out
    session.outputFileType = out.pathExtension == "mov" ? .mov : .mp4
    await session.export()
    if session.status != .completed { throw session.error ?? VideoError.exportFailed }
  }

  static func transcode(
    _ cuts: [[String: Any]], video: [String: Any], audio: Bool, paths: [String: String]
  ) async throws -> AVAssetExportSession {
    let width = CGFloat(video["width"] as! Int), height = CGFloat(video["height"] as! Int)
    let composition = AVMutableComposition()
    let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let sound = audio ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
    var instructions: [AVVideoCompositionInstructionProtocol] = []
    var cursor = CMTime.zero
    for cut in cuts {
      let asset = AVURLAsset(url: URL(fileURLWithPath: paths[cut["assetId"] as! String]!))
      let range = range(cut)
      let source = try await asset.loadTracks(withMediaType: .video)[0]
      try track.insertTimeRange(range, of: source, at: cursor)
      if let sound {
        if let voice = try await asset.loadTracks(withMediaType: .audio).first {
          try sound.insertTimeRange(range, of: voice, at: cursor)
        } else {
          sound.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: range.duration))
        }
      }
      // Turn the clip upright, then fit it into the frame with letter- or pillarboxing.
      let (size, transform) = try await source.load(.naturalSize, .preferredTransform)
      let upright = CGRect(origin: .zero, size: size).applying(transform)
      let scale = min(width / upright.width, height / upright.height)
      let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
      layer.setTransform(
        transform.concatenating(CGAffineTransform(translationX: -upright.minX, y: -upright.minY))
          .concatenating(CGAffineTransform(scaleX: scale, y: scale))
          .concatenating(
            CGAffineTransform(
              translationX: (width - upright.width * scale) / 2, y: (height - upright.height * scale) / 2)),
        at: cursor)
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
      instruction.layerInstructions = [layer]
      instructions.append(instruction)
      cursor = cursor + range.duration
    }
    let composer = AVMutableVideoComposition()
    composer.renderSize = CGSize(width: width, height: height)
    let fps = (video["fps"] as! String).split(separator: "/").map { Int32($0)! }
    composer.frameDuration = CMTime(value: CMTimeValue(fps[1]), timescale: fps[0])
    composer.instructions = instructions
    // An SDR colour space makes AVFoundation tone-map HDR clips; an HDR one keeps them.
    let transfer = video["transfer"] as! String
    let hdr = transfer != "bt709"
    composer.colorPrimaries = hdr ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2
    composer.colorYCbCrMatrix = hdr ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2
    composer.colorTransferFunction =
      ["arib-std-b67": AVVideoTransferFunction_ITU_R_2100_HLG, "smpte2084": AVVideoTransferFunction_SMPTE_ST_2084_PQ][
        transfer] ?? AVVideoTransferFunction_ITU_R_709_2
    let preset = hdr ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
    let session = AVAssetExportSession(asset: composition, presetName: preset)!
    session.videoComposition = composer
    return session
  }

  /// The plan's tags as QuickTime metadata. mvhd gets the export time, so the capture time goes into the creation
  /// date key, which Apple Photos reads first.
  static func metadata(_ tags: [String: String]) -> [AVMetadataItem] {
    var tags = tags
    tags["com.apple.quicktime.creationdate"] = tags["com.apple.quicktime.creationdate"] ?? tags["creation_time"]
    tags["com.apple.quicktime.location.ISO6709"] = tags["com.apple.quicktime.location.ISO6709"] ?? tags["location"]
    return tags.compactMap { key, value in
      guard key != "location", key != "com.apple.quicktime.content.identifier", let identifier = keys[key] else {
        return nil
      }
      let item = AVMutableMetadataItem()
      item.identifier = identifier
      item.value = value as NSString
      return item
    }
  }

  static func range(_ cut: [String: Any]) -> CMTimeRange {
    CMTimeRange(
      start: CMTime(value: CMTimeValue(cut["startUs"] as! Int), timescale: 1_000_000),
      duration: CMTime(value: CMTimeValue(cut["durationUs"] as! Int), timescale: 1_000_000))
  }

  static func us(_ time: CMTime) -> Int { Int((time.seconds * 1_000_000).rounded()) }
}
