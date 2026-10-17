import AppKit

let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
