import AppKit

// `BlarneyKey --transcribe clip.wav` runs one file through the real engine and exits.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--transcribe" {
    SelfTest.run(path: CommandLine.arguments[2])
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // show in the Dock and ⌘-Tab; the menu-bar item stays too
app.run()
