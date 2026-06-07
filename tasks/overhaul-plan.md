# HermesVoice Overhaul Plan

> Single source of truth for the HermesVoice redesign + feature work. Built from a
> requirements interview (2026-06-07). Execute one **Phase** per Claude Code session.
> Each phase is dependency-ordered and individually shippable: **the app must build,
> pass tests, and launch after every phase.** This plan supersedes
> `tasks/ui-polish-plan.md` (that earlier polish pass is already done).

---

## 0. Orientation (read first)

**What the app is.** A macOS menu-bar utility (`LSUIElement`, `.accessory`
activation) that shows a Spotlight-style floating `NSPanel` on **⌃⇧H**. It captures
voice via on-device `SFSpeechRecognizer` + `AVAudioEngine`, or typed text, and streams
replies from the local **Hermes gateway** (`127.0.0.1:8642`, OpenAI-compatible SSE).
Goal of the app: talk to Hermes Agent directly from a hotkey, without opening
Telegram/Discord.

**Tech / constraints (do not change without reason):**
- Swift Package Manager only — **no Xcode project**; builds under Command Line Tools.
- Target **macOS 14+**.
- Pure, hardware-free logic lives in **`HermesVoiceKit`** and is unit-tested by a
  custom harness (`swift run HermesVoiceTests`) — XCTest is unavailable under CLT.
  Keep new testable logic in `HermesVoiceKit`.
- Single-instance via `flock` at `~/.hermes/hermes_voice.lock`.
- Global hotkey via **Carbon `RegisterEventHotKey`** (no Accessibility permission
  needed). It works — only make it *configurable* later; don't replace the mechanism.
- Panel race-safety via `PanelStateMachine` + debouncers — preserve these.
- Ad-hoc code signing (`entitlements.plist`: audio-input). No paid notarization.

**Build / run / test:**
```bash
swift build -c release          # compile
swift run HermesVoiceTests      # run the pure-logic test suite
./build-app.sh                  # produce build/HermesVoice.app (ad-hoc signed)
open build/HermesVoice.app      # launch
cp -r build/HermesVoice.app /Applications/   # install
```

**Current file map:**
```
Sources/HermesVoice/        App.swift, AppDelegate.swift, OverlayPanel.swift,
                            OverlayView.swift, OverlayViewModel.swift, VoiceEngine.swift,
                            HermesAPIClient.swift, Config.swift, HotKeyManager.swift,
                            Theme.swift, WaveformView.swift, ButtonStyles.swift
Sources/HermesVoiceKit/     SSEParser.swift, APIKeyParser.swift, PanelStateMachine.swift,
                            Debouncer.swift   (pure, tested)
Tests/HermesVoiceTests/     custom harness + *Tests.swift
Resources/Info.plist, entitlements.plist, com.hermes.voice.plist, build-app.sh
```

**FIRST, before any code:** the project is **not under version control**. Run
`git init`, commit the current state, and commit after each phase so every step is
reversible. This is the main safeguard for "don't break the app."

---

## 1. Confirmed decisions (the spec)

