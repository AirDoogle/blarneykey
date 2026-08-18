import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // show in the Dock and ⌘-Tab; the menu-bar item stays too
app.run()
