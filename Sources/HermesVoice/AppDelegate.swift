import AppKit
import SwiftUI
import Carbon
import HermesVoiceKit

extension Notification.Name {
    static let hermesAutoHide = Notification.Name("hermesAutoHide")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var overlayPanel: OverlayPanel?
    var hotKeyManager: HotKeyManager?
    var viewModel = OverlayViewModel()
    private var autoHideObserver: Any?

    // Global monitor that closes the panel when the user clicks anywhere outside
    // of it. Installed only while the panel is fully shown and torn down on hide.
    private var clickOutsideMonitor: Any?

    // The app that was frontmost when the panel opened. Reactivated on close so
    // keyboard focus returns to where the user was working.
    private var previousApp: NSRunningApplication?

    // Secondary debounce — belt-and-suspenders alongside HotKeyManager's.
    // Guarantees that even if two hotkey events slip through (Carbon quirk,
    // app reactivation, etc.) a single physical press only flips the panel once.
    private var toggleDebouncer = Debouncer(interval: 0.12)

    // Path to the lock file for single-instance enforcement.
    nonisolated private static let lockPath = NSString("~/.hermes/hermes_voice.lock").expandingTildeInPath

    // File descriptor for the held flock. Kept open for the whole process
    // lifetime; the OS releases the lock automatically on exit or crash.
    private var lockFD: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Acquire an exclusive lock before anything else; if it fails, another
        // copy is already running and we bow out.
        guard claimSingleInstanceLock() else {
            print("HermesVoice: another instance is already running (lock held), exiting.")
            NSApp.terminate(nil)
            return
        }

        setupOverlayPanel()
        setupHotKey()

        // Listen for auto-hide notification
        autoHideObserver = NotificationCenter.default.addObserver(
            forName: .hermesAutoHide,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hidePanel()
            }
        }

        // Ensure the PID lock is released when the app terminates via any path
        // (Quit menu, Cmd+Q, SIGTERM, crash handler, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cleanupBeforeTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func cleanupBeforeTerminate() {
        releaseSingleInstanceLock()
    }

    deinit {
        // deinit is nonisolated; close the fd directly (releases the flock).
        if lockFD >= 0 { close(lockFD) }
    }

    // MARK: - Single-instance via atomic flock
    //
    // We hold an exclusive `flock` on a lock file for the whole process
    // lifetime. Unlike a read-check-write PID file, `flock(LOCK_EX|LOCK_NB)`
    // is atomic, so two copies launching simultaneously (e.g. launchd
    // RunAtLoad racing a manual `open`) can never both win — the loser sees
    // EWOULDBLOCK and exits. The kernel drops the lock automatically on exit
    // or crash, so there are no stale locks to clean up.

    /// Acquires the exclusive lock. Returns `false` if another instance holds it.
    private func claimSingleInstanceLock() -> Bool {
        let lockPath = Self.lockPath

        // Create parent directory if needed.
        let dir = (lockPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            // Can't open the lock file — fail open so the app still runs. The
            // panel state machine still prevents the "two windows" symptom
            // within a single process.
            print("HermesVoice: warning — could not open lock file (errno \(errno)); proceeding without lock.")
            return true
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            // Another instance holds the lock.
            close(fd)
            return false
        }

        lockFD = fd

        // Record our PID for diagnostics (best-effort; the lock itself is what
        // enforces exclusivity).
        let pidLine = "\(ProcessInfo.processInfo.processIdentifier)\n"
        ftruncate(fd, 0)
        _ = pidLine.withCString { write(fd, $0, strlen($0)) }

        return true
    }

    /// Releases the lock by closing the held descriptor.
    private func releaseSingleInstanceLock() {
        guard lockFD >= 0 else { return }
        close(lockFD)
        lockFD = -1
        try? FileManager.default.removeItem(atPath: Self.lockPath)
    }

    // MARK: - Setup

    private func setupOverlayPanel() {
        overlayPanel = OverlayPanel(viewModel: viewModel)
        overlayPanel?.onDismiss = { [weak self] in
            self?.hidePanel()
        }
    }

    private func setupHotKey() {
        // kVK_ANSI_H = 0x04, controlKey = 0x1000, shiftKey = 0x0200
        hotKeyManager = HotKeyManager(keyCode: UInt32(0x04), modifiers: UInt32(controlKey | shiftKey)) { [weak self] in
            DispatchQueue.main.async {
                self?.togglePanel()
            }
        }
    }

    // MARK: - Toggle

    @objc func togglePanel() {
        guard toggleDebouncer.shouldFire() else { return }

        guard let panel = overlayPanel else { return }

        switch panel.phase {
        case .hidden:
            showPanel()
        case .visible, .showing:
            hidePanel()
        case .hiding:
            // Already fading out — let it finish
            break
        }
    }

    // MARK: - Menu actions

    /// ⌘N / Chat ▸ New Chat. Acts only while the panel is the key surface.
    @objc func newChat() {
        guard overlayPanel?.phase == .visible else { return }
        viewModel.newChat()
    }

    /// ⌘F / Chat ▸ Search History. Opens the history list and focuses search.
    @objc func searchHistory() {
        guard overlayPanel?.phase == .visible else { return }
        viewModel.openHistory(focusSearch: true)
    }

    /// Menu-bar ▸ New Chat. Shows the panel first if it's hidden, so it works
    /// even when the app isn't already active.
    @objc func menuBarNewChat() {
        if overlayPanel?.phase != .visible { showPanel() }
        viewModel.newChat()
    }

    private func showPanel() {
        guard let panel = overlayPanel, panel.beginShow() else { return }

        // Remember who was frontmost so we can hand focus back on close.
        previousApp = NSWorkspace.shared.frontmostApplication

        viewModel.reset()
        panel.positionPanel()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.Layout.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }, completionHandler: { [weak self, weak panel] in
            panel?.finishShow()
            // Install the click-outside monitor only after the show animation
            // finishes, so the opening click/keystroke can't immediately dismiss.
            // Animation completions are delivered on the main thread.
            MainActor.assumeIsolated { self?.installClickOutsideMonitor() }
        })
    }

    private func hidePanel() {
        guard let panel = overlayPanel, panel.beginHide() else { return }

        removeClickOutsideMonitor()
        viewModel.cleanup()

        // Return focus to the app the user came from. Done before the fade so the
        // other app is already frontmost as our panel disappears.
        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
        previousApp = nil

        // Fade out animation then hide
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.Layout.disappearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.finishHide()
        })
    }

    // MARK: - Click-outside dismissal

    /// Installs a global mouse-down monitor that closes the panel when the user
    /// clicks in any other application. Global monitors only observe events
    /// destined for other apps, so a click inside our own panel never triggers it.
    private func installClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        // Only arm the monitor if the panel is actually visible.
        guard overlayPanel?.phase == .visible else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
