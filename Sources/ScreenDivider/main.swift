import AppKit

// Hold delegate as a global so it's never released
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate

// Prevent quit when last window closes
app.run()
