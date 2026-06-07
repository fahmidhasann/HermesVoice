import AppKit
import SwiftUI

/// Hosts the first-run `OnboardingView` in a small centered window. Created
/// lazily and kept alive across close (`isReleasedWhenClosed = false`) so the
/// completion handler can dismiss it cleanly.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private var onFinish: (() -> Void)?

    /// Shows the onboarding flow. `onFinish` runs once when the user completes
    /// or skips it; the window is closed before the callback fires.
    func show(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish

        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(onFinish: { [weak self] in
                self?.finish()
            }))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Welcome to HermesVoice"
            // No close button: the flow is exited only via Skip/Done, so the
            // onboarded flag is always set deliberately (never by an orphaned
            // window close that leaves first-run state half-applied).
            w.styleMask = [.titled, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.center()
            window = w
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.orderOut(nil)
        let callback = onFinish
        onFinish = nil
        callback?()
    }
}
