import AVFoundation
import Cocoa
import FlutterMacOS
import Quartz

/// The app's native side for files (channel `wecord/quicklook`):
///
/// * `canPreview(path)` → Bool: the file exists (the Quick Look panel
///   reads every type the system has a generator for, Office and iWork
///   included).
/// * `preview(path, title)`: opens the Quick Look panel over the window;
///   answers when it closes.
/// * `openIn(path)` → Bool: opens the file in its default app.
/// * `exportCopy(path, name)` → Bool: a save panel; false when cancelled.
/// * `videoPoster(url, maxSize)` → JPEG bytes of an early frame, or nil.
///
/// The panel asks the responder chain who controls it; MainFlutterWindow
/// answers and hands it to [QuickLookPlugin.shared].
final class QuickLookPlugin: NSObject, FlutterPlugin {
  static var shared: QuickLookPlugin?

  private var items: [PreviewItem] = []
  private var previewResult: FlutterResult?
  private weak var window: NSWindow?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "wecord/quicklook", binaryMessenger: registrar.messenger)
    let instance = QuickLookPlugin()
    shared = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func attach(window: NSWindow) {
    self.window = window
  }

  var hasItems: Bool { !items.isEmpty }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "canPreview":
      result(Self.fileURL(args["path"]) != nil)
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
      result(NSWorkspace.shared.open(url))
    case "exportCopy":
      guard let url = Self.fileURL(args["path"]) else {
        result(false)
        return
      }
      exportCopy(url: url, name: args["name"] as? String, result: result)
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

  // MARK: Quick Look panel

  private func preview(url: URL, title: String?, result: @escaping FlutterResult) {
    finishPreview()
    items = [PreviewItem(url: url, title: title)]
    previewResult = result
    window?.makeKeyAndOrderFront(nil)
    guard let panel = QLPreviewPanel.shared() else {
      finishPreview()
      return
    }
    if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
      panel.reloadData()
      panel.currentPreviewItemIndex = 0
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
  }

  func beginControl(_ panel: QLPreviewPanel) {
    panel.dataSource = self
    panel.delegate = self
    panel.reloadData()
  }

  func endControl(_ panel: QLPreviewPanel) {
    panel.dataSource = nil
    panel.delegate = nil
    finishPreview()
  }

  private func finishPreview() {
    items = []
    let result = previewResult
    previewResult = nil
    result?(nil)
  }

  // MARK: Save a copy

  private func exportCopy(url: URL, name: String?, result: @escaping FlutterResult) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name ?? url.lastPathComponent
    panel.canCreateDirectories = true
    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
      .first
    let completion: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK, let target = panel.url else {
        result(false)
        return
      }
      do {
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)
        result(true)
      } catch {
        result(
          FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
      }
    }
    if let window = window {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      completion(panel.runModal())
    }
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
      let rep = NSBitmapImageRep(cgImage: image)
      completion(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]))
    }
  }
}

extension QuickLookPlugin: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    items.count
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    items[index]
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

  var previewItemURL: URL! { url }
  var previewItemTitle: String! { title ?? url.lastPathComponent }
}
