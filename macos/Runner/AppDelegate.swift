import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationRequested = false
  @objc func openVideo(_ sender: Any?) { FSNativeBridge.openLocalVideo() }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    FSNativeBridge.showMainWindow()
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationRequested { return .terminateLater }
    terminationRequested = true
    FSNativeBridge.shutdown { sender.reply(toApplicationShouldTerminate: true) }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
