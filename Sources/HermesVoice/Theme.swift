import SwiftUI

/// Centralised design tokens. Single source of truth for all
/// colour, typography, spacing, and layout decisions in the app.
struct Theme {

    // MARK: - Colors
    //
    // Palette is "warm editorial" — off-white base, charcoal text, warm amber
    // accent. Dark mode lifts the accent and uses a warm-tinted charcoal to
    // keep the same emotional temperature as light mode.
    //
    // Semantic SwiftUI primitives (.primary/.secondary) are used for text so
    // they automatically adapt to the system appearance; only the accent and
    // surface tints are hand-picked per mode.

    enum Appearance {
        static let warmOffWhite  = Color(red: 0.980, green: 0.973, blue: 0.961)   // #FAF8F5
        static let warmCharcoal  = Color(red: 0.110, green: 0.110, blue: 0.118)   // warm dark
        static let accentLight   = Color(red: 0.831, green: 0.506, blue: 0.420)   // #D4816B
        static let accentDark    = Color(red: 0.910, green: 0.584, blue: 0.498)   // #E8957F
    }

    struct Colors {
        /// Warm amber accent — adapts to light/dark
        static let accent = resolvedColor(light: Appearance.accentLight, dark: Appearance.accentDark)

        /// Base tint for the visual-effect overlay
        static let baseTint = resolvedColor(light: Appearance.warmOffWhite, dark: Appearance.warmCharcoal)

        // Text — automatic via .primary/.secondary
        static let textPrimary   = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary  = Color.secondary.opacity(0.6)

        /// Background for user messages — subtle accent tint so they're visually
        /// distinct from assistant messages (which use .primary.opacity(0.05)).
        static let userBubble    = resolvedColor(
            light: Appearance.accentLight.opacity(0.10),
            dark:  Appearance.accentDark.opacity(0.14)
        )
        /// Background for assistant messages
        static let assistantBubble = Color.primary.opacity(0.05)
        /// Divider / hairline
        static let divider = Color.primary.opacity(0.08)

        // State colours
        static let recordingRed = Color(red: 0.92, green: 0.36, blue: 0.36)
        static let success      = Color(red: 0.40, green: 0.78, blue: 0.55)
        static let warning      = Color(red: 0.95, green: 0.65, blue: 0.30)
        static let error        = Color(red: 0.92, green: 0.36, blue: 0.36)
    }

    // MARK: - Typography

    struct Font {
        static func message(size: CGFloat = 13.5) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .default)
        }
        static func messageEmphasized(size: CGFloat = 13.5) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .default)
        }
        static func status(size: CGFloat = 10.5) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .default)
        }
        static func button(size: CGFloat = 13) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .default)
        }
        static func header(size: CGFloat = 15) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .default)
        }
        static func caption(size: CGFloat = 10) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .default)
        }
    }

    // MARK: - Spacing

    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: - Layout

    struct Layout {
        static let panelWidth: CGFloat = 540
        static let panelMinHeight: CGFloat = 220
        static let panelMaxHeight: CGFloat = 540
        /// Height the panel window is created at before SwiftUI reports the
        /// content's real height. Chosen ≥ the empty-state natural height so the
        /// first frame never clips the input row.
        static let panelInitialHeight: CGFloat = 300
        static let cornerRadius: CGFloat = 16
        static let screenTopOffset: CGFloat = 0.18

        static let shadowRadius: CGFloat = 32
        static let shadowOffsetY: CGFloat = -12
        static let shadowOpacity: CGFloat = 0.22

        // Animation durations (used by AppDelegate)
        static let appearDuration: CGFloat = 0.22
        static let disappearDuration: CGFloat = 0.16
        static let heightDuration: CGFloat = 0.28
    }

    // MARK: - Motion

    struct Motion {
        static let springQuick  = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.82)
        static let springGentle = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.86)
        static let easeOut      = SwiftUI.Animation.easeOut(duration: 0.22)
        static let easeInOut    = SwiftUI.Animation.easeInOut(duration: 0.28)

        /// Returns `.never` when the user has disabled motion (accessibility),
        /// preserving the requested animation otherwise. Use like:
        ///   `.animation(Theme.Motion.ifMotion(.easeOut(duration: 0.2)), value: flag)`
        static func ifMotion(_ animation: SwiftUI.Animation) -> SwiftUI.Animation? {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
        }
    }
}

// MARK: - Color helpers

/// Returns `light` in light mode, `dark` in dark mode.
private func resolvedColor(light: Color, dark: Color) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua]) == .darkAqua
        return isDark ? NSColor(dark) : NSColor(light)
    }))
}
