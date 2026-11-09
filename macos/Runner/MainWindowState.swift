import Cocoa

enum MainWindowState {
  static func restore(_ window: NSWindow, origin: NSPoint,
                      name: String = "FreeSceneMainWindow") {
    window.minSize = NSSize(width: 900, height: 650)
    window.setFrame(NSRect(origin: origin, size: NSSize(width: 1280, height: 860)), display: true)
    // Restore before enabling autosave so the launch defaults cannot replace
    // the user's frame. AppKit handles changes to the available screens.
    window.setFrameUsingName(name, force: true)
    window.setFrameAutosaveName(name)
  }
}
