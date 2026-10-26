import Flutter
import Foundation
import UIKit

/// Tells the app when the person takes a screenshot or records, mirrors or
/// casts the screen (roadmap G7, channels `wecord/screen_capture` and
/// `wecord/screen_capture/events`).
///
/// * `isCaptured` → `true` while the screen is recorded, mirrored or cast.
/// * events: `screenshot` (after the system took it), `recording_started` and
///   `recording_stopped`.
///
/// iOS only reports a screenshot after the fact and cannot stop it, so the
/// app treats this as best effort. Nothing here reads the picture.
final class ScreenCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var wasCaptured = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = ScreenCapturePlugin()
    let methods = FlutterMethodChannel(
      name: "wecord/screen_capture", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: methods)
    let events = FlutterEventChannel(
      name: "wecord/screen_capture/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "isCaptured" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(ScreenCapturePlugin.isCaptured())
  }

  /// Whether any of the app's screens is being recorded, mirrored or cast.
  private static func isCaptured() -> Bool {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if scenes.isEmpty {
      return UIScreen.main.isCaptured
    }
    return scenes.contains { $0.screen.isCaptured }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    wasCaptured = ScreenCapturePlugin.isCaptured()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    center.addObserver(
      self, selector: #selector(captureChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    sink = nil
    return nil
  }

  @objc private func screenshotTaken() {
    sink?("screenshot")
  }

  @objc private func captureChanged() {
    let captured = ScreenCapturePlugin.isCaptured()
    if captured == wasCaptured {
      return
    }
    wasCaptured = captured
    sink?(captured ? "recording_started" : "recording_stopped")
  }
}
