import SwiftUI

/// Centralised design tokens. Single source of truth for all
/// colour, typography, spacing, layout, depth, and motion decisions in the app.
struct Theme {

    // MARK: - Colors
    //
    // Palette is "warm editorial" — off-white base, charcoal text, warm amber
    // accent. The Phase-7 redesign keeps that identity but leans *expressive*:
    // a small amber ramp (bright → base → deep) feeds subtle gradients and
    // richer accent moments, while layered shadows add cozy depth.
    //
    // Dark mode lifts every amber stop and uses a warm-tinted charcoal so both
    // appearances share the same emotional temperature. Semantic SwiftUI
    // primitives (.primary/.secondary) are used for text so they auto-adapt;
    // only the accent ramp and surface tints are hand-picked per mode.

    enum Appearance {
        static let warmOffWhite  = Color(red: 0.980, green: 0.973, blue: 0.961)   // #FAF8F5
        static let warmCharcoal  = Color(red: 0.110, green: 0.110, blue: 0.118)   // warm dark

        // Amber ramp — light
        static let accentLight       = Color(red: 0.831, green: 0.506, blue: 0.420)   // #D4816B (base)
        static let accentBrightLight = Color(red: 0.886, green: 0.604, blue: 0.522)   // #E29A85 (lifted)
        static let accentDeepLight   = Color(red: 0.776, green: 0.431, blue: 0.341)   // #C66E57 (deepened)

        // Amber ramp — dark
        static let accentDark        = Color(red: 0.910, green: 0.584, blue: 0.498)   // #E8957F (base)
        static let accentBrightDark  = Color(red: 0.949, green: 0.663, blue: 0.576)   // #F2A993 (lifted)
        static let accentDeepDark    = Color(red: 0.863, green: 0.502, blue: 0.408)   // #DC8068 (deepened)
    }

    struct Colors {
        /// Warm amber accent — adapts to light/dark
        static let accent       = resolvedColor(light: Appearance.accentLight,       dark: Appearance.accentDark)
        /// Lifted amber — top of accent gradients, hover glows
        static let accentBright = resolvedColor(light: Appearance.accentBrightLight, dark: Appearance.accentBrightDark)
        /// Deepened amber — bottom of accent gradients, pressed states
        static let accentDeep   = resolvedColor(light: Appearance.accentDeepLight,   dark: Appearance.accentDeepDark)

        /// Soft amber wash for tinted surfaces (chips, active rows, tool rows).
        static let accentSoft = resolvedColor(
            light: Appearance.accentLight.opacity(0.12),
            dark:  Appearance.accentDark.opacity(0.18)
        )

        /// Base tint for the visual-effect overlay
        static let baseTint = resolvedColor(light: Appearance.warmOffWhite, dark: Appearance.warmCharcoal)

        // Text — automatic via .primary/.secondary
        static let textPrimary   = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary  = Color.secondary.opacity(0.6)

        /// Divider / hairline
        static let divider = Color.primary.opacity(0.08)
        /// Hairline border that lifts surfaces off the background (cards, bubbles).
        static let hairline = resolvedColor(
            light: Color.black.opacity(0.06),
            dark:  Color.white.opacity(0.08)
        )

        // State colours
        static let recordingRed = Color(red: 0.92, green: 0.36, blue: 0.36)
        static let success      = Color(red: 0.40, green: 0.78, blue: 0.55)
        static let warning      = Color(red: 0.95, green: 0.65, blue: 0.30)
        static let error        = Color(red: 0.92, green: 0.36, blue: 0.36)
    }

    // MARK: - Gradients
    //
    // Subtle, purposeful gradients only (per the warm-&-expressive brief):
    // they mark *primary action* and *live state*, never decorate inert chrome.
    // Each is built from appearance-resolved colours so light/dark parity is free.

    struct Gradients {
        /// Primary action (send button, mic-active fill). Lifted top → deep bottom.
        static let accent = LinearGradient(
            colors: [Colors.accentBright, Colors.accentDeep],
            startPoint: .top, endPoint: .bottom
        )

        /// Recording / listening fill (mic while active, accent line).
        static let recording = LinearGradient(
            colors: [
                Color(red: 0.945, green: 0.435, blue: 0.435),   // #F17070
                Color(red: 0.855, green: 0.290, blue: 0.290),   // #DA4A4A
            ],
            startPoint: .top, endPoint: .bottom
        )

        /// User-message bubble — a warm amber whisper, slightly stronger up top.
        static var userBubble: LinearGradient {
            LinearGradient(
                colors: [
                    resolvedColor(light: Appearance.accentLight.opacity(0.16),
                                  dark:  Appearance.accentDark.opacity(0.22)),
                    resolvedColor(light: Appearance.accentLight.opacity(0.09),
                                  dark:  Appearance.accentDark.opacity(0.13)),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }

        /// Assistant-message bubble — a quiet neutral lift with faint depth.
        static var assistantBubble: LinearGradient {
            LinearGradient(
                colors: [
                    resolvedColor(light: Color.black.opacity(0.045), dark: Color.white.opacity(0.075)),
                    resolvedColor(light: Color.black.opacity(0.025), dark: Color.white.opacity(0.045)),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }

        /// Header wash — a faint amber tint that fades to clear, anchoring the top.
        static var header: LinearGradient {
            LinearGradient(
                colors: [
                    resolvedColor(light: Appearance.accentLight.opacity(0.07),
                                  dark:  Appearance.accentDark.opacity(0.10)),
                    Color.clear,
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Depth (shadows)
    //
    // Two elevation steps. `bubble` is a near-invisible lift that separates a
    // surface from the background; `action` is the warm glow under the primary
    // send button. Keep radii small — these render per-message in a list.

    struct Depth {
        static let bubbleColor   = Color.black.opacity(0.07)
        static let bubbleRadius: CGFloat = 4
        static let bubbleY:      CGFloat = 1.5

        static func actionGlow(_ base: Color = Colors.accent) -> Color { base.opacity(0.40) }
        static let actionRadius: CGFloat = 6
        static let actionY:      CGFloat = 2
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

    // MARK: - Radius

    struct Radius {
        static let bubble:  CGFloat = 14
        static let control: CGFloat = 11
        static let chip:    CGFloat = 10
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
        /// A touch more lively for arrivals (bubbles, chips) — still no overshoot bounce worth noticing.
        static let springBubble = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.78)
        static let easeOut      = SwiftUI.Animation.easeOut(duration: 0.22)
        static let easeInOut    = SwiftUI.Animation.easeInOut(duration: 0.28)

        /// Returns `.never` when the user has disabled motion (accessibility),
        /// preserving the requested animation otherwise. Use like:
        ///   `.animation(Theme.Motion.ifMotion(.easeOut(duration: 0.2)), value: flag)`
        static func ifMotion(_ animation: SwiftUI.Animation) -> SwiftUI.Animation? {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
        }

        /// True when the user has asked the system to minimise motion.
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
