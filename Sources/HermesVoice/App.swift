import AppKit

@main
struct HermesVoiceApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate

        // Install a real main menu. An accessory app has no menu bar, but the
        // menu's key equivalents still drive the standard Edit responder chain —
        // this is what makes Cmd+Z/X/C/V/A work inside the input field, and the
        // Chat menu's ⌘N / ⌘F shortcuts work while the panel is key.
        app.mainMenu = makeMainMenu(target: delegate)

        // Create status bar item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "HermesVoice")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        let newChatItem = NSMenuItem(title: "New Chat", action: #selector(AppDelegate.menuBarNewChat), keyEquivalent: "")
        newChatItem.target = delegate
        menu.addItem(newChatItem)
        let activateItem = NSMenuItem(title: "Activate (⌃⇧H)", action: #selector(AppDelegate.togglePanel), keyEquivalent: "")
        activateItem.target = delegate
        menu.addItem(activateItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusItem.menu = menu

        delegate.statusItem = statusItem

        app.run()
    }

    /// Builds the application main menu with App + Edit menus. The Edit items use
    /// the standard first-responder selectors so they route through the field
    /// editor's responder chain (giving working Undo/Cut/Copy/Paste/Select All).
    private static func makeMainMenu(target: AppDelegate) -> NSMenu {
        let appName = "HermesVoice"
        let mainMenu = NSMenu()

        // App menu (first item; its title is shown as the app name on a regular app).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Edit menu — standard selectors, dispatched to the first responder.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        // Paste routes through a "smart paste": an image on the pasteboard is
        // attached to the message; otherwise it falls through to the normal text
        // paste in the field editor.
        let pasteItem = editMenu.addItem(withTitle: "Paste",
                                         action: #selector(AppDelegate.smartPaste(_:)),
                                         keyEquivalent: "v")
        pasteItem.target = target
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Chat menu — app-level conversation actions. Targeted at the delegate so
        // their key equivalents fire whenever the panel is key.
        let chatMenuItem = NSMenuItem()
        mainMenu.addItem(chatMenuItem)
        let chatMenu = NSMenu(title: "Chat")
        chatMenuItem.submenu = chatMenu
        let newChatItem = chatMenu.addItem(withTitle: "New Chat",
                                           action: #selector(AppDelegate.newChat),
                                           keyEquivalent: "n")
        newChatItem.target = target
        let searchItem = chatMenu.addItem(withTitle: "Search History",
                                          action: #selector(AppDelegate.searchHistory),
                                          keyEquivalent: "f")
        searchItem.target = target

        return mainMenu
    }
}
