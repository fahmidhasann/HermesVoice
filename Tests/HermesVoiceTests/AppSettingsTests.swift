import Foundation
import HermesVoiceKit

enum AppSettingsTests {
    static let cases: [TestCase] = [
        TestCase(name: "defaults are sane") {
            let d = AppSettings.default
            checkEqual(d.hotKeyCode, 0x04, "default hotkey is H")
            checkEqual(d.endpointHost, "127.0.0.1")
            checkEqual(d.endpointPort, 8642)
            check(d.model == nil, "default model is nil")
            checkEqual(d.appearance, .system)
            checkEqual(d.baseURLString, "http://127.0.0.1:8642")
        },
        TestCase(name: "encode/decode round-trips") {
            var s = AppSettings.default
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
    ]
}
