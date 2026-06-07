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

    // MARK: - Elevation (shadows)
    //
    // One elevation scale, two neutral steps plus the action glow:
    //   • rest     — a near-invisible lift separating a small surface (bubble,
    //                row) from the panel. Keep the radius small; it renders
    //                per-message in a list.
    //   • floating — the whole panel hovering over the desktop. Applied on the
    //                AppKit wrapper layer in `OverlayPanel` (a SwiftUI `.shadow`
    //                can't reach the window-level view), so it's exposed as raw
    //                values here and is the single source for that shadow.
    // `actionGlow` is a *coloured* glow under the primary send button — not a
    // neutral elevation — so it's kept distinct from the rest/floating scale.

    struct Elevation {
        static let restColor   = Color.black.opacity(0.07)
        static let restRadius:  CGFloat = 4
        static let restY:       CGFloat = 1.5

        static let floatingOpacity: CGFloat = 0.28
        static let floatingRadius:  CGFloat = 34
        static let floatingY:       CGFloat = -12

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
        /// Small medium-weight helper text (keyboard hints, inline cues).
        static func hint(size: CGFloat = 10.5) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .default)
        }
    }

    // MARK: - Icon sizes
    //
    // A tight four-step ladder for SF Symbols and leading glyphs, so icon sizing
    // is a token rather than a sprinkling of inline `.system(size:)` values.
    // Pair with an explicit weight: `.font(Theme.Icon.font(.sm, weight: .semibold))`.

    struct Icon {
        static let xs: CGFloat = 11      // close, copy, small inline glyphs
        static let sm: CGFloat = 12.5    // header actions, retry/stop/send, tool glyph
        static let md: CGFloat = 14      // mic, primary controls, remove-image
        static let lg: CGFloat = 22      // empty-state focal mark

        static func font(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }
    }

    // MARK: - Spacing

    // Core ladder plus three half-steps (`*2` = one notch above the named step)
    // that fill real gaps used by snug control/bubble padding, and a hero step
    // for empty-state breathing room. This is the single source — no more inline
    // `+2 / +4` offsets at call sites.

    struct Spacing {
        static let xxs:  CGFloat = 2
        static let xs:   CGFloat = 4
        static let xs2:  CGFloat = 6     // half-step xs → sm
        static let sm:   CGFloat = 8
        static let sm2:  CGFloat = 10    // half-step sm → md
        static let md:   CGFloat = 12
        static let md2:  CGFloat = 14    // half-step md → lg
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let xxl:  CGFloat = 28
        static let xxxl: CGFloat = 36    // hero / empty-state breathing room
    }

    // MARK: - Radius

    // A concentric ladder: each radius nests visually inside the one above, all
    // anchored to the panel corner. panel(16) ▸ bubble(14) ▸ control(11) ▸
    // chip(10) ▸ image(8). `Layout.cornerRadius` aliases `panel` so the outer
    // corner has one source too.

    struct Radius {
        static let panel:   CGFloat = 16   // the window itself
        static let bubble:  CGFloat = 14   // message bubbles, transcription preview
        static let control: CGFloat = 11   // input field, buttons
        static let chip:    CGFloat = 10   // tool-activity rows, chips
        static let image:   CGFloat = 8    // thumbnails (pending + in-message)
    }

    // MARK: - Layout

    struct Layout {
        static let panelWidth: CGFloat = 540
        /// Fixed panel height. The window no longer resizes to fit content; the
        /// conversation/history scroll inside this constant frame. This severs the
        /// content→window-height coupling that caused the resize-jitter.
        static let panelHeight: CGFloat = 540
        /// Outer panel corner — single source is `Radius.panel`.
        static let cornerRadius: CGFloat = Radius.panel
        static let screenTopOffset: CGFloat = 0.18

        // Animation durations (used by AppDelegate)
        static let appearDuration: CGFloat = 0.22
        static let disappearDuration: CGFloat = 0.16
    }

    // MARK: - Motion

    struct Motion {
        // Springs — arrivals & navigation.
        static let springQuick  = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.82)
        static let springGentle = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.86)
        /// A touch more lively for arrivals (bubbles, chips) — still no overshoot bounce worth noticing.
        static let springBubble = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.78)

        // Micro-motion ladder (eases) — named by *role*, not duration, so every
        // hover/press/state/content transition speaks one short vocabulary.
        static let press   = SwiftUI.Animation.easeOut(duration: 0.08)    // button press dip
        static let hover   = SwiftUI.Animation.easeOut(duration: 0.12)    // hover wash in/out
        static let toggle  = SwiftUI.Animation.easeOut(duration: 0.16)    // binary toggle (active, focus ring, disabled)
        static let content = SwiftUI.Animation.easeOut(duration: 0.20)    // content arrival / autoscroll / swap
        static let state   = SwiftUI.Animation.easeInOut(duration: 0.24)  // multi-state status pill / input-state shifts
        /// Slow ambient pulse (listening dot, future breathing). Already repeating.
        static let breathe = SwiftUI.Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)

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

    // MARK: - Materials
    //
    // The hybrid chrome/content rule from ADR 0001, as tokens rather than ad-hoc
    // choices: translucent *chrome* lets the wallpaper whisper through (header,
    // input bar, status pill, chips, tool rows); near-solid *content* keeps
    // reading surfaces (message bubbles) legible over any background. Applied in
    // Phase 1; defined here so every surface draws from one source.

    struct Materials {
        /// Chrome — translucent floating surfaces.
        static let chrome: Material = .thinMaterial
        /// Content — near-solid resolved surface bubbles tint over.
        static let content: Color = Colors.baseTint
    }
}

// MARK: - Color helpers

/// Returns `light` in light mode, `dark` in dark mode.
private func resolvedColor(light: Color, dark: Color) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        // Match only against [.aqua, .darkAqua] so any *vibrant* appearance the
        // NSVisualEffectView imposes on the hosting view (e.g. .vibrantDark)
        // resolves to its nearest base appearance. Listing .vibrantDark made it
        // match itself (≠ .darkAqua) and silently fall through to the light
        // colour — which kept the solid panel light while in dark mode.
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(dark) : NSColor(light)
    }))
}
