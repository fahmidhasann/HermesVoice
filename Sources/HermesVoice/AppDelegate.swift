import AppKit
import SwiftUI
import Carbon
import Combine
import ServiceManagement
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

    let settingsController = SettingsWindowController()

    // Subscription to the settings store + the last successfully applied
    // settings, used to diff which system-level effect to (re)apply on change.
    private var settingsCancellable: AnyCancellable?
    private var appliedSettings: AppSettings = .default

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
        subscribeToSettings()

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
        // Register the configured hotkey (defaults to ⌃⇧H).
        let s = AppSettingsStore.shared.settings
        hotKeyManager = HotKeyManager(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers) { [weak self] in
            DispatchQueue.main.async {
                self?.togglePanel()
            }
        }
    }

    // MARK: - Settings side effects

    /// Subscribe to settings changes and apply the system-level ones that the
    /// SwiftUI bindings can't perform themselves: hotkey re-registration,
    /// appearance, and launch-at-login. Diffs against `appliedSettings` so each
    /// effect only runs when its field actually changed.
    private func subscribeToSettings() {
        let store = AppSettingsStore.shared
        appliedSettings = store.settings
        applyAppearance(appliedSettings.appearance)
        applyLaunchAtLogin(appliedSettings.launchAtLogin)
        // Deliver on the next runloop tick so the store's `didSet` has committed
        // the new value (and re-entrant reverts below don't fight the publisher).
        settingsCancellable = store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] newSettings in
                self?.applySettingsChange(newSettings)
            }
    }

    private func applySettingsChange(_ new: AppSettings) {
        if new.appearance != appliedSettings.appearance {
            applyAppearance(new.appearance)
        }
        if new.launchAtLogin != appliedSettings.launchAtLogin {
            applyLaunchAtLogin(new.launchAtLogin)
        }

        let hotkeyChanged = new.hotKeyCode != appliedSettings.hotKeyCode
            || new.hotKeyModifiers != appliedSettings.hotKeyModifiers
        guard hotkeyChanged else { appliedSettings = new; return }

        let ok = hotKeyManager?.update(keyCode: new.hotKeyCode,
                                       modifiers: new.hotKeyModifiers,
                                       previousKeyCode: appliedSettings.hotKeyCode,
                                       previousModifiers: appliedSettings.hotKeyModifiers) ?? false
        if ok {
            appliedSettings = new
        } else {
            // Carbon rejected the combo (already claimed). Roll the store's
            // hotkey back to the last working one and tell the user.
            var reverted = AppSettingsStore.shared.settings
            reverted.hotKeyCode = appliedSettings.hotKeyCode
            reverted.hotKeyModifiers = appliedSettings.hotKeyModifiers
            AppSettingsStore.shared.settings = reverted
            appliedSettings = reverted
            showHotKeyConflictAlert()
        }
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            NSLog("HermesVoice: launch-at-login update failed: \(error.localizedDescription)")
        }
    }

    private func showHotKeyConflictAlert() {
        let alert = NSAlert()
        alert.messageText = "Shortcut unavailable"
        alert.informativeText = "That key combination is already in use by macOS or another app. Your previous shortcut has been kept."
        alert.alertStyle = .warning
        alert.runModal()
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

    /// ⌘V / Edit ▸ Paste. If the pasteboard holds an image and the panel is
    /// visible, attach it to the message; otherwise forward to the normal text
    /// paste so typing fields keep working.
    @objc func smartPaste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if overlayPanel?.phase == .visible,
           pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            viewModel.attachImage(image)
            return
        }
        // No image (or panel hidden) — route to the field editor's paste:.
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
    }

    /// Menu-bar ▸ New Chat. Shows the panel first if it's hidden, so it works
    /// even when the app isn't already active.
    @objc func menuBarNewChat() {
        if overlayPanel?.phase != .visible { showPanel() }
        viewModel.newChat()
    }

    /// ⌘, / Settings… — open (or focus) the Settings window.
    @objc func openSettings() {
        settingsController.show()
    }

    /// ⌘W / Window ▸ Close. Closes the Settings window when it's frontmost;
    /// otherwise hides the overlay panel.
    @objc func closeFrontWindow() {
        if let key = NSApp.keyWindow {
            if key === overlayPanel {
                hidePanel()
            } else {
                key.performClose(nil)
            }
            return
        }
        if overlayPanel?.phase == .visible { hidePanel() }
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
