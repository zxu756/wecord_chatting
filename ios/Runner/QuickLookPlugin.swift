import AVFoundation
import Flutter
import QuickLook
import UIKit

/// The app's native side for files (channel `wecord/quicklook`):
///
/// * `canPreview(path)` → Bool: whether Quick Look reads the local file.
/// * `preview(path, title)`: presents QLPreviewController; answers when it
///   is dismissed.
/// * `openIn(path, x?, y?, width?, height?)` → Bool: the "Open in…" menu.
/// * `exportCopy(path, name)` → Bool: a document picker to save a copy;
///   false when cancelled.
/// * `videoPoster(url, maxSize)` → JPEG bytes of an early frame (local or
///   remote video), or nil.
final class QuickLookPlugin: NSObject, FlutterPlugin {
  private var previewItem: PreviewItem?
  private var previewResult: FlutterResult?
  private var exportResult: FlutterResult?
  private var interaction: UIDocumentInteractionController?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "wecord/quicklook", binaryMessenger: registrar.messenger())
    let instance = QuickLookPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "canPreview":
      guard let url = Self.fileURL(args["path"]) else {
        result(false)
        return
      }
      result(QLPreviewController.canPreview(url as NSURL))
    case "preview":
      guard let url = Self.fileURL(args["path"]) else {
        result(FlutterError(code: "not_found", message: "No such file", details: nil))
        return
      }
      preview(url: url, title: args["title"] as? String, result: result)
    case "openIn":
      guard let url = Self.fileURL(args["path"]) else {
        result(false)
        return
      }
      openIn(url: url, args: args, result: result)
    case "exportCopy":
      guard let url = Self.fileURL(args["path"]) else {
        result(false)
        return
      }
      exportCopy(url: url, result: result)
    case "videoPoster":
      guard let string = args["url"] as? String, let url = URL(string: string) else {
        result(nil)
        return
      }
      let maxSize = (args["maxSize"] as? NSNumber)?.doubleValue ?? 480
      Self.videoPoster(url: url, maxSize: maxSize) { data in
        DispatchQueue.main.async {
          result(data.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func fileURL(_ value: Any?) -> URL? {
    guard let path = value as? String, FileManager.default.fileExists(atPath: path) else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window =
      scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? scenes.flatMap { $0.windows }.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }

  // MARK: Quick Look

  private func preview(url: URL, title: String?, result: @escaping FlutterResult) {
    guard let host = Self.topViewController() else {
      result(FlutterError(code: "no_window", message: "Nothing to present from", details: nil))
      return
    }
    previewResult?(nil)
    previewItem = PreviewItem(url: url, title: title)
    previewResult = result
    let controller = QLPreviewController()
    controller.dataSource = self
    controller.delegate = self
    controller.modalPresentationStyle = .fullScreen
    host.present(controller, animated: true)
  }

  // MARK: Open in

  private func openIn(url: URL, args: [String: Any], result: @escaping FlutterResult) {
    guard let host = Self.topViewController(), let view = host.view else {
      result(false)
      return
    }
    let controller = UIDocumentInteractionController(url: url)
    controller.name = url.lastPathComponent
    interaction = controller
    var rect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    if let x = (args["x"] as? NSNumber)?.doubleValue,
      let y = (args["y"] as? NSNumber)?.doubleValue,
      let width = (args["width"] as? NSNumber)?.doubleValue,
      let height = (args["height"] as? NSNumber)?.doubleValue
    {
      rect = CGRect(x: x, y: y, width: width, height: height)
    }
    result(controller.presentOpenInMenu(from: rect, in: view, animated: true))
  }

  // MARK: Save a copy

  private func exportCopy(url: URL, result: @escaping FlutterResult) {
    guard let host = Self.topViewController() else {
      result(false)
      return
    }
    exportResult?(false)
    exportResult = result
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = self
    host.present(picker, animated: true)
  }

  // MARK: Video poster

  static func videoPoster(url: URL, maxSize: Double, completion: @escaping (Data?) -> Void) {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxSize, height: maxSize)
    generator.requestedTimeToleranceBefore = .positiveInfinity
    generator.requestedTimeToleranceAfter = .positiveInfinity
    let time = CMTime(seconds: 0.5, preferredTimescale: 600)
    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
      _, image, _, _, _ in
      guard let image = image else {
        completion(nil)
        return
      }
      completion(UIImage(cgImage: image).jpegData(compressionQuality: 0.82))
    }
  }
}

extension QuickLookPlugin: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewItem == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
    -> QLPreviewItem
  {
    previewItem!
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    previewItem = nil
    previewResult?(nil)
    previewResult = nil
  }
}

extension QuickLookPlugin: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    exportResult?(true)
    exportResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    exportResult?(false)
    exportResult = nil
  }
}

/// A local file with the name it had on the sender's device.
final class PreviewItem: NSObject, QLPreviewItem {
  let url: URL
  let title: String?

  init(url: URL, title: String?) {
    self.url = url
    self.title = title
  }

  var previewItemURL: URL? { url }
  var previewItemTitle: String? { title ?? url.lastPathComponent }
}
