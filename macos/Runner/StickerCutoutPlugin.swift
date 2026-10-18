import CoreImage
import FlutterMacOS
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Cuts the subject out of a picture on the device with Apple Vision (channel
/// `wecord/sticker_cutout`), for personal stickers. The picture never leaves
/// the device.
///
/// * `isAvailable` → bool: whether this OS has
///   `VNGenerateForegroundInstanceMaskRequest` (iOS 17, macOS 14).
/// * `cutOut {bytes}` → `{bytes: PNG, width, height}`: the foreground
///   instances of the picture, cropped to them, on a transparent background.
///   Fails with `unsupported` (older OS), `unreadable` (not a picture the
///   system can open), `noSubject` (the request found nothing) or `failed`.
final class StickerCutoutPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "wecord.sticker_cutout", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "wecord/sticker_cutout", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(StickerCutoutPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      if #available(macOS 14.0, *) {
        result(true)
      } else {
        result(false)
      }
    case "cutOut":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "unreadable", message: "No picture", details: nil))
        return
      }
      let data = bytes.data
      queue.async {
        let outcome: Any
        if #available(macOS 14.0, *) {
          outcome = StickerCutoutPlugin.cutOut(data: data)
        } else {
          outcome = FlutterError(code: "unsupported", message: "Needs macOS 14", details: nil)
        }
        DispatchQueue.main.async { result(outcome) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The picture as upright pixels (its EXIF orientation applied).
  static func upright(data: Data) -> CIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return nil
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let raw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
    return CIImage(cgImage: image).oriented(forExifOrientation: raw)
  }

  @available(macOS 14.0, *)
  static func cutOut(data: Data) -> Any {
    guard let input = upright(data: data) else {
      return FlutterError(code: "unreadable", message: "Not a picture", details: nil)
    }
    let context = CIContext(options: [.useSoftwareRenderer: false])
    // Vision takes the pixels; the oriented CIImage is rendered once.
    guard let cgInput = context.createCGImage(input, from: input.extent) else {
      return FlutterError(code: "unreadable", message: "Not a picture", details: nil)
    }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgInput, options: [:])
    do {
      try handler.perform([request])
      guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
        return FlutterError(code: "noSubject", message: "No subject found", details: nil)
      }
      let masked = try observation.generateMaskedImage(
        ofInstances: observation.allInstances,
        from: handler,
        croppedToInstancesExtent: true)
      let image = CIImage(cvPixelBuffer: masked)
      guard
        let output = context.createCGImage(
          image, from: image.extent, format: .RGBA8,
          colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
      else {
        return FlutterError(code: "failed", message: "Could not draw the result", details: nil)
      }
      guard let png = StickerCutoutPlugin.png(from: output) else {
        return FlutterError(code: "failed", message: "Could not encode the result", details: nil)
      }
      return [
        "bytes": FlutterStandardTypedData(bytes: png),
        "width": output.width,
        "height": output.height,
      ]
    } catch {
      return FlutterError(code: "failed", message: error.localizedDescription, details: nil)
    }
  }

  static func png(from image: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
