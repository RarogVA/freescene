import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var voiceInput: DesktopVoiceInput?
  private var pressureMonitor: Any?
  private var forceClickSent = false

  deinit {
    if let monitor = pressureMonitor { NSEvent.removeMonitor(monitor) }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    MainWindowState.restore(self, origin: windowFrame.origin)
    self.title = "FreeScene"
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    FSNativeBridge.register(with: flutterViewController, window: self)
    voiceInput = DesktopVoiceInput(messenger: flutterViewController.engine.binaryMessenger, window: self)

    // Flutter exposes secondary clicks, but AppKit owns Force Touch stages.
    let contextMenu = FlutterMethodChannel(
      name: "freescene/context_menu", binaryMessenger: flutterViewController.engine.binaryMessenger)
    pressureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.pressure, .leftMouseDown, .leftMouseUp]) {
      [weak self, weak flutterViewController] event in
      guard let self = self, event.window === self,
            let view = flutterViewController?.view else { return event }
      if event.type == .leftMouseDown || event.type == .leftMouseUp || (event.type == .pressure && event.stage == 0) {
        self.forceClickSent = false
      }
      if event.type == .pressure && event.stage == 2 && !self.forceClickSent {
        self.forceClickSent = true
        let point = view.convert(event.locationInWindow, from: nil)
        contextMenu.invokeMethod("forceClick", arguments: [
          "x": point.x, "y": view.isFlipped ? point.y : view.bounds.height - point.y,
        ])
      }
      return event
    }

    super.awakeFromNib()
  }
}
