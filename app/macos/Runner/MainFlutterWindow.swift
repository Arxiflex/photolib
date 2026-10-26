import Cocoa
import FlutterMacOS
import IOKit.ps
import Network

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  /// Opened before the engine starts the app's Dart, and holds the folders open while the app runs.
  private let folders = FolderAccess()
  private let files = FileDrag()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    NativeLog.shared.register(with: flutterViewController.registrar(forPlugin: "NativeLog"))
    RegisterGeneratedPlugins(registry: flutterViewController)
    HdrLeafFactory.register(with: flutterViewController.registrar(forPlugin: "HdrLeaf"))
    ThumbnailChannel.register(with: flutterViewController.registrar(forPlugin: "ThumbnailChannel"))
    DeviceHealth.register(with: flutterViewController.registrar(forPlugin: "DeviceHealth").messenger)
    folders.register(with: flutterViewController.registrar(forPlugin: "FolderAccess"))
    MediaRequests.register(with: flutterViewController.registrar(forPlugin: "MediaRequests"))
    files.register(with: flutterViewController.registrar(forPlugin: "FileDrag"), view: flutterViewController.view)
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }

  /// Files from other apps, which FileDrag hands to Dart; the window's own are not taken back.
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingSource == nil ? .copy : []
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool { files.dropped(sender) }
}

/// The device's state for app/lib/core/device_health.dart on Android's scales (DeviceHealth.kt), as iOS gives it
/// (app/ios/Runner/MlChannel.swift); a Mac without a battery is full and on power. Desktops index in the foreground and
/// decode with libvips in Dart, so org.photolib/ml only takes `schedule` and `cancel`, and does nothing.
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
        let (battery, charging) = power()
        result([
          "battery": battery,
          "charging": charging,
          "powerSaving": ProcessInfo.processInfo.isLowPowerModeEnabled,
          "thermal": thermal(),
          "temperature": 0.0,
          "memory": Int(ProcessInfo.processInfo.physicalMemory),
          "metered": metered
        ] as [String: Any])
      }
    FlutterMethodChannel(name: "org.photolib/ml", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "schedule", "cancel": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The internal battery's charge and whether it is on AC power.
  private static func power() -> (Int, Bool) {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as NSArray?
    else { return (100, true) }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source as CFTypeRef)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let charge = description[kIOPSCurrentCapacityKey] as? Int,
        let capacity = description[kIOPSMaxCapacityKey] as? Int, capacity > 0
      else { continue }
      return (charge * 100 / capacity, description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }
    return (100, true)
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
