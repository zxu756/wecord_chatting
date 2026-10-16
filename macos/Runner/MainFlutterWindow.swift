import Cocoa
import FlutterMacOS
import Quartz

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app draws under a transparent title bar; the traffic lights sit
    // over the circle rail, which keeps its top 28 points clear.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    self.minSize = NSSize(width: 960, height: 640)
    if self.frame.width < 960 || self.frame.height < 640 {
      self.setContentSize(
        NSSize(
          width: max(self.frame.width, 960),
          height: max(self.frame.height, 640)))
      self.center()
    }

    // Without a title bar, Flutter asks the window to start a drag from its
    // top strip: see MacosWindowDragArea.
    let windowChannel = FlutterMethodChannel(
      name: "wecord/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Pictures and files copied to the pasteboard (a screenshot, files from
    // Finder) for pasting into the chat composer. Text is left to the text
    // field, so a paste of text never turns into an attachment.
    let clipboardChannel = FlutterMethodChannel(
      name: "wecord/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "readFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(MainFlutterWindow.pasteboardFiles())
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    QuickLookPlugin.register(
      with: flutterViewController.registrar(forPlugin: "QuickLookPlugin"))
    QuickLookPlugin.shared?.attach(window: self)

    super.awakeFromNib()
  }

  /// Files (at most 10, each under the chat's 50 MB limit) or the picture on
  /// the general pasteboard, as `{name, bytes}` maps; empty when it holds
  /// plain text instead.
  static func pasteboardFiles() -> [[String: Any]] {
    let limit = 50 * 1024 * 1024
    let pasteboard = NSPasteboard.general
    var files: [[String: Any]] = []
    let urls =
      pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    for url in urls.prefix(10) {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if size > limit { continue }
      if let data = try? Data(contentsOf: url) {
        files.append([
          "name": url.lastPathComponent,
          "bytes": FlutterStandardTypedData(bytes: data),
        ])
      }
    }
    if !files.isEmpty || !urls.isEmpty { return files }

    // Text on the pasteboard (even with a picture beside it, as copying from
    // a web page or a document does) is a text paste.
    if let text = pasteboard.string(forType: .string), !text.isEmpty { return [] }

    var png = pasteboard.data(forType: .png)
    if png == nil, let tiff = pasteboard.data(forType: .tiff) {
      png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
    if let png = png {
      files.append([
        "name": "pasted-image.png",
        "bytes": FlutterStandardTypedData(bytes: png),
      ])
    }
    return files
  }

  // The Quick Look panel asks the responder chain for a controller; the
  // window hands it to QuickLookPlugin while a preview is up.
  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    QuickLookPlugin.shared?.hasItems ?? false
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    QuickLookPlugin.shared?.beginControl(panel)
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    QuickLookPlugin.shared?.endControl(panel)
  }
}
