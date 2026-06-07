import AppKit
import SwiftUI

/// Owns the Settings window for the accessory app. The window is created lazily
/// and reused; `isReleasedWhenClosed = false` keeps it alive across close/reopen.
@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "HermesVoice Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // Accessory apps aren't active by default; bring ourselves forward so the
        // window can take key focus (needed for the hotkey recorder to receive
        // key events).
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
