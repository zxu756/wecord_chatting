import AVFoundation
import FlutterMacOS
import Speech

/// Turns a voice message's audio file into text with the system's speech
/// recognizer (channel `wecord/transcribe`). On-device whenever the device
/// supports it for the language; Apple's servers only when the caller says
/// `allowServer` (the app asks the person first).
///
/// * `capabilities {locales}` → `{supported, available, onDevice, locale,
///   authorization}`: whether a recognizer exists for the first usable locale
///   (the list is tried in order, then the device language), whether it is
///   available right now, whether it can run on the device, and the speech
///   recognition permission (`notDetermined`, `authorized`, `denied`,
///   `restricted`). Never asks for permission.
/// * `transcribe {path, locales, allowServer}` → `{text, onDevice, locale}`.
///   Asks for permission the first time. Fails with `not_authorized`,
///   `unsupported_locale`, `unavailable`, `needs_server` (the language can't
///   run on the device and `allowServer` is false), `unreadable` (not audio
///   the system can open), `no_speech` or `failed`.
final class TranscribePlugin: NSObject, FlutterPlugin {
  private var running: [ObjectIdentifier: SFSpeechRecognitionTask] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "wecord/transcribe", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(TranscribePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let locales = args["locales"] as? [String] ?? []
    switch call.method {
    case "capabilities":
      result(TranscribePlugin.capabilities(locales: locales))
    case "transcribe":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "unreadable", message: "No audio file", details: nil))
        return
      }
      transcribe(
        url: URL(fileURLWithPath: path), locales: locales,
        allowServer: args["allowServer"] as? Bool ?? false, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Capabilities

  /// The recognizer for the first of [locales] that has one, then for the
  /// device's own language.
  static func recognizer(for locales: [String]) -> SFSpeechRecognizer? {
    var candidates = locales.map { Locale(identifier: $0) }
    candidates.append(Locale.current)
    for locale in candidates {
      if let recognizer = SFSpeechRecognizer(locale: locale) {
        return recognizer
      }
    }
    return nil
  }

  static func authorizationName(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "notDetermined"
    }
  }

  static func capabilities(locales: [String]) -> [String: Any] {
    let authorization = authorizationName(SFSpeechRecognizer.authorizationStatus())
    guard let recognizer = recognizer(for: locales) else {
      return [
        "supported": false, "available": false, "onDevice": false,
        "locale": "", "authorization": authorization,
      ]
    }
    return [
      "supported": true,
      "available": recognizer.isAvailable,
      "onDevice": recognizer.supportsOnDeviceRecognition,
      "locale": recognizer.locale.identifier,
      "authorization": authorization,
    ]
  }

  // MARK: - Transcribing

  private func requestAuthorization(_ done: @escaping (Bool) -> Void) {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      done(true)
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async { done(status == .authorized) }
      }
    default:
      done(false)
    }
  }

  private func transcribe(
    url: URL, locales: [String], allowServer: Bool, result: @escaping FlutterResult
  ) {
    guard let recognizer = TranscribePlugin.recognizer(for: locales) else {
      result(
        FlutterError(
          code: "unsupported_locale", message: "No speech recognizer for this language",
          details: nil))
      return
    }
    requestAuthorization { [weak self] authorized in
      guard let self = self else { return }
      guard authorized else {
        result(
          FlutterError(
            code: "not_authorized", message: "Speech recognition is not allowed", details: nil))
        return
      }
      guard recognizer.isAvailable else {
        result(
          FlutterError(
            code: "unavailable", message: "Speech recognition is not available now",
            details: nil))
        return
      }
      let onDevice = recognizer.supportsOnDeviceRecognition
      if !onDevice && !allowServer {
        result(
          FlutterError(
            code: "needs_server",
            message: "This language can't be recognized on the device", details: nil))
        return
      }
      // Fails for anything the system can't open (a WebM or Ogg file, say),
      // before the recognizer is started.
      guard let file = try? AVAudioFile(forReading: url), file.length > 0 else {
        result(
          FlutterError(code: "unreadable", message: "The audio can't be read", details: nil))
        return
      }
      self.recognize(
        url: url, recognizer: recognizer, onDevice: onDevice, result: result)
    }
  }

  private func recognize(
    url: URL, recognizer: SFSpeechRecognizer, onDevice: Bool, result: @escaping FlutterResult
  ) {
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = onDevice
    request.shouldReportPartialResults = false
    if #available(macOS 13.0, *) {
      request.addsPunctuation = true
    }
    var finished = false
    var task: SFSpeechRecognitionTask?
    // The recognizer answers on its own queue and the timeout on the main
    // one; everything is settled on the main queue, once.
    func finish(_ value: Any?) {
      DispatchQueue.main.async {
        if finished { return }
        finished = true
        if let task = task {
          self.running.removeValue(forKey: ObjectIdentifier(task))
          task.cancel()
        }
        result(value)
      }
    }
    task = recognizer.recognitionTask(with: request) { recognition, error in
      if let recognition = recognition, recognition.isFinal {
        let text = recognition.bestTranscription.formattedString
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
          finish(FlutterError(code: "no_speech", message: "No speech found", details: nil))
        } else {
          finish([
            "text": text, "onDevice": onDevice, "locale": recognizer.locale.identifier,
          ])
        }
        return
      }
      if let error = error as NSError? {
        // Speech recognition reports a silent recording as error 1110 (or
        // "No speech detected").
        let silent = error.code == 1110 || error.localizedDescription.contains("No speech")
        let text = recognition?.bestTranscription.formattedString
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
          finish([
            "text": text, "onDevice": onDevice, "locale": recognizer.locale.identifier,
          ])
        } else if silent {
          finish(FlutterError(code: "no_speech", message: "No speech found", details: nil))
        } else {
          finish(
            FlutterError(
              code: "failed", message: error.localizedDescription, details: nil))
        }
      }
    }
    if let task = task {
      running[ObjectIdentifier(task)] = task
    }
    // A recognition that never answers is given up on.
    DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
      finish(FlutterError(code: "failed", message: "Timed out", details: nil))
    }
  }
}
