import AppKit

@main
struct HermesVoiceApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate

        // Create status bar item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "HermesVoice")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
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
}
