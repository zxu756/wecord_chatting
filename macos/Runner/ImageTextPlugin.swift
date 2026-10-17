import FlutterMacOS
import Foundation
import ImageIO
import Vision

/// Reads the text in a picture on the device with Apple Vision (channel
/// `wecord/image_text`). The picture never leaves the device.
///
/// * `recognize {path, languages}` → `{lines: [{text, confidence}], languages}`
///   (the lines in the order Vision reports them, top to bottom). `languages`
///   are Vision language codes (`zh-Hans`, `zh-Hant`, `en-US`); the ones this
///   OS can't read are left out, and what was used is answered back. Fails
///   with `unreadable` (not a picture the system can open) or `failed`.
///
/// Chinese needs Vision's third revision (iOS 16, macOS 13); on older systems
/// the request still runs, for English.
final class ImageTextPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "wecord.image_text", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "wecord/image_text", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(ImageTextPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let path = args["path"] as? String else {
      result(FlutterError(code: "unreadable", message: "No picture file", details: nil))
      return
    }
    let languages = args["languages"] as? [String] ?? ["zh-Hans", "zh-Hant", "en-US"]
    queue.async {
      let outcome = ImageTextPlugin.recognize(path: path, languages: languages)
      DispatchQueue.main.async { result(outcome) }
    }
  }

  /// The picture's pixels and the way up it is meant to be viewed (from
  /// its EXIF orientation).
  static func load(path: String) -> (CGImage, CGImagePropertyOrientation)? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0,
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return nil
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let raw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
    return (image, CGImagePropertyOrientation(rawValue: raw) ?? .up)
  }

  /// [wanted] without what the request can't read here.
  static func usable(_ wanted: [String], for request: VNRecognizeTextRequest) -> [String] {
    guard let supported = try? request.supportedRecognitionLanguages() else {
      return wanted
    }
    let readable = wanted.filter { supported.contains($0) }
    // Better something than nothing: let Vision pick its own default.
    return readable
  }

  static func recognize(path: String, languages: [String]) -> Any {
    guard let (image, orientation) = load(path: path) else {
      return FlutterError(code: "unreadable", message: "Not a picture", details: nil)
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let used = usable(languages, for: request)
    if !used.isEmpty {
      request.recognitionLanguages = used
    }
    do {
      let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
      try handler.perform([request])
    } catch {
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
    var lines: [[String: Any]] = []
    for observation in request.results ?? [] {
      if let best = observation.topCandidates(1).first {
        lines.append(["text": best.string, "confidence": Double(best.confidence)])
      }
    }
    return ["lines": lines, "languages": request.recognitionLanguages]
  }
}
