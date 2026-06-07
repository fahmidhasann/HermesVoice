import SwiftUI

/// Compact icon button for header actions (new chat, history, close).
/// Subtle at rest, a soft amber-neutral wash on hover, a confident press dip.
struct IconButtonStyle: ButtonStyle {
    @State private var isHovered = false
    var size: CGFloat = 26
    var backgroundColor: Color = Color.clear
    var hoverColor: Color = Theme.Colors.textPrimary.opacity(0.08)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle().fill(configuration.isPressed
                              ? Theme.Colors.textPrimary.opacity(0.14)
                              : (isHovered ? hoverColor : backgroundColor))
            )
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(Theme.Motion.hover, value: isHovered)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Circular mic toggle button — fills with the recording gradient when active,
/// a soft neutral wash otherwise. Active state carries a faint red glow.
struct CircleButtonStyle: ButtonStyle {
    @State private var isHovered = false
    var size: CGFloat = 34
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background {
                if isActive {
                    Circle().fill(Theme.Gradients.recording)
                } else {
                    Circle().fill(isHovered
                                  ? Theme.Colors.textPrimary.opacity(0.13)
                                  : Theme.Colors.textPrimary.opacity(0.06))
                }
            }
            .overlay(
                Circle().strokeBorder(Theme.Colors.hairline, lineWidth: isActive ? 0 : 0.5)
            )
            .shadow(color: isActive ? Theme.Colors.recordingRed.opacity(0.45) : .clear,
                    radius: isActive ? 7 : 0, x: 0, y: isActive ? 2 : 0)
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(Theme.Motion.hover, value: isHovered)
            .animation(Theme.Motion.toggle, value: isActive)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Accent-filled circle send button — warm amber gradient with a soft glow,
/// flattening to a muted disc when there's nothing to send.
struct SendButtonStyle: ButtonStyle {
    @State private var isHovered = false
    var size: CGFloat = 34
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background {
                if isDisabled {
                    Circle().fill(Theme.Colors.textSecondary.opacity(0.22))
                } else {
                    Circle()
                        .fill(Theme.Gradients.accent)
                        .overlay(
                            // A whisper of inner highlight up top for a domed feel.
                            Circle().fill(
                                LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                                               startPoint: .top, endPoint: .center)
                            )
                        )
                        .brightness(isHovered ? 0.05 : 0)
                }
            }
            .shadow(color: isDisabled ? .clear : Theme.Elevation.actionGlow(),
                    radius: isDisabled ? 0 : Theme.Elevation.actionRadius,
                    x: 0, y: isDisabled ? 0 : Theme.Elevation.actionY)
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(Theme.Motion.hover, value: isHovered)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .animation(Theme.Motion.toggle, value: isDisabled)
            .onHover { isHovered = $0 }
    }
}
