import SwiftUI
import AppKit
import HermesVoiceKit

/// The Settings window content: General / Voice / Connection / Shortcuts tabs.
/// All controls bind directly into `AppSettingsStore.shared.settings`; the store
/// persists on change and `AppDelegate` applies system-level side effects.
struct SettingsView: View {
    @ObservedObject private var store = AppSettingsStore.shared

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: $store.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            VoiceSettingsTab(settings: $store.settings)
                .tabItem { Label("Voice", systemImage: "mic") }
            ConnectionSettingsTab(settings: $store.settings)
                .tabItem { Label("Connection", systemImage: "network") }
            ShortcutsSettingsTab(settings: $store.settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 380)
        // Carry the warm-amber identity into the native controls (selected tab,
        // toggles, slider, pickers) while keeping standard macOS form idioms.
        .tint(Theme.Colors.accent)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Launch at login", isOn: $settings.launchAtLogin)

            Text("Open HermesVoice automatically when you log in.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }
}

// MARK: - Voice

private struct VoiceSettingsTab: View {
    @Binding var settings: AppSettings

    /// A small, friendly set of recognition locales. "" = follow the system.
    private let languages: [(id: String, label: String)] = [
        ("", "System"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Spanish"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("zh-CN", "Chinese (Simplified)"),
    ]

    var body: some View {
        Form {
            Picker("Default flow", selection: $settings.voiceFlow) {
                ForEach(VoiceFlow.allCases, id: \.self) { flow in
                    Text(flow.label).tag(flow)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Silence timeout")
                    Spacer()
                    Text(String(format: "%.1fs", settings.silenceTimeout))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.silenceTimeout, in: 0.5...4.0, step: 0.1)
            }

            Picker("Recognition language", selection: $settings.recognitionLanguage) {
                ForEach(languages, id: \.id) { lang in
                    Text(lang.label).tag(lang.id)
                }
            }

            Text(flowHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    /// One-line explanation of what the currently-selected flow does.
    private var flowHint: String {
        switch settings.voiceFlow {
        case .reviewSend:
            return "Tap the mic to dictate; the text fills the input for you to edit, then press Return to send."
        case .autoSend:
            return "Tap the mic to dictate; the message sends automatically after a pause. Changes apply on your next recording."
        case .pushToTalk:
            return "Hold the mic button to record and release to send. Changes apply on your next recording."
        }
    }
}

// MARK: - Connection

private struct ConnectionSettingsTab: View {
    @Binding var settings: AppSettings
    @State private var models: [String] = []
    @State private var modelStatus: String = ""
    @State private var loadingModels = false
    @State private var portText: String = ""

    private let client = HermesAPIClient()

    /// Bridge `model: String?` to a non-optional Picker selection ("" = default).
    private var modelSelection: Binding<String> {
        Binding(
            get: { settings.model ?? "" },
            set: { settings.model = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Host", text: $settings.endpointHost)
                TextField("Port", text: $portText)
                    .onChange(of: portText) { _, new in
                        if let port = Int(new.filter(\.isNumber)), port > 0 { settings.endpointPort = port }
                    }
            }

            Section {
                Picker("Model", selection: modelSelection) {
                    Text("Server default").tag("")
                    // Keep a previously-chosen model selectable even if the list
                    // hasn't loaded (or the server no longer advertises it).
                    if let current = settings.model, !current.isEmpty, !models.contains(current) {
                        Text(current).tag(current)
                    }
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button(action: refreshModels) {
                        Label("Refresh models", systemImage: "arrow.clockwise")
                    }
                    .disabled(loadingModels)
                    if loadingModels { ProgressView().scaleEffect(0.5).frame(width: 16, height: 16) }
                    Spacer()
                    if !modelStatus.isEmpty {
                        Text(modelStatus).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Text("Default endpoint is 127.0.0.1:8642 (the local Hermes gateway).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .onAppear {
            portText = String(settings.endpointPort)
            refreshModels()
        }
    }

    private func refreshModels() {
        loadingModels = true
        modelStatus = ""
        Task {
            let fetched = await client.fetchModels()
            await MainActor.run {
                models = fetched
                loadingModels = false
                modelStatus = fetched.isEmpty
                    ? "Couldn't reach the gateway."
                    : "\(fetched.count) model\(fetched.count == 1 ? "" : "s") available."
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettingsTab: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            HStack {
                Text("Toggle panel")
                Spacer()
                HotKeyRecorder(keyCode: $settings.hotKeyCode, modifiers: $settings.hotKeyModifiers)
            }

            Button("Reset to default (⌃⇧H)") {
                settings.hotKeyCode = AppSettings.default.hotKeyCode
                settings.hotKeyModifiers = AppSettings.default.hotKeyModifiers
            }
            .buttonStyle(.link)

            Text("Other shortcuts: ⌘N new chat · ⌘F history · ⌘, settings · ⌘W close · Esc close/back.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}
