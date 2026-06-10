import Foundation

/// How a captured voice transcript is handed to the conversation.
public enum VoiceFlow: String, Codable, Sendable, CaseIterable {
    /// Speech fills the input field; the user edits and presses Enter to send.
    case reviewSend
    /// Auto-send the transcript once silence is detected.
    case autoSend
    /// Hold the mic to record, release to send.
    case pushToTalk

    /// Human-readable label for the Settings picker.
    public var label: String {
        switch self {
        case .reviewSend: return "Transcribe → review → send"
        case .autoSend:   return "Auto-send on silence"
        case .pushToTalk: return "Push-to-talk (hold to record)"
        }
    }

    /// Whether recording should auto-stop after a silence window. Push-to-talk
    /// holds the mic open until the user releases the button, so it opts out.
    public var stopsOnSilence: Bool { self != .pushToTalk }

    /// What to do with a captured transcript once recording ends. Pure routing
    /// logic shared by the view model and exercised by unit tests.
    public enum TranscriptOutcome: Equatable, Sendable {
        /// Nothing usable was recognized — return to idle quietly.
        case ignore
        /// Place the text in the input field for the user to review and edit.
        case fill(String)
        /// Send the text to Hermes immediately.
        case send(String)
    }

    /// Decide how a finished transcript should be handled for this flow. Empty
    /// or whitespace-only transcripts always `.ignore` (graceful no-speech).
    public func outcome(for transcript: String) -> TranscriptOutcome {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ignore }
        switch self {
        case .reviewSend:          return .fill(trimmed)
        case .autoSend, .pushToTalk: return .send(trimmed)
        }
    }
}

/// App appearance override.
public enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

/// All user-configurable settings, persisted as JSON in `UserDefaults`. Decoding
/// is per-field tolerant (see `init(from:)`) so adding fields in a later version
/// never wipes a user's existing settings — missing keys fall back to defaults.
public struct AppSettings: Codable, Equatable, Sendable {
    // MARK: Shortcuts
    /// Carbon virtual key code for the global hotkey (default `H` = 4).
    public var hotKeyCode: UInt32
    /// Carbon modifier mask for the global hotkey (default ⌃⇧).
    public var hotKeyModifiers: UInt32

    // MARK: Connection
    /// Full base URL of the gateway (scheme + host + optional port), e.g.
    /// `http://127.0.0.1:8642` or `https://gw.example.com`. This is the single
    /// source for the endpoint; `endpointHost`/`endpointPort` are retained only
    /// to migrate settings written before this field existed.
    public var gatewayURL: String
    /// Legacy split endpoint — superseded by `gatewayURL`. Kept decodable so an
    /// upgrade composes `gatewayURL` from these once (see `init(from:)`).
    public var endpointHost: String
    public var endpointPort: Int
    /// Model id to request, or `nil`/empty to let the server pick its default.
    public var model: String?

    // MARK: General
    public var appearance: AppearanceMode
    public var launchAtLogin: Bool

    // MARK: Voice
    public var voiceFlow: VoiceFlow
    /// Seconds of silence before recording auto-stops.
    public var silenceTimeout: Double
    /// Recognition locale identifier (e.g. "en-US"); empty = system locale.
    public var recognitionLanguage: String

    public init(hotKeyCode: UInt32,
                hotKeyModifiers: UInt32,
                gatewayURL: String,
                endpointHost: String,
                endpointPort: Int,
                model: String?,
                appearance: AppearanceMode,
                launchAtLogin: Bool,
                voiceFlow: VoiceFlow,
                silenceTimeout: Double,
                recognitionLanguage: String) {
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.gatewayURL = gatewayURL
        self.endpointHost = endpointHost
        self.endpointPort = endpointPort
        self.model = model
        self.appearance = appearance
        self.launchAtLogin = launchAtLogin
        self.voiceFlow = voiceFlow
        self.silenceTimeout = silenceTimeout
        self.recognitionLanguage = recognitionLanguage
    }

    /// The shipped defaults: ⌃⇧H hotkey, local gateway, server-default model,
    /// system appearance, and the accurate-by-default voice behavior
    /// (transcribe → review → send).
    public static let `default` = AppSettings(
        hotKeyCode: 0x04,                                          // kVK_ANSI_H
        hotKeyModifiers: HotKeyFormatter.controlKey | HotKeyFormatter.shiftKey,
        gatewayURL: "http://127.0.0.1:8642",
        endpointHost: "127.0.0.1",
        endpointPort: 8642,
        model: nil,
        appearance: .system,
        launchAtLogin: false,
        voiceFlow: .reviewSend,
        silenceTimeout: 1.5,
        recognitionLanguage: "")

