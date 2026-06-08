import SwiftUI
import AVFoundation
import Speech

/// First-run welcome flow: a short three-step intro that explains the app,
/// walks the user through the microphone + speech-recognition permission
/// prompts, and points out the global hotkey. Shown once (gated by a
/// UserDefaults flag in `AppDelegate`); `onFinish` is called when the user
/// completes or skips it.
struct OnboardingView: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, connect, permissions, hotkey
    }

    /// Result of a "Test connection" tap in the Connect step.
    private enum TestState: Equatable {
        case idle, testing, reachable(models: Int), unreachable
    }

    // Fields bind straight into the shared stores, so whatever the user types is
    // persisted immediately (URL → UserDefaults, key → Keychain). That's why the
    // step is freely skippable: there's nothing to "commit" on the way out.
    @ObservedObject private var settingsStore = AppSettingsStore.shared
    @ObservedObject private var credentials = CredentialsStore.shared

    @State private var step: Step = .welcome
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var testState: TestState = .idle

    private let client = HermesAPIClient()

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 36)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        // Height is sized for the tallest step (Connect: badge + two fields + a
        // test row). The shorter steps absorb the slack through their trailing
        // Spacer, so nothing clips.
        .frame(width: 460, height: 500)
        .background(Theme.Colors.baseTint)
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcomeStep
        case .connect:     connectStep
        case .permissions: permissionsStep
        case .hotkey:      hotkeyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            iconBadge(symbol: "waveform")
            VStack(spacing: 10) {
                Text("Welcome to HermesVoice")
                    .font(.system(size: 22, weight: .semibold))
                Text("Talk to your Hermes agent from anywhere with a single keystroke — by voice or by typing — without opening Telegram or Discord.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var connectStep: some View {
        VStack(spacing: 18) {
            iconBadge(symbol: "network")
            VStack(spacing: 8) {
                Text("Connect your gateway")
                    .font(.system(size: 20, weight: .semibold))
                Text("HermesVoice talks to your Hermes Agent Gateway. Enter its URL and API key — both stay on this Mac (the key lives in your Keychain).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                onboardingField(label: "Gateway URL") {
                    TextField("http://127.0.0.1:8642", text: $settingsStore.settings.gatewayURL)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                onboardingField(label: "API key") {
                    SecureField("Paste your API key (optional)", text: $credentials.apiKey)
                        .textFieldStyle(.plain)
                }
                testRow
            }
            .frame(width: 320)

            Spacer(minLength: 0)
        }
    }

    /// "Test connection" action plus its ✓/✗ result, used only in the Connect step.
    private var testRow: some View {
        HStack(spacing: 8) {
            Button(action: testConnection) {
                Text("Test connection")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.accent)
            .disabled(testState == .testing)

            if testState == .testing {
                ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
            }
            Spacer()
            testStatusLabel
        }
    }

    @ViewBuilder
    private var testStatusLabel: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .reachable(let count):
            Label(count > 0 ? "Connected · \(count) model\(count == 1 ? "" : "s")" : "Connected",
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.success)
        case .unreachable:
            Label("Can't reach gateway", systemImage: "xmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.error)
        }
    }

    private func testConnection() {
        testState = .testing
        Task {
            let healthy = await client.checkHealth()
            let models = healthy ? await client.fetchModels() : []
            await MainActor.run {
                testState = healthy ? .reachable(models: models.count) : .unreachable
            }
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            iconBadge(symbol: "mic.fill")
            VStack(spacing: 8) {
                Text("Allow voice input")
                    .font(.system(size: 20, weight: .semibold))
                Text("HermesVoice transcribes your speech on-device. It needs the microphone and speech recognition — nothing audio leaves your Mac for transcription.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                permissionRow(title: "Microphone", granted: micGranted, denied: micDenied)
                permissionRow(title: "Speech recognition", granted: speechGranted, denied: speechDenied)
            }
            .padding(.top, 4)

            if micDenied || speechDenied {
                Text("Denied? Re-enable under System Settings ▸ Privacy & Security.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            iconBadge(symbol: "command")
            VStack(spacing: 10) {
                Text("You're all set")
                    .font(.system(size: 20, weight: .semibold))
                Text("Press your hotkey anytime to open the voice panel:")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                keycap("⌃ ⇧ H")
                Text("Change it — and the model, appearance, and voice behavior — in Settings (⌘,) or the menu-bar icon.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer (progress dots + actions)

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s == step ? AnyShapeStyle(Theme.Colors.accent)
                                        : AnyShapeStyle(Theme.Colors.textTertiary.opacity(0.4)))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step != .hotkey {
                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.trailing, 4)
            }
            Button(primaryTitle) { advance() }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome:     return "Get Started"
        case .connect:     return "Continue"
        case .permissions: return permissionsResolved ? "Continue" : "Allow Access"
        case .hotkey:      return "Done"
        }
    }

    private func advance() {
        switch step {
        case .welcome:
            step = .connect
        case .connect:
            step = .permissions
        case .permissions:
            if permissionsResolved {
                step = .hotkey
            } else {
                requestPermissions()
            }
        case .hotkey:
            onFinish()
        }
    }

    // MARK: - Permissions

    private var micGranted: Bool { micStatus == .authorized }
    private var micDenied: Bool { micStatus == .denied || micStatus == .restricted }
    private var speechGranted: Bool { speechStatus == .authorized }
    private var speechDenied: Bool { speechStatus == .denied || speechStatus == .restricted }
    /// True once both prompts have been answered (granted or denied), so the
    /// flow can move on rather than stalling on a denial.
    private var permissionsResolved: Bool {
        micStatus != .notDetermined && speechStatus != .notDetermined
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async {
                speechStatus = SFSpeechRecognizer.authorizationStatus()
            }
        }
    }

    // MARK: - Building blocks

    private func iconBadge(symbol: String) -> some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accentSoft)
                .frame(width: 96, height: 96)
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Gradients.accent)
        }
    }

    /// A labelled input chip for the Connect step — the field sits in the same
    /// soft-amber rounded surface used by `permissionRow`/`keycap`, so the step
    /// reads as part of the onboarding rather than a bare system form.
    private func onboardingField<Content: View>(label: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
            content()
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Colors.accentSoft.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(Theme.Colors.hairline)
                        )
                )
        }
    }

    private func permissionRow(title: String, granted: Bool, denied: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill"
                              : denied ? "xmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Theme.Colors.success
                                 : denied ? Theme.Colors.error : Theme.Colors.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(granted ? "Allowed" : denied ? "Denied" : "Not yet")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.accentSoft.opacity(0.5))
        )
        .frame(width: 300)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.accentSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.Colors.hairline)
                    )
            )
    }
}

/// Filled amber primary button for the onboarding footer.
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.Gradients.accent)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
    }
}
