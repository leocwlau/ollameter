import AppKit

enum ApplicationPasteMenu {
    static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        let pasteAction = NSSelectorFromString("paste:")

        let commandPaste = NSMenuItem(
            title: "Paste",
            action: pasteAction,
            keyEquivalent: "v"
        )
        commandPaste.keyEquivalentModifierMask = [.command]
        menu.addItem(commandPaste)

        let controlPaste = NSMenuItem(
            title: "Paste (Control)",
            action: pasteAction,
            keyEquivalent: "v"
        )
        controlPaste.keyEquivalentModifierMask = [.control]
        menu.addItem(controlPaste)

        return menu
    }

    static func install(into application: NSApplication = .shared) {
        let mainMenu = application.mainMenu ?? NSMenu()
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = makeEditMenu()
        mainMenu.addItem(editMenuItem)
        application.mainMenu = mainMenu
    }
}