    /// Base URL string for the configured endpoint (no trailing slash). Derived
    /// from `gatewayURL`, so it carries whatever scheme/port the user entered.
    public var baseURLString: String {
        var s = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Normalize a user-entered gateway URL into `scheme://host[:port]`, or nil
    /// when no valid http(s) base can be made of it. Handles the common entry
    /// mistakes that previously produced silently-wrong requests:
    /// - missing scheme (`gw.example.com:8642` parses with scheme
    ///   "gw.example.com"!) → `http://` is prepended,
    /// - a trailing path or slash (`…/v1` → `…/v1/v1/chat/completions`) →
    ///   path/query/fragment are stripped.
    public static func normalizedGatewayURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if let schemeRange = trimmed.range(of: "://") {
            // An explicit scheme must be http(s); anything else is a typo we
            // can't guess at (ftp://… etc.), not a missing-scheme case.
            let scheme = trimmed[..<schemeRange.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
        } else {
            candidate = "http://" + candidate
        }

        guard var components = URLComponents(string: candidate),
              let parsedScheme = components.scheme?.lowercased(),
              parsedScheme == "http" || parsedScheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = parsedScheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard var normalized = components.string else { return nil }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized
    }

    /// Model normalized for sending: trimmed, `nil` when empty.
    public var normalizedModel: String? {
        guard let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else { return nil }
        return model
    }

    // MARK: - Tolerant Codable

    private enum CodingKeys: String, CodingKey {
        case hotKeyCode, hotKeyModifiers
        case gatewayURL, endpointHost, endpointPort, model
        case appearance, launchAtLogin
        case voiceFlow, silenceTimeout, recognitionLanguage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        // Per-field fallback: a missing or malformed key reads as the default.
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        hotKeyCode = value(.hotKeyCode, d.hotKeyCode)
        hotKeyModifiers = value(.hotKeyModifiers, d.hotKeyModifiers)
        endpointHost = value(.endpointHost, d.endpointHost)
        endpointPort = value(.endpointPort, d.endpointPort)
        // gatewayURL migration: an explicit stored value wins; otherwise compose
        // it from the legacy host/port (which themselves defaulted just above, so
        // a brand-new blob lands on the local-gateway default).
        if let stored = (try? c.decodeIfPresent(String.self, forKey: .gatewayURL)) ?? nil,
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gatewayURL = stored
        } else {
            gatewayURL = "http://\(endpointHost):\(endpointPort)"
        }
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
        appearance = value(.appearance, d.appearance)
        launchAtLogin = value(.launchAtLogin, d.launchAtLogin)
        voiceFlow = value(.voiceFlow, d.voiceFlow)
        silenceTimeout = value(.silenceTimeout, d.silenceTimeout)
        recognitionLanguage = value(.recognitionLanguage, d.recognitionLanguage)
    }

    /// Decode tolerantly — corrupt/empty data yields the defaults rather than
    /// throwing, so a bad blob can never block launch.
    public static func decode(_ data: Data) -> AppSettings {
        guard !data.isEmpty,
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    public static func encode(_ settings: AppSettings) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(settings)) ?? Data()
    }
}

/// Pure formatting + validation for global-hotkey configurations. Carbon
/// modifier-mask constants are duplicated here as plain integers so the Kit
/// stays hardware-free (no `Carbon` import) and unit-testable.
public enum HotKeyFormatter {
    public static let cmdKey: UInt32 = 0x0100
    public static let shiftKey: UInt32 = 0x0200
    public static let optionKey: UInt32 = 0x0800
    public static let controlKey: UInt32 = 0x1000

    private static let anyModifier = cmdKey | shiftKey | optionKey | controlKey

    /// Modifier glyphs in macOS canonical order (⌃⌥⇧⌘).
    public static func modifierSymbols(_ modifiers: UInt32) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s
    }

    /// True when at least one of ⌃⌥⇧⌘ is set — a bare key is not a valid global
    /// hotkey, so the recorder uses this to reject incomplete combinations.
    public static func hasModifier(_ modifiers: UInt32) -> Bool {
        modifiers & anyModifier != 0
    }

    /// Display string for the whole combination, e.g. "⌃⇧H".
    public static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierSymbols(modifiers) + keyName(keyCode)
    }

    /// Human-readable name for a Carbon/AppKit virtual key code.
    public static func keyName(_ keyCode: UInt32) -> String {
        if let name = keyNames[keyCode] { return name }
        return "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
