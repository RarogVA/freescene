import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    MainWindowState.restore(self, origin: windowFrame.origin)
    self.title = "FreeScene"
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    FSNativeBridge.register(with: flutterViewController, window: self)

    super.awakeFromNib()
  }
}
