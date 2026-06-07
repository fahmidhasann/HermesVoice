import Carbon
import AppKit
import HermesVoiceKit

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    // Debounce: key-repeat and accidental double-fires from Carbon can both
    // dispatch a single keypress as 2-3 events within ~50ms. We coalesce those
    // into a single callback so one press = one toggle. (User reported "two
    // windows open" when holding ⌃⇧H — this is what was happening.)
    private var debouncer = Debouncer(interval: 0.18)

    // Store reference for the C callback
    private static var instance: HotKeyManager?

    init(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback
        HotKeyManager.instance = self
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        unregisterHotKey()
        HotKeyManager.instance = nil
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x48564B59) // "HVKY"
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        // Install event handler
        let handlerCallback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr {
                HotKeyManager.instance?.fireIfNotDebounced()
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // Register the hotkey
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("HermesVoice: Failed to register hotkey, status: \(status)")
        }
    }

    private func fireIfNotDebounced() {
        if debouncer.shouldFire() {
            callback()
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
