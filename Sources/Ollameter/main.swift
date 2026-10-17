import AppKit

let coordinator = AppCoordinator()
NSApplication.shared.delegate = coordinator
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
