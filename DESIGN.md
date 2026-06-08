---
name: HermesVoice
description: A warm, fast macOS panel for talking or typing to a Hermes agent from anywhere.
colors:
  terracotta: "#D4816B"
  terracotta-bright: "#E29A85"
  terracotta-deep: "#C66E57"
  terracotta-dark: "#E8957F"
  terracotta-bright-dark: "#F2A993"
  terracotta-deep-dark: "#DC8068"
  warm-off-white: "#FAF8F5"
  warm-charcoal: "#1C1C1E"
  recording-red: "#EB5C5C"
  success: "#66C78C"
  warning: "#F2A64D"
typography:
  title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
rounded:
  panel: "16px"
  bubble: "14px"
  control: "11px"
  chip: "10px"
  image: "8px"
spacing:
  xxs: "2px"
  xs: "4px"
  xs2: "6px"
  sm: "8px"
  sm2: "10px"
  md: "12px"
  md2: "14px"
  lg: "16px"
  xl: "20px"
  xxl: "28px"
  xxxl: "36px"
components:
  button-send:
    backgroundColor: "{colors.terracotta}"
    textColor: "#FFFFFF"
    size: "34px"
  button-send-disabled:
    backgroundColor: "#00000038"
    textColor: "#FFFFFF"
    size: "34px"
  input-field:
    backgroundColor: "#0000000C"
    textColor: "{colors.warm-charcoal}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  bubble-user:
    backgroundColor: "#D4816B29"
    textColor: "{colors.warm-charcoal}"
    rounded: "{rounded.bubble}"
    padding: "10px 14px"
  bubble-assistant:
    backgroundColor: "#0000000C"
    textColor: "{colors.warm-charcoal}"
    rounded: "{rounded.bubble}"
    padding: "10px 14px"
---

# Design System: HermesVoice

## 1. Overview

**Creative North Star: "The Warm Workbench"**

HermesVoice is a fast, well-made tool with an editorial warmth. It is summoned
by a keystroke, used mid-task, and dismissed; its whole job is to get you in, do
the thing, and get out. The visual system serves that: warm to the touch, never
sterile, and quiet enough to never compete with the work it interrupts. Think of
a craftsman's bench, not a chat app. Everything has a place, the surface is calm,
and the one warm tool (the terracotta accent) is the thing your eye goes to.

The whole system is built from a single warm-neutral canvas (off-white in light,
warm charcoal in dark) and one accent: **Terracotta**, a fired-clay
orange-pink. There is no second accent and no display typography. Hierarchy comes
from a compact type ladder (15px ceiling), generous-but-rhythmic spacing, soft
materials, and state-driven depth, not from size, color variety, or chrome. The
panel floats over arbitrary wallpapers, so a hard rule governs everything:
**chrome may be translucent; content stays near-solid and readable** (ADR 0001).

This system explicitly rejects three looks (from PRODUCT.md): the **cluttered
and busy** (many controls and competing signals at once), the **sterile
corporate SaaS** (cold blues, dense dashboards, no character), and the **loud and
techy** (neon, pervasive glassmorphism, cyberpunk "AI product" sheen). Warmth is
carried by color, material, and type, never by volume.

**Key Characteristics:**
- One canvas, one accent (Terracotta). No second accent, ever.
- Compact, utilitarian type: a 15px ceiling, no display type, hierarchy from weight.
- Hybrid materials: translucent chrome, near-solid content (legibility over any wallpaper).
- Flat by default; depth is a response to state (focus, active, hover, primary action).
- Concentric radii nesting inside the 16px panel: 16 ▸ 14 ▸ 11 ▸ 10 ▸ 8.
- Light and dark share one emotional temperature; the accent lifts in dark mode.

## 2. Colors

A single warm-neutral canvas plus one warm accent. Color is rare on purpose: the
terracotta marks the primary action and live state, and almost nothing else.

