import Cocoa
import FlutterMacOS

/// Files dragged between Finder and the window (ADR-0144), for app/lib/features/desktop/file_drag.dart: files dropped
/// on the window go to Dart as their paths (`dropped`, from MainFlutterWindow's dragging destination), and Dart's
/// `drag` drags paths out of it as copies, while the mouse button that moved them is down. Files Finder opens with the
/// app (CFBundleDocumentTypes) go as a drop, and those that come before Dart asks for them (`opened`) wait.
final class FileDrag: NSObject, NSDraggingSource, FlutterAppLifecycleDelegate {
  private var channel: FlutterMethodChannel?
  /// Opened before Dart asked; nil once it did.
  private var opened: [String]? = []
  private weak var view: NSView?
  /// The left button's latest event, which a drag starts from.
  private var mouse: NSEvent?
  private var monitor: Any?

  func register(with registrar: FlutterPluginRegistrar, view: NSView) {
    self.view = view
    let channel = FlutterMethodChannel(name: "org.photolib/drag", binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch (call.method, call.arguments) {
      case ("drag", let paths as [String]):
        self?.drag(paths)
        result(nil)
      case ("opened", _):
        result(self?.opened ?? [])
        self?.opened = nil
      default: result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    registrar.addApplicationDelegate(self)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
      self?.mouse = event
      return event
    }
  }

  private func drag(_ paths: [String]) {
    guard let view, let mouse else { return }
    let point = view.convert(mouse.locationInWindow, from: nil)
    let items = paths.map { path in
      let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: path) as NSURL)
      let frame = NSRect(x: point.x - 32, y: point.y - 32, width: 64, height: 64)
      item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: path))
      return item
    }
    view.beginDraggingSession(with: items, event: mouse, source: self)
  }

  /// Copies, and only out of the app: its own window takes none of its files.
  func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    context == .outsideApplication ? .copy : []
  }

  /// The drag kept the mouse, so Flutter never heard the button go up: tell it, or its next click is lost.
  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    guard let window = view?.window,
      let release = NSEvent.mouseEvent(
        with: .leftMouseUp, location: window.convertPoint(fromScreen: screenPoint), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 0)
    else { return }
    window.sendEvent(release)
  }

  /// Files, and the password setup links photolibd's page hands the app (ADR-0243), which Dart tells apart.
  func handleOpen(_ urls: [URL]) -> Bool {
    let paths = urls.compactMap { url in
      url.isFileURL ? url.path : url.scheme == "photolib" ? url.absoluteString : nil
    }
    guard !paths.isEmpty else { return false }
    if opened == nil { channel?.invokeMethod("dropped", arguments: paths) } else { opened?.append(contentsOf: paths) }
    return true
  }

  /// Hands Dart the files of a drop from another app; false when it brought none.
  func dropped(_ info: NSDraggingInfo) -> Bool {
    guard info.draggingSource == nil,
      let urls = info.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      !urls.isEmpty
    else { return false }
    channel?.invokeMethod("dropped", arguments: urls.map(\.path))
    return true
  }
}
