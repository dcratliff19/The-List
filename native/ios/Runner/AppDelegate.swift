import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TheListCapture") {
      let channel = FlutterMethodChannel(name: "thelist/capture", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "getPendingShares" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let group = Bundle.main.object(forInfoDictionaryKey: "TheListAppGroup") as? String ?? "group.app.thelist.shared"
        guard let defaults = UserDefaults(suiteName: group) else {
          result([])
          return
        }
        // Consume the extension queue once; Dart presents each entry for review.
        let pending = defaults.stringArray(forKey: "pendingShares") ?? []
        defaults.removeObject(forKey: "pendingShares")
        result(pending)
      }
    }
  }
}
