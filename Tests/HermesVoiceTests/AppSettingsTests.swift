import Foundation
import HermesVoiceKit

enum AppSettingsTests {
    static let cases: [TestCase] = [
        TestCase(name: "defaults are sane") {
            let d = AppSettings.default
            checkEqual(d.hotKeyCode, 0x04, "default hotkey is H")
            checkEqual(d.gatewayURL, "http://127.0.0.1:8642")
            checkEqual(d.endpointHost, "127.0.0.1")
            checkEqual(d.endpointPort, 8642)
            check(d.model == nil, "default model is nil")
            checkEqual(d.appearance, .system)
            checkEqual(d.baseURLString, "http://127.0.0.1:8642")
        },
        TestCase(name: "encode/decode round-trips") {
            var s = AppSettings.default
            s.gatewayURL = "https://gw.example.com:8443"
            s.endpointHost = "localhost"
            s.endpointPort = 9000
            s.model = "hermes-pro"
            s.appearance = .dark
            s.launchAtLogin = true
            s.voiceFlow = .reviewSend
            s.silenceTimeout = 2.5
            s.recognitionLanguage = "en-US"
            s.hotKeyCode = 9
            s.hotKeyModifiers = HotKeyFormatter.cmdKey | HotKeyFormatter.optionKey
            let decoded = AppSettings.decode(AppSettings.encode(s))
            checkEqual(decoded, s, "round-trip should be identity")
        },
        TestCase(name: "corrupt data falls back to defaults") {
            let decoded = AppSettings.decode(Data("not json".utf8))
            checkEqual(decoded, .default)
            checkEqual(AppSettings.decode(Data()), .default, "empty data → defaults")
        },
        TestCase(name: "missing fields fall back per-field, keeping present ones") {
            // Only a couple of keys present; everything else should default.
            let json = #"{"endpointPort": 7777, "appearance": "light"}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            checkEqual(decoded.endpointPort, 7777, "present field kept")
            checkEqual(decoded.appearance, .light, "present field kept")
            checkEqual(decoded.endpointHost, AppSettings.default.endpointHost, "missing field defaulted")
            checkEqual(decoded.hotKeyCode, AppSettings.default.hotKeyCode, "missing field defaulted")
        },
        TestCase(name: "unknown enum value falls back to default") {
            let json = #"{"voiceFlow": "telepathy", "appearance": "neon"}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            checkEqual(decoded.voiceFlow, AppSettings.default.voiceFlow)
            checkEqual(decoded.appearance, AppSettings.default.appearance)
        },
        TestCase(name: "normalizedModel trims and nils-out empty") {
            var s = AppSettings.default
            s.model = "   "
            check(s.normalizedModel == nil, "blank model normalizes to nil")
            s.model = "  hermes-x  "
            checkEqual(s.normalizedModel, "hermes-x")
        },
        TestCase(name: "hotkey modifier symbols are canonical order") {
            let mods = HotKeyFormatter.controlKey | HotKeyFormatter.shiftKey
            checkEqual(HotKeyFormatter.modifierSymbols(mods), "⌃⇧")
            let all = HotKeyFormatter.controlKey | HotKeyFormatter.optionKey
                | HotKeyFormatter.shiftKey | HotKeyFormatter.cmdKey
            checkEqual(HotKeyFormatter.modifierSymbols(all), "⌃⌥⇧⌘")
        },
        TestCase(name: "hotkey display string combines modifiers + key") {
            checkEqual(
                HotKeyFormatter.displayString(keyCode: 4,
                                              modifiers: HotKeyFormatter.controlKey | HotKeyFormatter.shiftKey),
                "⌃⇧H")
            checkEqual(
                HotKeyFormatter.displayString(keyCode: 49, modifiers: HotKeyFormatter.cmdKey),
                "⌘Space")
        },
        TestCase(name: "hasModifier rejects bare keys") {
            check(!HotKeyFormatter.hasModifier(0), "no modifiers → invalid")
            check(HotKeyFormatter.hasModifier(HotKeyFormatter.cmdKey), "cmd → valid")
        },
        TestCase(name: "unknown key code names itself") {
            checkEqual(HotKeyFormatter.keyName(9999), "Key 9999")
        },
        TestCase(name: "baseURLString reflects the gateway URL (any scheme/port)") {
            var s = AppSettings.default
            s.gatewayURL = "https://gw.example.com:8443"
            checkEqual(s.baseURLString, "https://gw.example.com:8443")
        },
        TestCase(name: "baseURLString strips trailing slashes") {
            var s = AppSettings.default
            s.gatewayURL = "http://localhost:8642/"
            checkEqual(s.baseURLString, "http://localhost:8642", "one trailing slash")
            s.gatewayURL = "http://localhost:8642///"
            checkEqual(s.baseURLString, "http://localhost:8642", "several trailing slashes")
            s.gatewayURL = "  http://localhost:8642  "
            checkEqual(s.baseURLString, "http://localhost:8642", "surrounding whitespace trimmed")
        },
        TestCase(name: "legacy host/port composes gatewayURL when absent") {
            // A blob written before gatewayURL existed: migrate from host/port.
            let json = #"{"endpointHost": "localhost", "endpointPort": 9000}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            checkEqual(decoded.gatewayURL, "http://localhost:9000", "composed from legacy fields")
            checkEqual(decoded.baseURLString, "http://localhost:9000")
        },
        TestCase(name: "missing gatewayURL with no host/port lands on the default") {
            let json = #"{"model": "x"}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            // host/port default to 127.0.0.1:8642, so the composed URL matches.
            checkEqual(decoded.gatewayURL, "http://127.0.0.1:8642")
        },
        TestCase(name: "explicit gatewayURL wins over legacy host/port") {
            let json = #"{"gatewayURL": "https://gw.example.com", "endpointHost": "localhost", "endpointPort": 9000}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            checkEqual(decoded.gatewayURL, "https://gw.example.com", "stored URL preferred")
        },
        TestCase(name: "blank stored gatewayURL falls back to composed legacy URL") {
            let json = #"{"gatewayURL": "   ", "endpointHost": "10.0.0.2", "endpointPort": 7000}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            checkEqual(decoded.gatewayURL, "http://10.0.0.2:7000", "whitespace-only URL ignored")
        },
        TestCase(name: "wrong-typed field falls back without wiping the blob") {
            // endpointPort given as a string is the wrong type; it must fall back
            // to the default while a correctly-typed sibling is preserved.
            let json = #"{"endpointPort": "not-a-number", "endpointHost": "example.com"}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            checkEqual(decoded.endpointPort, AppSettings.default.endpointPort,
                       "mistyped field defaults")
            checkEqual(decoded.endpointHost, "example.com", "valid sibling preserved")
        },
        TestCase(name: "explicit null model decodes to nil") {
            let json = #"{"model": null}"#
            let decoded = AppSettings.decode(Data(json.utf8))
            check(decoded.model == nil, "null model → nil")
        },
        TestCase(name: "no modifiers yields an empty symbol string") {
            checkEqual(HotKeyFormatter.modifierSymbols(0), "")
        },
        TestCase(name: "each modifier maps to its glyph") {
            checkEqual(HotKeyFormatter.modifierSymbols(HotKeyFormatter.controlKey), "⌃")
            checkEqual(HotKeyFormatter.modifierSymbols(HotKeyFormatter.optionKey), "⌥")
            checkEqual(HotKeyFormatter.modifierSymbols(HotKeyFormatter.shiftKey), "⇧")
            checkEqual(HotKeyFormatter.modifierSymbols(HotKeyFormatter.cmdKey), "⌘")
        },
        TestCase(name: "named key codes resolve to glyphs") {
            checkEqual(HotKeyFormatter.keyName(36), "↩")
            checkEqual(HotKeyFormatter.keyName(53), "⎋")
            checkEqual(HotKeyFormatter.keyName(123), "←")
            checkEqual(HotKeyFormatter.keyName(126), "↑")
            checkEqual(HotKeyFormatter.keyName(122), "F1")
        },
        TestCase(name: "hasModifier accepts any single modifier") {
            check(HotKeyFormatter.hasModifier(HotKeyFormatter.controlKey), "ctrl valid")
            check(HotKeyFormatter.hasModifier(HotKeyFormatter.optionKey), "opt valid")
            check(HotKeyFormatter.hasModifier(HotKeyFormatter.shiftKey), "shift valid")
        },
        TestCase(name: "voiceFlow and appearance expose all cases with labels") {
            checkEqual(VoiceFlow.allCases.count, 3)
            checkEqual(AppearanceMode.allCases.count, 3)
            for f in VoiceFlow.allCases { check(!f.label.isEmpty, "\(f) has a label") }
            for a in AppearanceMode.allCases { check(!a.label.isEmpty, "\(a) has a label") }
        },
    ]
}
