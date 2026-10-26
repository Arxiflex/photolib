import UIKit
import UniformTypeIdentifiers

/// "Save to Photolib" in the share sheet (docs/10 §6.4, ADR-0143), without a Flutter engine: copies each shared photo
/// and video into an entry of the App Group's inbox, then writes the entry's manifest; the app saves the entry into the
/// Photos library when it next starts or resumes (ShareInbox.swift, app/lib/core/share_inbox.dart). Files are copied,
/// never loaded, so that long videos fit the extension's memory.
final class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
    view.addSubview(spinner)
    spinner.startAnimating()
    Task {
      do {
        try await save()
        extensionContext?.completeRequest(returningItems: nil)
      } catch {
        extensionContext?.cancelRequest(withError: error)
      }
    }
  }

  private func save() async throws {
    guard
      let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.org.photolib.photolib")
    else { throw CocoaError(.fileNoSuchFile) }
    let entry = inbox.appendingPathComponent("Inbox", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    var items = [[String: String]]()
    for (index, provider) in providers.enumerated() {
      let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie : UTType.image
      // A folder each, so that files of the same name stay apart.
      guard provider.hasItemConformingToTypeIdentifier(type.identifier),
        let name = try? await copy(provider, type, into: entry.appendingPathComponent("\(index)", isDirectory: true))
      else { continue }
      items.append(["file": "\(index)/\(name)", "kind": type == .movie ? "video" : "photo"])
    }
    do {
      guard !items.isEmpty else { throw CocoaError(.fileReadUnknown) }
      // Last: an entry without its manifest is still being copied.
      try JSONSerialization.data(withJSONObject: ["items": items])
        .write(to: entry.appendingPathComponent("manifest.json"), options: .atomic)
    } catch {
      // deletion-ok: the inbox entry this extension failed to finish
      try? FileManager.default.removeItem(at: entry)
      throw error
    }
  }

  /// Copies the file of [provider] into [folder] under its own name, which Photos keeps as the original's.
  private func copy(_ provider: NSItemProvider, _ type: UTType, into folder: URL) async throws -> String {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try await withCheckedThrowingContinuation { done in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
        // The file is gone once this returns.
        guard let url else { return done.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
        done.resume(with: Result {
          try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
          return url.lastPathComponent
        })
      }
    }
  }
}