### Primary
- **Terracotta** (#D4816B): the one accent. Marks the primary action (send
  button), the active/responding state, focus rings, the user-bubble tint, and
  the empty-state focal halo. In dark mode it lifts to **Terracotta (Dark)**
  (#E8957F) so the warmth survives a dark canvas.
- **Terracotta Bright** (#E29A85, dark #F2A993): top of accent gradients and
  hover glows. The lifted end of the ramp.
- **Terracotta Deep** (#C66E57, dark #DC8068): bottom of accent gradients and
  pressed states. The grounded end of the ramp.

### Neutral
- **Warm Off-White** (#FAF8F5): the light-mode canvas. A true warm neutral, not
  a tinted "cream"; it reads as paper, never as a beige theme.
- **Warm Charcoal** (#1C1C1E): the dark-mode canvas and the spirit of the ink. A
  warm-tinted dark so both appearances share one temperature.
- **Text** (system label colors): primary, secondary (~60% of primary), and
  tertiary text use the macOS semantic label colors so they auto-adapt to
  appearance and vibrancy. Do not hand-pick text hex.
- **Hairline / Divider** (black 6-8% in light, white 8% in dark): the only
  borders in the system. Always ≤ 1px. They separate surfaces without drawing a
  line you notice.

### Signal (functional states, used only for state)
- **Recording Red** (#EB5C5C): the listening/recording cue, and reused for
  errors. The single red of the system. Gradient form #F17070 → #DA4A4A fills
  the active mic.
- **Success Green** (#66C78C): the "Done" state dot only.
- **Warning Amber** (#F2A64D): the transcribing/sending state. Note it sits near
  the terracotta hue; it is a state color, never an accent.

### Named Rules
**The One-Accent Rule.** Terracotta is the only accent in the system. There is
no secondary brand color. If a screen needs a second accent to make sense, the
screen is wrong, not the palette.

**The Rare-Color Rule.** On any given surface, saturated color (terracotta or a
signal color) covers well under 10%. Its rarity is what makes the send button and
the live-state pill read instantly. Everything else is warm neutral.

## 3. Typography

**Display Font:** none. The system has no hero/display type by design.
**Body Font:** SF Pro (the macOS system font, `-apple-system` / `system-ui`).
**Mono Font:** SF Mono, used only inside fenced code blocks in assistant
messages (via MarkdownUI + Highlightr).

**Character:** one family, sized down and tuned by weight. The result is
compact, native, and utilitarian, the type of a well-built tool rather than a
content site. Warmth comes from the canvas and accent, not from a typeface.

### Hierarchy
- **Title** (semibold, 15px): the panel header label and section titles. The
  largest text in the app; there is nothing bigger.
- **Body** (regular, 13.5px): conversation text, the live transcript, and the
  input field. Emphasis is the same size at medium weight (13.5px / 500), never
  a size jump.
- **Label** (medium, 13px): button text and interactive labels.
- **Status label** (semibold, 10.5px, +0.3px tracking): the status-pill text
  (Ready, Listening, Transcribing…). The one place tracking is used.
- **Hint** (medium, 10.5px): keyboard hints and inline cues (the empty-state
  keycap line).
- **Caption** (regular, 9.5-10px): timestamps under bubbles, at low opacity.

### Named Rules
**The No-Shout Rule.** Type never exceeds 15px and is never set in all-caps
sentences. Hierarchy is made with weight and the small-label ramp, not with
scale. If something needs to feel important, it gets weight or the accent, not a
bigger font.

## 4. Elevation

Flat by default; depth is a response to state. Surfaces sit nearly flush with the
canvas at rest, and shadow or glow appears to signal something happening (focus,
active capture, the primary action). The deliberate exception is the panel
itself, which carries a real drop shadow because it is literally floating over
the desktop.

### Shadow Vocabulary
- **Floating panel** (`opacity 0.28, radius 34, y -12`): the whole panel hovering
  over the wallpaper. Applied once, on the AppKit window layer (a SwiftUI
  `.shadow` can't reach the window view). This is the one always-on elevation.
- **Rest lift** (`black 7%, radius 4, y 1.5`): a near-invisible lift under
  message bubbles so they separate by a hair from the panel. Tuned so faint that
  bubbles read essentially flat; it renders per-message, so it stays cheap.
- **Action glow** (`terracotta 40%, radius 6, y 2`): a warm glow under the send
  button. Marks the primary action; disappears when the button is disabled.
- **Recording glow** (`recording-red 45%, radius 7, y 2`): the active-mic glow.
  Marks live capture; present only while recording.

### Named Rules
**The Flat-By-Default Rule.** Surfaces are flat at rest. Shadow and glow appear
only as a response to state: focus, active, hover, or the primary action. The
floating panel's drop shadow is the single exception, because it is floating.

## 5. Components

The feel is **refined and tactile**: soft surfaces with real, restrained depth.
Gentle highlights, hairline edges, concentric radii, and a confident press dip,
but never heavy and never decorative.

### Buttons
- **Shape:** circular for the action controls (mic, send: 34px) and header
  actions (26px). Press feedback is a uniform scale to 0.90 with a fast dip
  (`press`, 80ms).
- **Send (primary):** a terracotta gradient fill (bright → deep) with a whisper
  of white inner highlight up top for a domed feel, plus the action glow.
  Brightens slightly on hover. Disabled flattens to a muted neutral disc with no
  glow. While a response streams, it **morphs in place** into a Stop button
  (`stop.fill`), never appearing as a second button.
- **Mic:** a soft neutral wash at rest (ink 6%, hover 13%), a 0.5px hairline ring.
  Active, it fills with the recording gradient and gains the recording glow. In
  push-to-talk it is a press-and-hold control (release sends).
- **Header actions (icon):** clear at rest, a soft ink wash on hover (8%), a
  firmer wash on press (14%). New chat, history, close. Quiet until touched.
- **Retry / Copy (tertiary):** plain glyph buttons. Copy lives on every bubble,
  subtle at rest (40% opacity), full-strength on hover, with a green checkmark
  "Copied" confirmation.

### Status Pill (signature)
The header capsule that shows the lifecycle state. A 6px dot plus a tracked
10.5px label on a state-tinted capsule (fill `statusColor 12%`, hairline
`statusColor 18%`). The dot and label both take the state color: secondary
(Ready), recording-red (Listening), warning (Transcribing/Sending), terracotta
(Responding), success (Done), error (Error). While listening or responding, the
dot grows a slow breathing ring. State changes cross-fade over 240ms. This is the
app's primary state expression: one calm, legible signal, not five.

### Message Bubbles (signature)
Near-solid content, per ADR 0001. Continuous-corner rounded rectangles at 14px
with a 0.5px edge and the near-invisible rest lift.
- **User:** a warm terracotta-tint gradient (a "warm amber whisper", stronger up
  top) with a terracotta 18% edge. Right-aligned with a 48px leading gutter.
- **Assistant:** a quiet neutral lift gradient (ink 4.5% → 2.5%) with a hairline
  edge. Full GitHub-flavored markdown, with highlighted, copyable code blocks,
  rendered incrementally as it streams. Left-aligned with a 48px trailing gutter.
- **Arrival:** fade + 10px rise + scale from 0.98, on a gentle `springBubble`,
  anchored to the bubble's own corner.
- **Timestamp:** a 9.5px caption below the bubble at ~45% opacity.

### Inputs / Fields
- **Style:** a multi-line text field (1-4 lines, auto-grow) on a faint ink fill
  (~4.5%) at the 11px control radius, with a 0.5px hairline edge. Placeholder
  "Type a message…".
- **Focus:** the edge shifts to a terracotta 55% ring at 1.5px, toggled over
  160ms. The one focus treatment in the system.
- **Behavior:** Return sends; Shift/Option+Return inserts a newline; Esc dismisses
  the panel. While a response streams, the field is replaced in place by the live
  waveform.

### Chips
- **Tool activity row:** the ephemeral "Hermes is using…" row. A terracotta-soft
  fill at the 10px chip radius with a terracotta 15% edge, an emoji glyph, and a
  small spinner. Never persisted in the transcript; it enters on a leading slide
  and vanishes when the step completes.
- **Pending image chip:** a 52px square thumbnail at the 8px image radius with a
  divider edge and a top-trailing remove button.

### Navigation
- **Header actions** sit top-right (new chat, history, close), quiet icon buttons.
- **Chat ↔ History** is a gentle navigational push: History slides in from the
  trailing edge while Chat eases left and dims; Back reverses. Reduce-motion
  collapses this to a cross-fade or instant swap.

### Empty State (first impression)
A single warm focal point: a soft terracotta halo (blurred) behind a gradient
disc holding a light `waveform` glyph, then "Click the mic or type to begin"
(emphasized body), then a keycap-style hint line ("⌃⇧H to toggle · Enter to
send"). Warm, centered, one idea.

### Recording (the calm-cohesive target)
"Listening" is one confident expression, not five simultaneous red signals.
Documented intent (per `tasks/ui-polish-plan.md`): keep the organic waveform plus
a single calm accent; drop redundant reds; gentle enter/exit on the
text ↔ waveform swap. Red stays the conventional capture cue.

## 6. Do's and Don'ts

### Do:
- **Do** keep Terracotta (#D4816B) as the only accent, on well under 10% of any
  surface (the One-Accent and Rare-Color rules).
- **Do** keep content near-solid and legible over any wallpaper; reserve
  translucent materials (`.thinMaterial`) for chrome only (ADR 0001).
- **Do** build hierarchy with weight and the small-label ramp, never with type
  larger than 15px (the No-Shout rule).
- **Do** keep surfaces flat at rest and let depth respond to state: focus rings,
  active glows, hover washes, the send action glow (the Flat-By-Default rule).
- **Do** nest radii concentrically inside the 16px panel: 16 ▸ 14 ▸ 11 ▸ 10 ▸ 8.
- **Do** route every color, size, space, radius, shadow, and motion value through
  `Theme.swift`. It is the single source; never inline a raw value.
- **Do** pair every state with shape, label, or motion, not color alone (the red
  "Listening" cue carries a dot, label, and waveform too).
- **Do** give every animation a reduce-motion fallback via `Theme.Motion.ifMotion`.

### Don't:
- **Don't** ship the **cluttered and busy** look: no stacking multiple competing
  signals at once. The five-simultaneous-reds recording state is the canonical
  trap; collapse signals into one.
- **Don't** drift toward **sterile corporate SaaS**: no cold blues, no dense
  dashboards, no characterless enterprise flatness.
- **Don't** go **loud and techy**: no neon gradients, no pervasive
  glassmorphism, no cyberpunk "AI product" sheen, no dramatic dark-by-default.
  Gradients here are subtle and mark only primary action or live state.
- **Don't** add a second accent, or recolor the terracotta identity.
- **Don't** use type in all-caps sentences, or any display type; the 15px header
  is the ceiling.
- **Don't** make content (bubbles, transcript) translucent. If text could ever
  sit on glass over a busy wallpaper, the design is wrong.
- **Don't** use a colored side-stripe border, gradient-filled text, or a shadow
  heavy enough to read as a 2014 app (if the blur is small and the shadow dark,
  it is wrong).
- **Don't** let body text fall below 4.5:1 contrast (3:1 for large/bold); hold
  placeholders to 4.5:1 too (WCAG AA).
