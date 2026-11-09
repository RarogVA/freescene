import Cocoa

@main
enum WindowStateTest {
  static func main() {
    _ = NSApplication.shared
    // A unique autosave key is supplied by the runner. No FreeScene defaults
    // or account/profile files are read or modified.
    let name = CommandLine.arguments[1]
    let mode = CommandLine.arguments[2]
    let window = NSWindow(contentRect: NSRect(x: 30, y: 30, width: 800, height: 600),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    MainWindowState.restore(window, origin: NSPoint(x: 30, y: 30), name: name)
    precondition(window.minSize == NSSize(width: 900, height: 650))
    if mode == "save" {
      window.orderFront(nil)
      window.setFrame(NSRect(x: 40, y: 50, width: 1040, height: 720), display: true)
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
      window.close()
      UserDefaults.standard.synchronize()
    } else {
      precondition(window.frame.size == NSSize(width: 1040, height: 720),
                   "Saved size was not restored across processes: \(window.frame)")
      window.setFrameAutosaveName("")
      NSWindow.removeFrame(usingName: name)
      UserDefaults.standard.synchronize()
    }
    print("Window state \(mode): passed")
  }
}
