import AVFoundation
import Flutter
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
      name: "wecord/transcribe", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TranscribePlugin(), channel: channel)
    VoiceInputPlugin.register(with: registrar)
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
    if #available(iOS 16.0, *) {
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

// MARK: - Live dictation

/// Speak to type: live speech recognition of the microphone, with partial
/// results as the person talks (channels `wecord/voice_input` and
/// `wecord/voice_input/events`). The system recognizer (`SFSpeechRecognizer`)
/// is fed by an `AVAudioEngine` tap. It runs on the device whenever the
/// language supports that; Apple's servers only when Dart says `allowServer`
/// (the app asks the person first).
///
/// * `capabilities {locale}` → `{supported, available, onDevice, locale,
///   authorization, microphone}`. Never asks for permission.
/// * `start {locale, allowServer}` → null once listening. Asks for speech
///   recognition and microphone permission the first time. Fails with
///   `unsupported_locale`, `unavailable`, `needs_server`, `not_authorized`
///   (speech recognition), `mic_denied`, `busy` or `failed`.
/// * `stop` ends the audio; the recognizer then reports its last result.
/// * `cancel` throws the session away.
///
/// Events on the event channel (maps with a `type`): `partial {text}` and
/// `final {text}` carry everything recognized in this session so far;
/// `level {value}` (0...1) drives the waveform; `error {code}`; `end` closes
/// the session (always the last event of one).
final class VoiceInputPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var session = 0
  private var running = false
  private var lastLevel = Date.distantPast
  private var configObserver: NSObjectProtocol?
  #if os(iOS)
    private var previousCategory: AVAudioSession.Category?
    private var previousMode: AVAudioSession.Mode?
    private var previousOptions: AVAudioSession.CategoryOptions?
  #endif

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = VoiceInputPlugin()
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "wecord/voice_input", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    let events = FlutterEventChannel(
      name: "wecord/voice_input/events", binaryMessenger: messenger)
    events.setStreamHandler(plugin)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    // Nobody listens any more: stop the microphone.
    teardown()
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let locale = args["locale"] as? String ?? ""
    switch call.method {
    case "capabilities":
      result(VoiceInputPlugin.capabilities(locale: locale))
    case "start":
      start(locale: locale, allowServer: args["allowServer"] as? Bool ?? false, result: result)
    case "stop":
      request?.endAudio()
      stopEngine()
      result(nil)
    case "cancel":
      teardown()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Capabilities

  static func microphoneName() -> String {
    #if os(iOS)
      if #available(iOS 17.0, *) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "authorized"
        case .denied: return "denied"
        default: return "notDetermined"
        }
      }
      switch AVAudioSession.sharedInstance().recordPermission {
      case .granted: return "authorized"
      case .denied: return "denied"
      default: return "notDetermined"
      }
    #else
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized: return "authorized"
      case .denied: return "denied"
      case .restricted: return "restricted"
      default: return "notDetermined"
      }
    #endif
  }

  static func capabilities(locale: String) -> [String: Any] {
    let authorization = TranscribePlugin.authorizationName(
      SFSpeechRecognizer.authorizationStatus())
    guard let recognizer = TranscribePlugin.recognizer(for: [locale]) else {
      return [
        "supported": false, "available": false, "onDevice": false, "locale": "",
        "authorization": authorization, "microphone": microphoneName(),
      ]
    }
    return [
      "supported": true,
      "available": recognizer.isAvailable,
      "onDevice": recognizer.supportsOnDeviceRecognition,
      "locale": recognizer.locale.identifier,
      "authorization": authorization,
      "microphone": microphoneName(),
    ]
  }

  // MARK: Permissions

  private func requestSpeech(_ done: @escaping (Bool) -> Void) {
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

  private func requestMicrophone(_ done: @escaping (Bool) -> Void) {
    #if os(iOS)
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission { granted in
          DispatchQueue.main.async { done(granted) }
        }
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async { done(granted) }
        }
      }
    #else
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { done(granted) }
      }
    #endif
  }

  // MARK: Listening

  private func emit(_ event: [String: Any]) {
    if Thread.isMainThread {
      sink?(event)
    } else {
      DispatchQueue.main.async { [weak self] in self?.sink?(event) }
    }
  }

  private func start(locale: String, allowServer: Bool, result: @escaping FlutterResult) {
    if running {
      result(FlutterError(code: "busy", message: "Already listening", details: nil))
      return
    }
    guard let recognizer = TranscribePlugin.recognizer(for: [locale]) else {
      result(
        FlutterError(
          code: "unsupported_locale", message: "No speech recognizer for this language",
          details: nil))
      return
    }
    guard recognizer.isAvailable else {
      result(
        FlutterError(
          code: "unavailable", message: "Speech recognition is not available now", details: nil))
      return
    }
    let onDevice = recognizer.supportsOnDeviceRecognition
    if !onDevice && !allowServer {
      result(
        FlutterError(
          code: "needs_server", message: "This language can't be recognized on the device",
          details: nil))
      return
    }
    running = true
    requestSpeech { [weak self] speechOk in
      guard let self = self else { return }
      guard speechOk else {
        self.running = false
        result(
          FlutterError(
            code: "not_authorized", message: "Speech recognition is not allowed", details: nil))
        return
      }
      self.requestMicrophone { micOk in
        guard micOk else {
          self.running = false
          result(
            FlutterError(code: "mic_denied", message: "The microphone is not allowed", details: nil)
          )
          return
        }
        do {
          try self.begin(recognizer: recognizer, onDevice: onDevice)
          result(nil)
        } catch {
          self.teardown()
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func begin(recognizer: SFSpeechRecognizer, onDevice: Bool) throws {
    session += 1
    let mine = session
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = onDevice
    if #available(iOS 16.0, macOS 13.0, *) {
      request.addsPunctuation = true
    }
    self.request = request

    #if os(iOS)
      let audioSession = AVAudioSession.sharedInstance()
      previousCategory = audioSession.category
      previousMode = audioSession.mode
      previousOptions = audioSession.categoryOptions
      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    #endif

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw NSError(
        domain: "wecord.voice_input", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No microphone"])
    }
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self = self else { return }
      self.request?.append(buffer)
      self.reportLevel(buffer)
    }
    engine.prepare()
    try engine.start()
    configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      // The microphone changed (a headset): end this session; Dart starts
      // another one while the person is still dictating.
      self?.request?.endAudio()
      self?.stopEngine()
    }

    task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
      DispatchQueue.main.async {
        guard let self = self, mine == self.session else { return }
        if let recognition = recognition {
          let text = recognition.bestTranscription.formattedString
          if recognition.isFinal {
            self.emit(["type": "final", "text": text])
            self.finishSession(mine)
            return
          }
          self.emit(["type": "partial", "text": text])
        }
        if let error = error as NSError? {
          // A silent stretch ends the task with 1110 ("No speech detected"):
          // an ordinary end, not a failure.
          let silent = error.code == 1110 || error.localizedDescription.contains("No speech")
          let cancelled = error.code == 216 || error.code == 301
          if !silent && !cancelled && recognition == nil {
            self.emit(["type": "error", "code": "failed", "message": error.localizedDescription])
          }
          self.finishSession(mine)
        }
      }
    }
  }

  private func reportLevel(_ buffer: AVAudioPCMBuffer) {
    let now = Date()
    guard now.timeIntervalSince(lastLevel) > 0.05,
      let samples = buffer.floatChannelData?[0]
    else { return }
    lastLevel = now
    let count = Int(buffer.frameLength)
    guard count > 0 else { return }
    var sum: Float = 0
    for index in 0..<count { sum += samples[index] * samples[index] }
    let rms = (sum / Float(count)).squareRoot()
    // -50 dB (quiet room) ... -10 dB (loud) mapped to 0...1.
    let decibels = 20 * log10(max(rms, 0.000_01))
    let value = max(0, min(1, (decibels + 50) / 40))
    emit(["type": "level", "value": Double(value)])
  }

  private func stopEngine() {
    if engine.isRunning {
      engine.stop()
    }
    engine.inputNode.removeTap(onBus: 0)
    if let observer = configObserver {
      NotificationCenter.default.removeObserver(observer)
      configObserver = nil
    }
  }

  /// The recognizer is done (a final result, an error, or silence).
  private func finishSession(_ mine: Int) {
    guard mine == session else { return }
    teardown()
    emit(["type": "end"])
  }

  /// Releases the microphone and the recognizer without any more events.
  private func teardown() {
    session += 1
    stopEngine()
    request?.endAudio()
    request = nil
    task?.cancel()
    task = nil
    running = false
    #if os(iOS)
      if let category = previousCategory, let mode = previousMode,
        let options = previousOptions
      {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(category, mode: mode, options: options)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      }
      previousCategory = nil
      previousMode = nil
      previousOptions = nil
    #endif
  }
}
