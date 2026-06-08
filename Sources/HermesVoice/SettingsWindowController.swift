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
            // The overlay panel lives at `.floating` (OverlayPanel.swift). A plain
            // `.normal` window would always render behind it, so place Settings one
            // band above the overlay to guarantee it sits on top in the Z-order.
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            w.center()
            window = w
        }
        // Accessory apps aren't active by default; bring ourselves forward so the
        // window can take key focus (needed for the hotkey recorder to receive
        // key events) and become the active app on screen.
        NSApp.activate(ignoringOtherApps: true)
        guard let w = window else { return }
        // Re-center on a fresh open and force it to the absolute front of its
        // window level, ahead of the floating overlay, then give it key focus.
        w.orderFrontRegardless()
        w.makeKeyAndOrderFront(nil)
        w.makeKey()
    }
}
