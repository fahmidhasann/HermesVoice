# Implementation brief: UI/UX polish pass ("soft & tactile")

**Status:** decisions locked (interview complete). Not yet implemented — held for
review. This is a refinement pass on an already-intentional design; it changes
*feel*, not flow or features.

Companion docs: `CONTEXT.md` (UI vocabulary) · `docs/adr/0001-translucent-chrome-near-solid-content.md`.

---

## 0. Context

HermesVoice is a macOS menu-bar app: a fixed-size (540×540) floating **panel**
(toggled ⌃⇧H) hosting a **chat surface** and a **history** screen, talking to a
local Hermes agent. The visual system lives in `Theme.swift` and is read by every
view, so system-level token changes ripple to all five surfaces (overlay,
history, menu bar, settings, onboarding).

## 1. Locked decisions

1. **Driver:** refinement/polish, not fixing flow or bugs.
2. **Identity:** keep the warm-editorial amber identity — **no palette change**.
3. **Quality bar:** soft & tactile / Apple-native (materials, gentle springs,
   cozy depth, rounded warmth — dialed in carefully, not piled on).
4. **Focus:** bespoke effort on the **overlay** first; refined tokens then ripple
   outward.
5. **Materials:** **hybrid** — translucent material *chrome*; near-solid
   *content*; tactile light/shadow craft everywhere. (See ADR 0001.)
6. **chat ↔ history:** gentle navigation **push** (history slides in from the
   trailing edge; chat eases left + dims; Back reverses). Reduce-motion →
   cross-fade/instant.
7. **macOS floor:** keep `.macOS(.v14)`; `if #available`-guard the rare 15+ API.
   (Verified: materials, springs, `.scrollTransition`, `PhaseAnimator`,
   `.symbolEffect`, `.visualEffect` are all available on 14.)
8. **Recording:** **calm & cohesive** — collapse the five simultaneous red signals
   (top accent line, mic glow, pulsing dot, waveform, transcription preview) into
   one confident "Listening" expression; more organic waveform; gentle
   entry/exit; keep red as the conventional rec cue.

## 2. Non-goals

- No new accent/palette; no recoloring the identity.
- No panel resize or size change — fixed 540×540 stays (see
  `tasks/fixed-panel-size-plan.md`).
- No flow/feature add or removal.
- Do **not** over-style the native Settings window — Apple-native means leaning on
  native `Form`/`TabView`, only ensuring accent + spacing parity.
- No new dependencies expected.

## 3. Phase 0 — Foundations (`Theme.swift`; ripples to all surfaces)

Low-risk, high-leverage consolidation. Concrete current offenders found:

- **Elevation/shadow:** one scale (e.g. `rest / raised / floating`). Today the
  panel shadow is hardcoded in `OverlayPanel.swift:57-60` (opacity 0.28, radius
  34, y −12) while `Theme.Layout.shadow*` (32 / −12 / 0.22) and `Theme.Depth.*`
  define separate values — reconcile to one source. Verify `Theme.Layout.shadow*`
  isn't dead after.
- **Motion vocabulary:** keep a small named set on `Theme.Motion`. Remove the
  inlined `.spring(response:0.34, dampingFraction:0.78)` in `MessageBubble`
  (`OverlayView.swift:587`, == `springBubble`) and the hardcoded
  `.easeOut(duration: 0.12 / 0.08 / 0.16)` in `ButtonStyles.swift` and
  `pushToTalkMic` — route all through tokens.
- **Type scale:** tighten to a strict ladder; eliminate inline `.system(size:)`
  (header icons 12.5/11, timestamps 9.5, copy 10.5, hints 10.5, etc.) — route via
  `Theme.Font` and a new `Theme.Icon` size set.
- **Spacing rhythm:** remove ad-hoc `+2 / +4` offsets (`Spacing.sm + 2`,
  `.md + 4`, `.vertical, 5`, `xxl + sm`); add scale steps where a real value is
  missing, justify any remainder.
- **Radius harmony:** define a concentric ladder nesting inside panel 16 (content
  bubble ≈ 12–14, control ≈ 10–11, chip ≈ 8–10, image 8); fold inline 8/9/10 in.
- **Material roles:** add `Theme.Materials` (chrome = `.thinMaterial`; content =
  near-solid resolved surface) so the chrome/content rule is a token, not ad-hoc.

## 4. Phase 1 — Overlay (daily driver)

- **Apply hybrid materials:** `.thinMaterial` on chrome (header, input bar, status
  pill, chips, tool rows); near-solid content bubbles. Raise assistant-bubble fill
  toward opaque if contrast needs it (today 0.045–0.075 is quite translucent).
- **Bubble tactile craft:** subtle top highlight, soft inner/drop shadow from the
  elevation token, concentric edge. Keep amber user-bubble identity.
- **chat ↔ history push:** replace the `Group { if showingHistory }` swap with an
  animated container; `springGentle`; reduce-motion fallback.
- **Calm recording:** consolidate signals — keep the waveform + a single calm
  accent as the "Listening" expression; drop redundant simultaneous reds; make the
  waveform organic (mirrored around center, smooth interpolation); gentle
  enter/exit on the text↔waveform swap.
- **Empty state / first impression:** refine the halo/disc/waveform focal point and
  copy hierarchy; optional very-subtle breathing (reduce-motion aware).
- **Micro-motion:** smoother message arrival (token spring), send↔stop morph,
  subtle scroll-edge `.scrollTransition` fade (guard for 14+), consistent
  hover/press states via the motion tokens.

## 5. Phase 2 — Ripple

- **History:** inherit tokens; refine row hover/selection + push-in continuity.
- **Menu bar:** tokens only; refine the streaming pulse + background-finish cue.
- **Settings:** keep native; ensure `.tint(accent)` + spacing parity; minimal.
- **Onboarding:** inherit tokens; refine icon badges, keycap, progress dots; add a
  gentle step transition (currently instant).

## 6. Acceptance / verification

- `swift build` clean.
- `swift run HermesVoiceTests` passes (this project's test runner is a plain
  executable — XCTest is unavailable under the CLT toolchain; *not* `swift test`).
- Verify **both** light and dark, and the **reduce-motion** path.
- Visually check overlay legibility over a busy wallpaper (validates ADR 0001).
- `graphify update .` after code changes (per `CLAUDE.md`).

## 7. Deferred to implementation (tune with eyes on screen)

Exact type-scale values · exact elevation shadow values · whether assistant-bubble
opacity needs raising · precise waveform redesign · which recording signals to drop
vs keep.
