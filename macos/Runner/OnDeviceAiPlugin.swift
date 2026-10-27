import Foundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// Summaries, rewrites and translations with the system's own language model
/// (Apple Intelligence, Foundation Models), on the device (channel
/// `wecord/on_device_ai`). Nothing is sent anywhere. The same file is in the
/// iOS and macOS apps; the work is in `OnDeviceAiCore.swift`.
///
/// * `availability` → `{available, reason}`; `reason` (when not available) is
///   `os_too_old`, `device_not_eligible`, `not_enabled`, `model_not_ready` or
///   `unavailable`. Never fails and never downloads anything.
/// * `summarize {lines, language, recent, merge}` → `{text}` (bullet points).
/// * `rewrite {mode, text}` → `{text}` (`mode` is fix, shorter, polite or
///   formal).
/// * `translate {text, target}` → `{text}`.
///
/// A request fails with the code `unavailable` (`message` is the reason
/// above), `context_too_long`, `refused`, `unsupported_language`, `busy` or
/// `failed`. The app only sends what the person asked to process, in pieces
/// that fit the model's small context.
final class OnDeviceAiPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "wecord/on_device_ai", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(OnDeviceAiPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "availability":
      let state = OnDeviceAiCore.availability()
      result(["available": state.available, "reason": state.reason])
    case "summarize":
      run(result) {
        try await OnDeviceAiCore.summarize(
          lines: args["lines"] as? [String] ?? [],
          language: args["language"] as? String ?? "en",
          recent: args["recent"] as? Bool ?? false,
          merge: args["merge"] as? Bool ?? false)
      }
    case "rewrite":
      run(result) {
        try await OnDeviceAiCore.rewrite(
          mode: args["mode"] as? String ?? "fix", text: args["text"] as? String ?? "")
      }
    case "translate":
      run(result) {
        try await OnDeviceAiCore.translate(
          text: args["text"] as? String ?? "", target: args["target"] as? String ?? "en")
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func run(
    _ result: @escaping FlutterResult, _ work: @escaping () async throws -> String
  ) {
    Task {
      let outcome: Any
      do {
        outcome = ["text": try await work()]
      } catch let failure as OnDeviceAiFailure {
        outcome = FlutterError(code: failure.code, message: failure.message, details: nil)
      } catch {
        outcome = FlutterError(code: "failed", message: error.localizedDescription, details: nil)
      }
      await MainActor.run { result(outcome) }
    }
  }
}