| Area | Decision |
|---|---|
| **Visual direction** | **Keep the warm-amber editorial identity** (`#D4816B` light / `#E8957F` dark, off-white/charcoal). Refine toward **"warm & expressive"**: subtle gradients, more depth/shadow, richer accent moments, cozy — *not* austere minimalism. Still native/premium quality (Raycast/Cleanshot tier). |
| **Panel: click-outside** | Close the panel when the user clicks outside it (today it only closes on Esc / X / hotkey). |
| **Panel: focus return** | On close, return keyboard focus to the app the user was in before opening. |
| **Panel: resize** | Fix height jitter/flicker as the conversation grows or streams. |
| **Panel: display** | Single main display is fine — **no** multi-display/Space targeting needed. |
| **Keyboard / paste** | **Cmd+V/C/X/A/Z must work** in the input field (currently broken). Plus full app keyboard control: ⌘N new chat, ⌘, settings, ⌘W close, ⌘F search history, arrows in history, Esc close/back. |
| **Data storage** | **All data stays local** under `~/.hermes/hermes_voice/` (mirrors the existing `~/.hermes/desktop/` pattern): `sessions.json` index + per-conversation transcript files. Tag `source: "hermes_voice"` locally; set `User-Agent: HermesVoice/<version>` on requests. **No changes to the Hermes server.** ("Local + discoverable" — the agent can read these files on request.) |
| **History model** | **Client-owned.** Send the full `messages` array. **Do NOT send `X-Hermes-Session-Id`** for continuation (fixes likely context double-counting). Let the server derive its own session id from the first message for grouping. |
| **On open** | **Resume the last conversation.** Start a blank one explicitly via New Chat / ⌘N. |
| **History browsing** | **In-panel searchable list** (title + preview + relative time + message count). Click to open, back to return. Delete supported. Keeps the compact panel. |
| **Settings window** | Customizable **hotkey** (with conflict detection); **model picker** (from `/v1/models`); **launch-at-login** (SMAppService); **voice behavior** (default flow, silence timeout, push-to-talk vs toggle, recognition language). Advanced: endpoint host/port (default `127.0.0.1:8642`), appearance (system/light/dark). |
| **Voice default** | **Transcribe → review → send**: speech fills the input field; user edits; Enter sends. Auto-send-on-silence and push-to-talk are selectable in Settings. |
| **Markdown** | Add **swift-markdown-ui + Highlightr** (SPM deps). Full GitHub-flavored markdown themed to the amber palette; **syntax-highlighted, copyable code blocks**; lists/tables/headings/quotes; links open in browser. |
| **Copy buttons** | Reliable, **discoverable copy on BOTH user and assistant messages** (today it's hover-only and easy to miss). |
| **Reliability** | (a) Detect gateway-offline vs HTTP/auth errors + friendly guidance; (b) connection **health indicator** (header + menu bar); (c) **auto-retry** transient failures; (d) **keep partial responses** on mid-stream drop, with retry. |
| **Packaging** | Custom **.icns app icon** (warm-amber, waveform motif); **first-run onboarding** (mic + speech perms + hotkey intro); **polished menu-bar menu** (New Chat / recents / Settings… / connection status / Quit, with key equivalents); **build/install polish** (versioned bundle, embed icon; keep ad-hoc signing). |
| **Extra features** | **Image input** (paste/drag → multimodal); **full keyboard control**; **tool-activity display** (parse `hermes.tool.progress` SSE events). |
| **Explicitly OUT** | **No TTS / spoken responses** (voice input only). No server-side Hermes changes. No multi-display targeting. |
| **Sequencing** | **Phase 1 = quick-win bug fixes** (user priority). Rest follow in dependency order below. |

---

## 2. Hermes server API reference (verified from `~/.hermes/hermes-agent/gateway/platforms/api_server.py`)

Base URL `http://127.0.0.1:8642`. Auth: `Authorization: Bearer <API_SERVER_KEY>` (read
from `~/.hermes/.env`, already handled by `APIKeyParser`/`Config`).

**`POST /v1/chat/completions`** — OpenAI-compatible, **stateless**.
- Body: `{"messages": [...], "stream": true, "model": "<optional>"}`.
- Opt-in continuity via `X-Hermes-Session-Id` header — **we deliberately DON'T send it**
  (we own history client-side; sending both history and the header can double-count).
- When no session header is sent, the server **derives a stable session id from the
  system prompt + first user message**, so multi-turn conversations still group.
- **SSE content chunks:** `data: {"object":"chat.completion.chunk","choices":[{"delta":{"content":"…"}}]}`
  terminated by `data: [DONE]`.
- **SSE tool-activity events (interleaved!):**
  ```
  event: hermes.tool.progress
  data: {"tool":"<name>","emoji":"…","label":"<preview>","toolCallId":"…","status":"running"}
  ```
  …and a later matching `…"status":"completed"`. These are **named SSE events**
  (`event:` line + following `data:` line). The current parser drops them.
- **Multimodal input:** `content` may be an array of parts — `{"type":"text","text":…}`
  and `{"type":"image_url","image_url":{"url":"data:image/png;base64,…"}}` (OpenAI
  format). *Verify exact accepted shape when implementing image input.*

**Other useful endpoints:**
- `GET /v1/models` → `{object:list, data:[{id, object:"model", …}]}` — feeds the model picker.
- `GET /v1/health` (and `/health`) → `{"status":"ok", …}` — use for the reachability indicator.
- `GET /v1/capabilities`, `/v1/skills`, `/v1/toolsets` — capability discovery (optional).
- Server-side session REST exists (`GET /api/sessions` with `id, source, model, title,
  started_at, last_active, message_count, preview, …`; `/messages`, `/fork`, etc.).
  **We are client-owned so we don't depend on these**, but they're available for
  reference/debugging.
- Errors are OpenAI-style: `{"error":{"message":…,"type":…,"code":…}}`.

---

## 3. Known bugs / gaps (root causes)

1. **Cmd+V/C/X/A/Z don't work** — accessory app has *no main menu*, so the standard
   Edit responder chain that powers these shortcuts isn't installed. Fix: add a real
   main menu with an Edit menu (standard selectors + key equivalents); ensure the panel
   is key and the field is first responder.
2. **Possible context double-counting** — `HermesAPIClient` sends the full `history` *and*
   a perpetual `X-Hermes-Session-Id` from `UserDefaults`. Stop sending the header.
3. **One perpetual session id** (`Config.sessionId`, never reset) → no "new chat" / no
   grouping. Replace with per-conversation local ids.
4. **No click-outside dismiss** — `OverlayPanel.resignKey()` is intentionally a no-op.
5. **Focus not returned** — `showPanel()` calls `NSApp.activate(ignoringOtherApps:)` and
   never restores the previously-frontmost app on hide.
6. **Resize jitter** — `ContentHeightKey` preference → `updateHeight` animation can feed
   back on itself.
7. **Tool-progress SSE events dropped** — `SSEParser` only understands `data:` content
   lines; `event:`-named lines are ignored.
8. **Conversation lost on quit** — `chatMessages` is in-memory only.
9. **Voice auto-send is fragile** — `requiresOnDeviceRecognition = true` means `isFinal`
   rarely fires; a silence timer calls `endAudio()` then auto-sends, which can fire
   prematurely. (Addressed by the new default voice flow.)

---

## 4. Phased implementation plan

> Conventions per phase: **Goal · Tasks · Files · Acceptance · Don't-break.**
> Run `swift build -c release` + `swift run HermesVoiceTests` + a launch smoke test
> (hotkey toggles panel) at the end of every phase. Commit.

### Phase 1 — Quick-win bug fixes  *(user priority; isolated, low risk)*
**Goal:** Daily use feels right; no architectural change.
**Tasks:**
- **1a. Editing shortcuts + paste.** Install a proper `NSMenu` main menu in `App.swift`
  with an **Edit** menu: Undo/Redo, Cut (`x`), Copy (`c`), Paste (`v`), Select All (`a`)
  using the standard first-responder selectors (`undo:`, `cut:`, `copy:`, `paste:`,
  `selectAll:`). Confirm the panel becomes key and the `TextField` is first responder so
  the chain resolves. (Also add an App menu with Quit `q`.)
- **1b. Click-outside to close.** While the panel is visible, install a global mouse-down
  monitor (`NSEvent.addGlobalMonitorForEvents(matching:.leftMouseDown/.rightMouseDown)`)
  and/or a local monitor; if the click is outside the panel frame → `hidePanel()`.
  Remove the monitor on hide. (Keep it from firing during show animation.)
- **1c. Focus return on close.** Before activating, capture
  `NSWorkspace.shared.frontmostApplication`. On hide, `previousApp?.activate()`. Consider
  not calling `NSApp.activate(ignoringOtherApps:)` at all — make the panel key without
  full app activation if the field still accepts input.
- **1d. Resize jitter.** Stabilize the height loop: raise the change threshold, debounce
  preference updates, ensure a single animation drives the frame, and don't re-emit the
  preference because of the animation. Verify smooth growth while typing + streaming.

**Files:** `App.swift`, `AppDelegate.swift`, `OverlayPanel.swift`, `OverlayView.swift`.
**Acceptance:** Cmd+V/C/X/A/Z work in the field; clicking outside closes; previous app
regains focus + cursor; panel resizes smoothly with no flicker.
**Don't-break:** Keep `PanelStateMachine` transitions, debouncers, single-instance lock.

### Phase 2 — Data & API foundation  *(mostly invisible; enables features)*
**Goal:** Local persistence + correct streaming + reliability primitives.
**Tasks:**
- **2a. ConversationStore** (logic in `HermesVoiceKit`, file IO in app layer). Write/read
  `~/.hermes/hermes_voice/sessions.json` (index: `{id, title, startedAt, lastActiveAt,
  source:"hermes_voice", messageCount, model}`) and `transcripts/<id>.jsonl`
  (append `{role, content, ts}` per message). Atomic writes (temp + rename). Derive title
  from the first user message (trimmed).
- **2b. Conversation model + resume-last.** Introduce a `Conversation` type; have
  `OverlayViewModel` own the *current* conversation, persist on every change, and **load
  the most recent conversation on launch**.
- **2c. Continuity fix.** Stop sending `X-Hermes-Session-Id`. Keep sending the full
  `messages` array. Keep a stable local conversation id. **Verify** (Hermes logs / token
  counts) there's no double-counting.
- **2d. SSE upgrade.** Extend `HermesAPIClient` + `SSEParser` to track `event:` lines and
  pair them with the next `data:` line. Recognize `hermes.tool.progress` → surface a
  `ToolActivity` event; keep content chunks + `[DONE]`. Add `HermesVoiceKit` tests for the
  named-event parsing.
- **2e. Reliability primitives.** Classify errors: `offline` (connection refused) vs
  `http/auth` vs `streamDropped`. Add a `/v1/health` reachability check. Auto-retry
  transient failures (small bounded retry w/ backoff). On mid-stream drop, **keep the
  partial assistant text**, mark it incomplete, expose a retry.

**Files:** new `ConversationStore.swift` (Kit + app IO wrapper), `SSEParser.swift`,
`HermesAPIClient.swift`, `OverlayViewModel.swift`, `Config.swift`, tests.
**Acceptance:** conversations survive quit/relaunch; no double-counting; tool events
parsed (unit-tested); killing Hermes surfaces an offline state; a dropped stream keeps
partial text.
**Don't-break:** Existing SSE content path must still work; `User-Agent: HermesVoice/<v>`
added to all requests.

### Phase 3 — Conversation features (history, new chat, copy)
**Goal:** Manage multiple conversations.
**Tasks:**
- **3a. New Chat** — header button + ⌘N + menu-bar item: save current, start fresh
  conversation, focus input.
- **3b. In-panel history browser** — a history button flips the panel to a **searchable
  list** (title, preview, relative time, message count). Search filters live. Click opens;
  back returns. Delete a conversation (removes its local files). Keyboard: ⌘F focus
  search, ↑/↓ navigate, Enter open, Esc back.
- **3c. Copy buttons** — reliable, discoverable copy on **both** user and assistant
  bubbles (clear affordance, "Copied" feedback). Copies the full message text.

**Files:** new `HistoryView.swift`, `OverlayView.swift`, `OverlayViewModel.swift`,
`App.swift` (menu).
**Acceptance:** browse/search/open/delete past chats; ⌘N starts fresh and saves the old;
copy works on both roles.

### Phase 4 — Rich content (markdown, images, tool activity)
**Goal:** Render agent output well; richer I/O.
**Tasks:**
- **4a. Dependencies** — add `swift-markdown-ui` + `Highlightr` to `Package.swift` (pin
  versions). Confirm they resolve under `swift build` with CLT.
- **4b. Markdown rendering** — replace inline-only rendering in the assistant bubble with
  MarkdownUI, themed to the amber palette via `Theme`. Code blocks: syntax-highlighted
  (Highlightr) + **per-block copy button**. Lists/tables/headings/quotes; links open in
  browser. Ensure partial/streaming markdown renders without flping layout.
- **4c. Image input** — paste (Cmd+V image) + drag-drop into the panel → show a thumbnail
  chip in the input; on send, build multimodal `content` parts (text + `image_url` data
  URL). Render attached images in the user bubble. *Verify the server's accepted image
  part shape first.*
- **4d. Tool-activity display** — render `ToolActivity` events (from 2d) as ephemeral
  "Hermes is using {emoji} {label}…" rows during a response; resolve/collapse on
  `status:"completed"`. Do **not** persist these markers in the transcript.

**Files:** new `MarkdownMessageView.swift`, `OverlayView.swift`, `OverlayViewModel.swift`,
`HermesAPIClient.swift`, `Package.swift`.
**Acceptance:** code blocks highlighted + copyable; tables/lists render; pasting/dragging
an image sends it and Hermes responds to it; tool steps appear live then resolve.

### Phase 5 — Settings + full keyboard control
**Goal:** Make hardcoded behavior configurable; native shortcuts everywhere.
**Tasks:**
- **5a. Settings window** (dedicated window for the accessory app; or SwiftUI `Settings`
  scene). Tabs: **General / Voice / Connection / Shortcuts.**
  - **Hotkey recorder** with conflict detection; re-register `HotKeyManager` live.
  - **Model picker** from `/v1/models`; persist; send as `body.model`. *Verify the server
    honors a per-request model; if model is global, drive whatever mechanism works or hide
    the control.*
  - **Launch-at-login** via `SMAppService.mainApp` (supersedes the launchd plist reliance).
  - **Voice:** default flow (transcribe-review-send / auto-send / push-to-talk), silence
    timeout, recognition language.
  - **Advanced:** endpoint host/port (default `127.0.0.1:8642`), appearance
    (system/light/dark).
- **5b. Full keyboard control** — wire ⌘, (settings), ⌘W (close), ⌘N (new), ⌘F (search),
  Esc (close/back) through the main menu so they work app-wide; arrows in history list.

**Files:** new `SettingsView.swift` + window controller, `AppSettings` (UserDefaults-backed;
pure parts in Kit), `HotKeyManager.swift`, `App.swift`.
**Acceptance:** change hotkey live; switch model; toggle launch-at-login; switch voice
default; all shortcuts work.

### Phase 6 — Voice flow change
**Goal:** Make voice "accurate" by default.
**Tasks:**
- **6a.** Implement **transcribe → review → send** as default: on stop/silence, fill the
  input field with the transcript and focus it; **do not auto-send**; Enter sends. Honor
  the Settings choice for auto-send and push-to-talk (hold-to-record, release-to-send).
- **6b.** Robustness: keep on-device recognition; handle no-speech and locale-unsupported
  gracefully; keep the live waveform during capture.

**Files:** `VoiceEngine.swift`, `OverlayViewModel.swift`, `WaveformView.swift`, settings.
**Acceptance:** default = speak → field fills → edit → Enter; settings switch modes;
waveform animates while capturing.

### Phase 7 — Expressive visual redesign  *(warm & expressive)*
**Goal:** Cozy, deep, richly-amber — yet native/premium. Applies to **all** surfaces.
**Tasks:**
- **7a. Theme evolution** in `Theme.swift`: richer amber usage, subtle gradients (mic/send
  buttons, header tint), layered depth/shadow, refined materials, cozy spacing,
  light/dark parity. Keep all tokens centralized.
- **7b. Component polish:** message bubbles (depth + gradient tint), status pill, empty
  state, waveform, history rows, buttons (gradient/hover/press), panel chrome, spring
  motion (respect reduce-motion via `Theme.Motion.ifMotion`).
- **7c.** Ensure the redesign covers new surfaces (history, settings, onboarding).

**Files:** `Theme.swift`, `ButtonStyles.swift`, `OverlayView.swift`, `WaveformView.swift`,
all new views.
**Acceptance:** warm/expressive and consistent across light/dark; no perf regressions
(smooth animations).

### Phase 8 — Native packaging & onboarding
**Goal:** Feels installed and first-class.
**Tasks:**
- **8a. App icon** — design an `.icns` (warm-amber, waveform motif) at all sizes; embed in
  the bundle (`CFBundleIconFile` / AppIcon); shows in Dock/Cmd-Tab/About.
- **8b. First-run onboarding** — small flow: welcome → explained mic + speech permission
  prompts → "your hotkey is ⌃⇧H" → done. First launch only.
- **8c. Menu-bar menu** — New Chat · Recent conversations (last N) · Settings… ·
  connection status line · Quit, with key equivalents.
- **8d. Build/install polish** — `build-app.sh` embeds the icon, bumps `CFBundleVersion`,
  validates the bundle; keep ad-hoc sign + entitlements; document install/update; migrate
  autostart to `SMAppService` (retire `com.hermes.voice.plist` if appropriate).

**Files:** `build-app.sh`, `Resources/Info.plist`, new AppIcon assets,
`OnboardingView.swift`, `App.swift`, `com.hermes.voice.plist`.
**Acceptance:** real Dock icon; clean first-run; rich menu; reproducible versioned bundle.

### Phase 9 — QA, tests, verification
**Goal:** Lock it in.
**Tasks:**
- Expand `HermesVoiceKit` tests: SSE named-event/tool parsing, ConversationStore
  round-trip + atomic writes, settings serialization, error classification, hotkey-string
  formatting.
- Manual verification checklist per feature; regression pass on hotkey single-fire,
  single-instance, panel state machine, light/dark, reduce-motion.
- Confirm release build + tests green.

---

## 5. Cross-cutting rules ("don't break the app")
- **Per phase:** build (release) + tests + launch smoke test must pass; then commit.
- Keep new pure logic in **`HermesVoiceKit`** with tests; no AppKit there.
- Preserve the **Carbon hotkey**, **flock single-instance**, **PanelStateMachine**, and
  **debouncers**. Only Phase 5 makes the hotkey configurable.
- Stay on **SPM / no Xcode**; verify any new dependency resolves under CLT.
- One phase per session; rely on git checkpoints for rollback.

## 6. Open items to verify during implementation
1. Confirm `/v1/chat/completions` double-counts when both full history **and**
   `X-Hermes-Session-Id` are sent (validates the Phase 2c fix).
2. Does the server honor a per-request **`model`** in the body, or is the model global?
   (Shapes the Phase 5 model picker.)
3. Exact **multimodal image** content-part schema accepted (Phase 4c).
4. Server-derived session-id grouping behaves as expected with no header (Phase 2c).
5. `/v1/health` response shape + latency for the health indicator (Phase 2e / 8c).
