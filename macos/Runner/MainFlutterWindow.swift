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

    RegisterGeneratedPlugins(registry: flutterViewController)
    QuickLookPlugin.register(
      with: flutterViewController.registrar(forPlugin: "QuickLookPlugin"))
    QuickLookPlugin.shared?.attach(window: self)

    super.awakeFromNib()
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
