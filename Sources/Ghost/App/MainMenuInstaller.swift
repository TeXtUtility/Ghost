import AppKit

/// LSUIElement (menu-bar) apps don't get a default Edit menu, which means
/// SwiftUI's TextField / TextEditor inside our popover won't respond to
/// ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z because there's nothing in the responder chain
/// to translate those keystrokes into the corresponding selectors.
///
/// Installing a (hidden) main menu with the standard Edit items fixes that
/// — AppKit routes the keyboard shortcuts via the menu, the actions are
/// nil-targeted, and the responder chain delivers them to the focused
/// NSTextView / NSTextField underneath SwiftUI.
@MainActor
enum MainMenuInstaller {
    static func install() {
        let mainMenu = NSMenu()

        // App menu — needed so ⌘Q quits cleanly.
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Ghost")
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Ghost",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu — the actual fix for paste/copy/cut/select all/undo.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        let undo = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(undo)

        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)

        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",   action: Selector(("cut:")),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",  action: Selector(("copy:")),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: Selector(("paste:")),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All",
                                    action: Selector(("selectAll:")),
                                    keyEquivalent: "a"))

        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}
