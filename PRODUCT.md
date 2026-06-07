# Product

## Register

product

## Users

macOS power users: keyboard-driven Mac users who want a capable assistant one
keystroke away from anywhere on the system.

Their context is mid-task. They are inside another app (editor, terminal,
browser, doc) when a question or thought surfaces, and they do not want to
break flow to find a window, open a browser tab, or hunt for a control. They
summon the panel with a global hotkey (⌃⇧H), talk or type, take the answer, and
return to what they were doing.

The job to be done: reach the Hermes agent, by voice or text, with the least
friction possible, and get back to work. History exists for the secondary job
of revisiting a past conversation.

## Product Purpose

HermesVoice is a macOS menu-bar app that puts a Hermes agent one hotkey away
from anywhere. A fixed-size (540×540) floating panel lets the user talk or type
to the agent, watch the reply stream in, and revisit past conversations, then
dismiss and resume their work. Voice flows (review-send, auto-send,
push-to-talk) and a text input share the same surface.

Success is reflexive use: the panel is faster and lower-friction than opening
any other app to reach the agent, so users reach for it without thinking. It
wins on the time and attention it gives back, not on the time it holds.

## Brand Personality

Three words: **quick, unobtrusive, crafted.**

The app wears a warm-editorial skin (amber accent, off-white base, charcoal
text, soft tactile depth) but behaves fast and exacting. Warmth is carried by
color, material, and type, never by chatter or visual volume. Voice and tone
are minimal, plain, and confident: no marketing gloss, no robotic "AI product"
register, no filler.

Emotional goal: the user feels in control and the interaction feels effortless
and immediate, calm but never slow. The app should read as a quiet, well-made
native macOS tool, not as a chatbot.

## Anti-references

What HermesVoice should explicitly NOT look or feel like:

- **Cluttered and busy.** Too many controls or competing signals at once. The
  recording state is the canonical trap: five simultaneous red cues (top accent
  line, mic glow, pulsing dot, waveform, transcription preview) collapsed into
  one confident "Listening" expression. Show one clear thing at a time.
- **Sterile corporate SaaS.** Cold blues, dense dashboards, enterprise
  flatness. No warmth, no character, no sense a person made it.
- **Loud and techy.** Neon gradients, pervasive glassmorphism, cyberpunk
  "AI product" sheen, dramatic dark-by-default drama. Gradients and materials
  here stay subtle and purposeful (they mark primary action and live state),
  never decorative.

## Design Principles

1. **Speed is the feature.** The panel earns its place only by being faster
   than not using it: summon, capture, dismiss. Judge every interaction by the
   friction it removes, not the polish it adds.

2. **Recede, don't perform.** The chrome gets out of the way so the
   conversation and the user's own flow stay in focus. No element claims
   attention it did not earn. When in doubt, remove a signal rather than add
   one.

3. **Craft you feel, not notice.** Apple-native precision (materials, gentle
   springs, cozy depth, concentric radii) tuned so the result reads as simply
   "right," never as decoration. Restraint over accumulation; dialed in
   carefully, not piled on.

4. **Warmth is the identity, never the volume.** The warm-editorial amber
   carries character through color, material, and type. One confident accent,
   not a palette parade. Personality comes from how it feels, not from how loud
   it is.

5. **Legible over anything.** The panel floats over arbitrary wallpapers, so
   content stays readable regardless of what is behind it (ADR 0001:
   translucent chrome, near-solid content). State is always unambiguous, and
   meaning never rides on color alone.

## Accessibility & Inclusion

Target: **WCAG AA.**

- Body text ≥ 4.5:1 against its background; large text (≥18px, or bold ≥14px)
  ≥ 3:1; placeholder text held to the same 4.5:1.
- Never rely on color alone. The red "Listening" cue must also carry shape,
  label, or motion so the state reads without color perception.
- Reduce-motion is honored throughout (`Theme.Motion.ifMotion` /
  `reduceMotion`): animations fall back to crossfade or instant.
- Legibility over arbitrary wallpapers is a hard requirement, not a nicety
  (ADR 0001).
- Light and dark appearances share the same emotional temperature and must
  both pass contrast.
