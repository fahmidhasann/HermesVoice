import SwiftUI

/// Compact icon button for header actions (clear, close).
struct IconButtonStyle: ButtonStyle {
    @State private var isHovered = false
    var size: CGFloat = 24
    var backgroundColor: Color = Theme.Colors.textPrimary.opacity(0.04)
    var hoverColor: Color = Theme.Colors.textPrimary.opacity(0.10)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(isHovered ? hoverColor : backgroundColor)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Circular mic toggle button — turns red when active.
struct CircleButtonStyle: ButtonStyle {
    @State private var isHovered = false
    var size: CGFloat = 34
    var activeColor: Color = Theme.Colors.recordingRed
    var isActive: Bool = false

    private var bg: Color {
        if isActive { return activeColor }
        if isHovered { return Theme.Colors.textPrimary.opacity(0.12) }
        return Theme.Colors.textPrimary.opacity(0.06)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(bg)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Accent-filled circle send button.
struct SendButtonStyle: ButtonStyle {
    @State private var isHovered = false
    var size: CGFloat = 34
    var isDisabled: Bool = false

    private var bg: Color {
        if isDisabled { return Theme.Colors.textSecondary.opacity(0.25) }
        if isHovered { return Theme.Colors.accent.opacity(0.85) }
        return Theme.Colors.accent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(Circle().fill(bg))
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
