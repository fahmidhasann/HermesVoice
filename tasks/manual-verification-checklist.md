# HermesVoice — Manual Verification Checklist

> Phase 9 QA artifact. Automated coverage (release build, `swift run HermesVoiceTests`,
> bundle build/validate, launch smoke test) is green and re-runnable. The items below
> require a human at the keyboard / real microphone / a running Hermes gateway, and
> couldn't be automated headlessly (keystroke injection + screen capture need
> Accessibility / Screen-Recording permission this process doesn't hold).
>
> Run after a clean install: `rm -rf /Applications/HermesVoice.app && cp -r build/HermesVoice.app /Applications/ && open /Applications/HermesVoice.app`

## Phase 1 — Editing, dismissal, focus, resize
- [ ] Cmd+V / C / X / A / Z all work inside the input field.
- [ ] Clicking outside the panel closes it; the opening click never dismisses it.
- [ ] On close, focus + cursor return to the app that was frontmost before opening.
- [ ] Panel resizes smoothly while a reply streams — no height jitter/flicker.

## Phase 2 — Persistence, continuity, reliability
- [ ] Send a message → Quit → relaunch: the last conversation resumes.
- [ ] Kill the gateway mid-send: an offline state appears, then auto-retry recovers.
- [ ] Drop a stream mid-reply: the partial assistant text is kept + a retry is offered.
- [ ] (Protocol already verified live) no token double-counting without the session header.

## Phase 3 — History, new chat, copy
- [ ] Open history: search, ↑/↓ navigate, Enter opens, Esc returns.
- [ ] Delete a conversation (including the currently-open one) — files removed, UI recovers.
- [ ] ⌘N and the menu-bar New Chat both start a fresh chat (old one stays saved).
- [ ] Copy button works on **both** user and assistant bubbles (with "Copied" feedback).

## Phase 4 — Rich content
- [ ] A real markdown reply renders: code block syntax-highlighted + per-block copy; tables/lists.
- [ ] Paste an image and drag-drop an image — Hermes answers about it; image shows in the bubble.
- [ ] Tool-activity rows appear live during a tool-using response, then resolve/collapse.
- [ ] Image attachments persist across quit/relaunch in the transcript.

## Phase 5 — Settings + keyboard control
- [ ] Open Settings (⌘, and menu-bar).
- [ ] Record a new hotkey: it re-registers live; a taken combo reverts with an alert.
- [ ] Toggle launch-at-login; switch appearance light/dark; change host/port and model.
- [ ] ⌘W closes Settings when frontmost, otherwise hides the panel.

## Phase 6 — Voice flow
- [ ] Default (review-send): speak → field fills → edit → Return sends.
- [ ] Auto-send: sends after a silence pause.
- [ ] Push-to-talk: hold records, release sends.
- [ ] Waveform animates while capturing; no-speech returns quietly to idle.

## Phase 7 — Visual redesign (eyeball in BOTH light & dark)
- [ ] Bubble depth/gradients, status pill, empty state, waveform.
- [ ] Send/mic gradient + glow; input focus ring; crisp panel edge on a bright wallpaper.
- [ ] History selected-row wash; Settings amber tint.
- [ ] Reduce-Motion (System Settings ▸ Accessibility) flattens bubble-arrival animations.

## Phase 8 — Packaging & onboarding
- [ ] Dock / Cmd-Tab / About all show the warm-amber waveform icon.
- [ ] First-run onboarding walks welcome → mic+speech grant → hotkey step.
- [ ] Menu-bar menu: live connection line, recents (open one), New Chat, Settings, Quit.

## Cross-cutting regression pass
- [ ] **Hotkey single-fire:** one ⌃⇧H press = one toggle (no double-open). *(Logic covered by `PanelStateMachineTests`.)*
- [ ] **Single-instance:** launching a second copy doesn't start a second process (flock at `~/.hermes/hermes_voice.lock`).
- [ ] **Panel state machine:** rapid ⌃⇧H spam never desyncs show/hide. *(Transitions unit-tested.)*
- [ ] **Light/dark + Reduce-Motion:** covered per-surface above.
