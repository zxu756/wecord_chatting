import AVFoundation
import FlutterMacOS

/// The system's Portrait video effect (background blur), which macOS applies
/// to the camera for every app that uses it once the user turns it on in
/// the menu bar's Video Effects. Apps can't switch it on themselves: they can
/// open the system's video effects and read whether it is on (channel
/// `wecord/video_effects`):
///
/// * `status` → `{supported, enabled}`: whether a camera here offers the
///   effect, and whether the user has it on.
/// * `show` → Bool: opens the system's video effects.
final class VideoEffectsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "wecord/video_effects", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(VideoEffectsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(VideoEffectsPlugin.status())
    case "show":
      result(VideoEffectsPlugin.showVideoEffects())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func status() -> [String: Bool] {
    guard #available(macOS 12.0, *) else {
      return ["supported": false, "enabled": false]
    }
    let camera = AVCaptureDevice.default(for: .video)
    let supported = camera?.formats.contains { $0.isPortraitEffectSupported } ?? false
    return ["supported": supported, "enabled": AVCaptureDevice.isPortraitEffectEnabled]
  }

  static func showVideoEffects() -> Bool {
    guard #available(macOS 12.0, *) else {
      return false
    }
    AVCaptureDevice.showSystemUserInterface(.videoEffects)
    return true
  }
}
