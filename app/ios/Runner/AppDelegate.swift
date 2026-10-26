import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    MlBackground.registerTask()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HdrLeaf") {
      HdrLeafFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeLog") {
      NativeLog.shared.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoKit") {
      PhotoKitChannel.register(with: registrar)
      ThumbnailChannel.register(with: registrar)
      ShareSheet.register(with: registrar)
      ViewerChannel.register(with: registrar)
      ShareInbox.register(with: registrar)
      DeviceHealth.register(with: registrar.messenger())
      MlChannel.register(with: registrar.messenger())
      MediaRequests.register(with: registrar)
    }
  }

  /// Offers a file of the app's own, such as the diagnostic bundle, through the share sheet: the viewer channel's
  /// "share", which ViewerChannel (ThumbnailChannel.swift) passes on.
  static func share(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "share", let path = (call.arguments as? [Any])?.first as? String,
      let url = URL(string: path), url.isFileURL
    else { return result(FlutterMethodNotImplemented) }
    let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    guard let root = window?.rootViewController, let view = root.view else { return result(nil) }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // An iPad shows the sheet as a popover, which needs an anchor.
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    (root.presentedViewController ?? root).present(sheet, animated: true)
    result(nil)
  }
}
