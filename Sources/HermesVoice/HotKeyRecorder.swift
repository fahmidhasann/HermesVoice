import SwiftUI
import AppKit
import HermesVoiceKit

/// A click-to-record control for capturing a global-hotkey combination. While
/// recording it installs a local key-down monitor and swallows the next valid
/// key + modifier press, writing it back through the bindings. `AppDelegate`
/// performs the actual (revertable) Carbon re-registration when the binding
/// changes, so a combination the system rejects is rolled back automatically.
struct HotKeyRecorder: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    @State private var recording = false
    @State private var monitor: Any?

    /// Virtual key codes of the modifier keys themselves — ignored so a lone
    /// ⌘/⇧/⌥/⌃ press doesn't get captured as the shortcut key.
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Type shortcut…" : HotKeyFormatter.displayString(keyCode: keyCode, modifiers: modifiers))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 96)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut")
        .onDisappear(perform: stopRecording)
    }

    private func toggle() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording without changing the binding.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            // Wait for a non-modifier key.
            guard !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }

            let mods = Self.carbonModifiers(from: event.modifierFlags)
            // A global hotkey needs at least one modifier; otherwise keep waiting.
            guard HotKeyFormatter.hasModifier(mods) else { return nil }

            keyCode = UInt32(event.keyCode)
            modifiers = mods
            stopRecording()
            return nil // swallow the event so it doesn't type into anything
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Translate AppKit modifier flags into the Carbon modifier mask Carbon's
    /// `RegisterEventHotKey` expects (and that `HotKeyFormatter` formats).
    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= HotKeyFormatter.cmdKey }
        if flags.contains(.shift)   { m |= HotKeyFormatter.shiftKey }
        if flags.contains(.option)  { m |= HotKeyFormatter.optionKey }
        if flags.contains(.control) { m |= HotKeyFormatter.controlKey }
        return m
    }
}
