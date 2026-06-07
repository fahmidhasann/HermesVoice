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
        case welcome, permissions, hotkey
    }

    @State private var step: Step = .welcome
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 36)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 460, height: 420)
        .background(Theme.Colors.baseTint)
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcomeStep
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
        case .permissions: return permissionsResolved ? "Continue" : "Allow Access"
        case .hotkey:      return "Done"
        }
    }

    private func advance() {
        switch step {
        case .welcome:
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
