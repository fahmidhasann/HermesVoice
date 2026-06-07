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
✅ **Done (2026-06-07):** repo initialized, `.gitignore` added (excludes
`.build/`, `build/`, `.DS_Store`), baseline committed (`abf874b`), Phase 1
committed (`63861e9`).

---

## Progress tracker

| Phase | Status |
|---|---|
| **1 — Quick-win bug fixes** | ✅ **Done (2026-06-07)** — commit `63861e9` |
| **2 — Data & API foundation** | ✅ **Done (2026-06-07)** |
| **3 — Conversation features** | ✅ **Done (2026-06-07)** |
| **4 — Rich content** | ✅ **Done (2026-06-07)** |
| **5 — Settings + keyboard control** | ✅ **Done (2026-06-07)** |
| **6 — Voice flow change** | ✅ **Done (2026-06-07)** |
| **7 — Expressive visual redesign** | ✅ **Done (2026-06-07)** |
| **8 — Native packaging & onboarding** | ✅ **Done (2026-06-07)** |
| **9 — QA, tests, verification** | ✅ **Done (2026-06-07)** |

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

### Phase 1 — Quick-win bug fixes  *(user priority; isolated, low risk)*  ✅ DONE (2026-06-07, commit `63861e9`)
**Goal:** Daily use feels right; no architectural change.
**Tasks:**
- [x] **1a. Editing shortcuts + paste.** Installed a real `NSMenu` main menu in `App.swift`
  (`makeMainMenu()`): an **App** menu (About, Quit `q`) and an **Edit** menu —
  Undo/Redo, Cut (`x`), Copy (`c`), Paste (`v`), Select All (`a`) using the standard
  first-responder selectors (`undo:`/`redo:`, `cut:`/`copy:`/`paste:`/`selectAll:`),
  target `nil` so they route through the field-editor responder chain. Panel already
  `canBecomeKey`; `OverlayView.onAppear` makes the field first responder.
- [x] **1b. Click-outside to close.** `AppDelegate` installs a global mouse-down monitor
  (`.leftMouseDown/.rightMouseDown/.otherMouseDown`) → `hidePanel()`. Armed only in the
  show-animation completion handler (so the opening click can't dismiss); removed on hide.
  Global monitors only see other-app events, so clicks inside the panel don't trigger it.
- [x] **1c. Focus return on close.** `showPanel()` captures
  `NSWorkspace.shared.frontmostApplication` into `previousApp`; `hidePanel()` calls
  `previousApp.activate()` (skipped if it's our own bundle). Kept `NSApp.activate` for
  reliable field focus — restoring the prior app on close still returns focus correctly.
- [x] **1d. Resize jitter.** Root cause: `updateHeight` gated against the *live*
  (mid-animation) `frame.height`, re-issuing the same target each frame and restarting the
  animation. Now gates against a stored `targetHeight`, rounds to whole points, and drives
  a single animation (`Theme.Layout.heightDuration`).

**Files:** `App.swift`, `AppDelegate.swift`, `OverlayPanel.swift`, `OverlayView.swift`.
**Acceptance:** Cmd+V/C/X/A/Z work in the field; clicking outside closes; previous app
regains focus + cursor; panel resizes smoothly with no flicker.
**Don't-break:** Keep `PanelStateMachine` transitions, debouncers, single-instance lock.

**Verification status:** `swift build -c release` ✅ · `swift run HermesVoiceTests` →
42 checks, 0 failures ✅ · launch smoke test (bundle launches, lock acquired, status
item + hotkey registered, no crash, clean quit + lock released) ✅.
⚠️ **Still needs a manual on-device pass** (couldn't be automated headlessly): actually
typing Cmd+V/C/X/A/Z in the field, clicking outside to dismiss, ⌃⇧H toggle, and watching
for smooth resize while streaming.

### Phase 2 — Data & API foundation  *(mostly invisible; enables features)*  ✅ DONE (2026-06-07)
**Goal:** Local persistence + correct streaming + reliability primitives.

**What shipped:**
- **2a.** Pure `ConversationStore` in `HermesVoiceKit` (`SessionMeta`/`TranscriptRecord`
  models, index encode/decode, JSONL transcript encode/decode, title derivation, upsert
  sorted most-recent-first). App-layer `ConversationFileStore` does atomic (temp+rename)
  IO under `~/.hermes/hermes_voice/` — `sessions.json` index + `transcripts/<id>.jsonl`.
- **2b.** `OverlayViewModel` owns the current conversation (`conversationId` +
  `conversationStartedAt`), persists each user/assistant message, and **resumes the most
  recent conversation on launch**. `clearConversation()` now starts a fresh conversation
  (old one stays saved). `ChatMessage` gained an injectable `timestamp` + `isIncomplete`.
- **2c.** Stopped sending `X-Hermes-Session-Id`; client sends the full `messages` array via
  `streamCompletion(messages:)`. **Verified** against the live gateway: identical repeated
  requests *without* the header are stable (prompt_tokens 20659 → 20659), *with* a
  perpetual header they grow (20639 → 20648) — confirming server-side accumulation /
  double-counting (open items #1, #4). Removed the perpetual `Config.sessionId`.
- **2d.** Added stateful `SSEStreamParser` that pairs `event:` lines with the following
  `data:` line, decoding `hermes.tool.progress` → `ToolActivity` (running/completed).
  `OverlayViewModel.activeTools` tracks live tool steps (rendering is Phase 4d). Stateless
  `SSEParser` kept for the content path. 7 new parser tests.
- **2e.** Pure `HermesErrorClassifier` (offline / auth / http / streamDropped / timeout +
  `isTransient`). `HermesAPIError` carries a `kind` and friendly guidance. Client returns
  an `AsyncThrowingStream` so mid-stream drops throw; the VM keeps partial text (marked
  `isIncomplete`), auto-retries transient failures *before any content arrives* (bounded,
  backoff), and exposes `retryLast()` (retry button wired in `OverlayView`). `/v1/health`
  reachability check drives `connectionState`, refreshed when the panel opens.
  `User-Agent: HermesVoice/<version>` added to all requests (verified `/v1/health` →
  `{"status":"ok","platform":"hermes-agent"}`).

**Verification:** `swift build -c release` ✅ · `swift run HermesVoiceTests` → 85 checks,
0 failures ✅ · launch smoke test via `open` (lock acquired, resume-last with seeded data
does not crash, clean quit + lock released) ✅ · live-gateway protocol checks for 2c/2e ✅.
⚠️ **Still needs a manual on-device pass:** real send → quit → relaunch resume; killing the
gateway mid-send to watch the offline state + retry; observing a kept partial on drop.

**Files added:** `Sources/HermesVoiceKit/{ConversationStore,HermesError}.swift`,
`Sources/HermesVoice/ConversationFileStore.swift`,
`Tests/HermesVoiceTests/{ConversationStoreTests,HermesErrorTests}.swift`.

<details><summary>Original task list</summary>

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

</details>

### Phase 3 — Conversation features (history, new chat, copy)  ✅ DONE (2026-06-07)
**Goal:** Manage multiple conversations.

**What shipped:**
- **3a. New Chat** — header **square.and.pencil** button (always present),
  Chat ▸ New Chat **⌘N**, and a menu-bar **New Chat** item. `OverlayViewModel.newChat()`
  resets to a fresh, unregistered conversation via `startBlankConversation()` (the old one
  stays persisted; the new id is written to the index only on first send) and refocuses
  the input. The menu-bar variant (`menuBarNewChat`) shows the panel first if hidden so it
  works when the app isn't already active. Replaced the old `clearConversation()`.
- **3b. In-panel history browser** — new `HistoryView.swift`. A header
  **clock.arrow.circlepath** button (and ⌘F) flips the panel to a searchable list
  (title, last-message preview, relative time, message count). `viewModel.openHistory()`
  loads the index + previews; `filteredHistory` filters live via
  `ConversationStore.matchesQuery`. Click (or Enter) opens via `openConversation(id:)`
  which loads that transcript into the thread; back chevron / Esc returns. Trash on row
  hover calls `deleteConversation(id:)` → `ConversationFileStore.deleteConversation`
  (removes index entry + `transcripts/<id>.jsonl`; if the open chat is deleted it falls
  back to a blank one). Keyboard: ⌘F focus search, ↑/↓ move selection (scrolls into view),
  Enter open, Esc back.
- **3c. Copy buttons** — the per-bubble copy button is now **always visible** (subtle at
  rest, full-strength on hover) on **both** user and assistant bubbles, with the existing
  "Copied" checkmark feedback. Copies the full message text.

**New pure logic (HermesVoiceKit, tested):** `ConversationStore.previewText(from:)`
(collapse + truncate), `matchesQuery(title:preview:query:)` (case-insensitive),
`relativeTime(from:now:)` ("just now"/m/h/d/w → "MMM d"). `ConversationFileStore` gained
`loadPreview(id:)`.

**Files added/changed:** new `Sources/HermesVoice/HistoryView.swift`;
`OverlayView.swift`, `OverlayViewModel.swift`, `App.swift`, `AppDelegate.swift`,
`ConversationFileStore.swift`, `HermesVoiceKit/ConversationStore.swift`,
`Tests/HermesVoiceTests/ConversationStoreTests.swift`.

**Verification:** `swift build -c release` ✅ · `swift run HermesVoiceTests` → 101 checks,
0 failures ✅ · launch smoke test via `open` (launches, runs, clean quit + lock released) ✅.
⚠️ **Still needs a manual on-device pass:** open history → search/↑↓/Enter/Esc; delete a
conversation (incl. the open one); ⌘N + menu-bar New Chat; copy on both roles.

<details><summary>Original task list</summary>

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

</details>

### Phase 4 — Rich content (markdown, images, tool activity)  ✅ DONE (2026-06-07)
**Goal:** Render agent output well; richer I/O.

**What shipped:**
- **4a. Dependencies** — added `swift-markdown-ui` (exact **2.4.1**) + `Highlightr`
  (exact **2.3.0**) to `Package.swift`; both resolve and build under CLT (Swift 6.3,
  transitive `swift-cmark`/`NetworkImage` pulled automatically). `build-app.sh` now copies
  every SwiftPM `*.bundle` from `.build/release/` into the app's `Resources/` so
  Highlightr's `Bundle.module` (highlight.js + CSS themes) resolves at runtime — verified
  `Highlightr_Highlightr.bundle/highlight.min.js` lands in the built bundle.
- **4b. Markdown rendering** — new `MarkdownMessageView.swift` renders assistant bubbles
  with MarkdownUI on a custom amber `Theme.hermes` (text/links/inline-code/blockquote).
  Fenced code blocks use a Highlightr-backed `CodeSyntaxHighlighter` (`atom-one-light`/
  `atom-one-dark` by appearance, monospaced 12pt) inside a custom code-block style with a
  language label + **per-block copy button** and horizontal scroll. Lists/tables/headings
  inherit `.basic`; links open in the browser via the default `openURL`. Streams
  incrementally (re-renders as content grows). Replaced the old inline-only
  `AttributedString` path in `MessageBubble`.
- **4c. Image input** — paste (⌘V image via `AppDelegate.smartPaste`, falling back to text
  paste) + drag-drop (`.onDrop` of `.image`/`.fileURL` with a dashed accent target) stage
  images as thumbnail chips above the input (`PendingImageChip`, removable, capped at
  `maxAttachments = 6`). On send, `OutgoingMessage.contentJSON` builds OpenAI multimodal
  `content` parts (text + `image_url` data URL); text-only stays a plain string. Attached
  images render in the user bubble and **persist** in the transcript (`TranscriptRecord`
  gained optional `images: [String]?`, backward-compatible decode). `ImageEncoder`
  downscales to ≤1280px and encodes PNG data URLs. **Verified live:** the gateway accepts
  the exact shape (200/SSE, no `invalid_image`) — open item #3 below.
- **4d. Tool-activity display** — `ToolActivityRow` renders live "Hermes is using {emoji}
  {label}…" rows (from `viewModel.activeTools`, populated by the 2d parser) in the thread
  while a response streams; rows collapse as steps complete and are **never persisted**.

**New pure logic (HermesVoiceKit, tested):** `TranscriptRecord.images` round-trip +
missing-key backward-compat (2 new tests).

**Files added/changed:** new `Sources/HermesVoice/{MarkdownMessageView,ImageAttachment}.swift`;
`OverlayView.swift`, `OverlayViewModel.swift`, `HermesAPIClient.swift`, `App.swift`,
`AppDelegate.swift`, `Package.swift`, `build-app.sh`,
`HermesVoiceKit/ConversationStore.swift`, `Tests/HermesVoiceTests/ConversationStoreTests.swift`.

**Verification:** `swift build -c release` ✅ · `swift run HermesVoiceTests` → 106 checks,
0 failures ✅ · live-gateway multimodal check (text+image → "OK", no 400) ✅ · `./build-app.sh`
embeds the Highlightr bundle ✅ · launch smoke test via `open` (launches, lock acquired,
no crash, clean quit) ✅.
⚠️ **Still needs a manual on-device pass:** render a real markdown reply (code block
highlight + copy, tables/lists); paste & drag an image and confirm Hermes answers about it;
watch tool-activity rows appear/resolve during a tool-using response.

<details><summary>Original task list</summary>

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

</details>

### Phase 5 — Settings + full keyboard control  ✅ DONE (2026-06-07)
**Goal:** Make hardcoded behavior configurable; native shortcuts everywhere.

**What shipped:**
- **5a. Settings window** — new `SettingsView.swift` (SwiftUI `TabView`) hosted in a
  reusable titled `NSWindow` via `SettingsWindowController` (lazy, `isReleasedWhenClosed
  = false`, activates the accessory app so it can take key focus). Tabs:
  **General** (appearance segmented picker · launch-at-login toggle), **Voice**
  (default-flow picker · silence-timeout slider · recognition-language picker),
  **Connection** (host/port fields · model picker), **Shortcuts** (hotkey recorder +
  reset). All controls bind into `AppSettingsStore.shared.settings`.
  - **Hotkey recorder** (`HotKeyRecorder.swift`): click-to-record via a local
    `.keyDown` monitor; ignores bare modifier keys, requires ≥1 modifier, Esc cancels.
    Translates AppKit flags → Carbon mask. `HotKeyManager.update(…)` re-registers live
    and **reverts to the prior combo + shows an alert** when Carbon rejects it (real
    conflict detection via `RegisterEventHotKey` status).
  - **Model picker** from `/v1/models` (`HermesAPIClient.fetchModels()`), persisted and
    sent as `body.model`. *(See open item #2 below — the gateway is effectively
    single-model; the value is accepted but doesn't switch behavior. Picker kept,
    future-proof.)*
  - **Launch-at-login** via `SMAppService.mainApp` (register/unregister, idempotent,
    errors swallowed in dev). Existing `com.hermes.voice.plist` left for Phase 8.
  - **Voice** silence-timeout + recognition-language plumbed into `VoiceEngine`
    (refreshed on each `startRecording`; recognizer rebuilt only when the locale id
    changes). Default-flow stored for Phase 6 to consume.
  - **Advanced:** endpoint host/port drive `HermesAPIClient` endpoints (resolved
    per-request from live settings, no restart); appearance applied via
    `NSApp.appearance`.
- **5b. Full keyboard control** — App menu **Settings… ⌘,** and a Window menu
  **Close ⌘W** (`closeFrontWindow`: closes the Settings window when frontmost, else
  hides the panel). ⌘N / ⌘F / Esc / history arrows already wired (Phases 1/3).
  `AppDelegate` subscribes to the settings store (`Combine`, `receive(on: .main)`),
  diffing against `appliedSettings` so each side effect (hotkey/appearance/launch) only
  fires on real change.

**New pure logic (HermesVoiceKit, tested):** `AppSettings` (Codable, per-field tolerant
decode so future fields never wipe saved settings), `VoiceFlow` / `AppearanceMode`
enums, `HotKeyFormatter` (Carbon modifier masks, canonical-order glyphs, key-code names,
display strings, validity). 10 new tests (`AppSettingsTests`) — 130 checks total.

**Files added:** `Sources/HermesVoiceKit/AppSettings.swift`,
`Sources/HermesVoice/{AppSettingsStore,SettingsView,HotKeyRecorder,SettingsWindowController}.swift`,
`Tests/HermesVoiceTests/AppSettingsTests.swift`.
**Files changed:** `HermesAPIClient.swift` (settings-driven endpoints + model + fetchModels),
`HotKeyManager.swift` (revertable live re-register), `VoiceEngine.swift` (settings),
`App.swift` (menus), `AppDelegate.swift` (store subscription + side effects + actions),
`Tests/…/main.swift`.

**Verification:** `swift build -c release` ✅ (no warnings) · `swift run HermesVoiceTests`
→ 130 checks, 0 failures ✅ · `./build-app.sh` ✅ · launch smoke test via `open`
(launches, lock acquired, no crash, clean quit) ✅ · live-gateway checks for the model
path ✅.
⚠️ **Still needs a manual on-device pass:** open Settings (⌘, / menu-bar); record a new
hotkey and confirm it re-registers live + a taken combo reverts with the alert; toggle
launch-at-login; switch appearance light/dark; change host/port and model; ⌘W closes
Settings then hides panel.

<details><summary>Original task list</summary>

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

</details>

### Phase 6 — Voice flow change  ✅ DONE (2026-06-07)
**Goal:** Make voice "accurate" by default.

**What shipped:**
- **6a. Transcribe → review → send is now the default.** `AppSettings.default.voiceFlow`
  flipped from `.autoSend` to `.reviewSend`. `VoiceEngine` was made **flow-agnostic**: it
  captures audio + transcribes and delivers the result via a single `onFinalResult`; it no
  longer decides whether to send. New `startRecording(autoStopOnSilence:)`, `finish()`
  (deliver transcript exactly once, guarded by `didFinish`), and `stopRecording()`/
  `teardown()` (cancel without delivering). The **routing decision is pure logic** in
  `HermesVoiceKit`: `VoiceFlow.outcome(for:) → .ignore / .fill / .send` and
  `VoiceFlow.stopsOnSilence`. `OverlayViewModel.handleTranscript(_:)` consumes it —
  `reviewSend` **fills the input field** (appending to any typed text) and refocuses
  without sending; `autoSend` and `pushToTalk` send immediately. **Push-to-talk** is a
  hold-to-record control: the mic button becomes a `DragGesture(minimumDistance: 0)` (press
  → `startHoldRecording`, release → `endHoldRecording` → finalize+send) when the flow is
  PTT, styled to match `CircleButtonStyle`; tap-to-toggle is preserved for the other modes.
- **6b. Robustness.** On-device recognition kept (`requiresOnDeviceRecognition = true`).
  Silence now **finalizes from the accumulated partial transcript** instead of calling
  `endAudio()` and waiting on the flaky on-device `isFinal` (root-cause fix for bug #9);
  silence auto-stop is also gated on `hasReceivedSpeech` so a pre-speech pause can't cut
  recording off early. No-speech (empty transcript, or recognition error codes 1/216)
  resolves gracefully to `.ignore` → returns to idle quietly. Unsupported recognition
  locales already fall back to the system locale in `applyVoiceSettings`. The live waveform
  + transcription preview during capture are unchanged.

**New pure logic (HermesVoiceKit, tested):** `VoiceFlow.stopsOnSilence`,
`VoiceFlow.TranscriptOutcome`, `VoiceFlow.outcome(for:)`. 7 new tests
(`VoiceFlowTests`) — **145 checks total**.

**Files changed:** `Sources/HermesVoiceKit/AppSettings.swift` (default flow + routing
logic), `Sources/HermesVoice/{VoiceEngine,OverlayViewModel,OverlayView,SettingsView}.swift`,
`Tests/HermesVoiceTests/{VoiceFlowTests.swift,main.swift}`. (`WaveformView.swift`
needed no change — it already animates from `audioLevel` during capture.)

**Verification:** `swift build -c release` ✅ · `swift run HermesVoiceTests` → 145 checks,
0 failures ✅ · `./build-app.sh` ✅ · launch smoke test via `open` (launches, lock acquired,
clean quit + lock released) ✅.
⚠️ **Still needs a manual on-device pass:** default flow — speak → field fills → edit →
Return sends; switch to auto-send and confirm it sends after a pause; switch to push-to-talk
and confirm hold-records / release-sends; confirm the waveform animates while capturing and
no-speech returns quietly to idle.

<details><summary>Original task list</summary>

- **6a.** Implement **transcribe → review → send** as default: on stop/silence, fill the
  input field with the transcript and focus it; **do not auto-send**; Enter sends. Honor
  the Settings choice for auto-send and push-to-talk (hold-to-record, release-to-send).
- **6b.** Robustness: keep on-device recognition; handle no-speech and locale-unsupported
  gracefully; keep the live waveform during capture.

**Files:** `VoiceEngine.swift`, `OverlayViewModel.swift`, `WaveformView.swift`, settings.
**Acceptance:** default = speak → field fills → edit → Enter; settings switch modes;
waveform animates while capturing.

</details>

### Phase 7 — Expressive visual redesign  *(warm & expressive)*  ✅ DONE (2026-06-07)
**Goal:** Cozy, deep, richly-amber — yet native/premium. Applies to **all** surfaces.

**What shipped:**
- **7a. Theme evolution.** `Theme.swift` gained an **amber ramp** (`accent` /
  `accentBright` / `accentDeep`, light+dark) feeding a new **`Gradients`** group —
  `accent` (primary action), `recording` (live capture), `userBubble`,
  `assistantBubble`, and a faint `header` wash — all built from appearance-resolved
  colours so light/dark parity is automatic. Added a **`Depth`** group (two elevation
  steps: near-invisible `bubble` lift + warm `actionGlow` under the send button), a
  **`Radius`** group (`bubble`/`control`/`chip`), an `accentSoft` wash, a `hairline`
  edge colour, and a livelier `springBubble` motion token plus a `Motion.reduceMotion`
  flag. Every token stays centralized; gradients are **purposeful** (action + live
  state), never decorative — and no gradient-text.
- **7b. Component polish.**
  - **Buttons** (`ButtonStyles.swift`): send button is now an amber **gradient disc**
    with a domed top-highlight + warm glow, flattening to a muted disc when disabled;
    mic toggle fills with the **recording gradient** + red glow when active; icon
    buttons get a clean hover/press wash. All keep distinct rest/hover/press/disabled
    states.
  - **Message bubbles** (`OverlayView.swift`): role-tinted **gradient fill** (amber
    whisper for user, neutral lift for assistant) on a continuous-rounded surface with
    a hairline edge + a faint drop shadow for depth; arrival is a gentle **spring**
    (scale+offset from the correct corner), reduce-motion safe.
  - **Status pill**: the header dot+label now sits in a **state-tinted capsule** (live
    connection/state read at a glance).
  - **Empty state**: layered amber halo + gradient disc behind a gradient `waveform`
    glyph; cozier copy chip.
  - **Waveform**: gradient capsule bars with a centre-weighted edge fade on a soft amber
    wash.
  - **Input field** (chat + history search): continuous-rounded surface with a hairline
    that lights to an **amber focus ring**.
  - **Panel chrome** (`OverlayPanel.swift`): added a hairline edge so the panel reads
    crisp on bright wallpapers + a deeper/softer drop shadow for a grounded float.
  - Tool-activity rows + transcription preview re-themed onto the `accentSoft` /
    recording washes with hairlines.
- **7c. New surfaces covered.** History rows use a **soft amber gradient wash + hairline**
  for the selected/keyboard-focused row (no side-stripe) and a faint neutral hover; the
  history empty-state icon uses the accent gradient. The **Settings** window keeps native
  macOS form/`TabView` idioms (earned familiarity) but inherits the warm-amber identity via
  `.tint(Theme.Colors.accent)` (selected tab, toggles, slider, pickers, the hotkey
  recorder). *(Onboarding is Phase 8 — not yet a surface.)*

**Files changed:** `Theme.swift`, `ButtonStyles.swift`, `WaveformView.swift`,
`OverlayView.swift`, `OverlayPanel.swift`, `HistoryView.swift`, `SettingsView.swift`.
No new files; no logic changes (pure-logic suite untouched).

**Verification:** `swift build -c release` ✅ (no warnings) · `swift run HermesVoiceTests`
→ 145 checks, 0 failures ✅ · `./build-app.sh` (clean) embeds the Highlightr bundle ✅ ·
launch smoke test via `open` (launches, lock acquired, clean quit + lock released) ✅.
⚠️ **Still needs a manual on-device pass** (couldn't be automated — sending the ⌃⇧H
keystroke and screen-capture both require Accessibility/Screen-Recording permission this
process doesn't hold): eyeball the panel in **both light & dark** — bubble depth/gradients,
status pill, empty state, waveform, send/mic gradient + glow, input focus ring, panel edge;
history selected-row wash; Settings amber tint; and confirm **reduce-motion** flattens the
arrivals.

<details><summary>Original task list</summary>

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

</details>

### Phase 8 — Native packaging & onboarding  ✅ DONE (2026-06-07)
**Goal:** Feels installed and first-class.

**What shipped:**
- **8a. App icon** — a programmatic renderer (`tools/make-icon.swift`, CoreGraphics)
  draws the warm-amber identity: a macOS squircle with a diagonal amber gradient + a
  cream **waveform** motif (the same voice language as the menu-bar glyph / empty state).
  `tools/generate-icns.sh` renders every iconset size sharply (16→1024, incl. @2x) and
  packs `Resources/AppIcon.icns` via `iconutil` (committed, so a normal build needs no
  render step). `Info.plist` gained `CFBundleIconFile`/`CFBundleIconName = AppIcon`;
  `build-app.sh` embeds the `.icns` → shows in Dock / Cmd-Tab / About.
- **8b. First-run onboarding** — new `OnboardingView.swift` (3 steps: welcome → mic +
  speech permission prompts with live granted/denied status → "your hotkey is ⌃⇧H")
  hosted in `OnboardingWindowController` (borderless titlebar, no close button so the
  flag is only ever set via Skip/Done). Gated by the `hermesVoiceHasOnboarded`
  UserDefaults flag; `AppDelegate.showOnboardingIfNeeded()` runs it once on first launch,
  then opens the panel. Permission prompts go through `AVCaptureDevice.requestAccess` +
  `SFSpeechRecognizer.requestAuthorization`; a denial still lets the flow continue.
- **8c. Menu-bar menu** — menu construction moved from `App.swift` into `AppDelegate`,
  which is now the menu's `NSMenuDelegate` and **rebuilds it on every open**
  (`menuNeedsUpdate`): a live **connection line** (●/○ from `connectionState`, refreshed
  each open), **New Chat ⌘N**, Open HermesVoice (⌃⇧H), a **Recent** section (last 5 via
  new `OverlayViewModel.recentSessions(limit:)`, click → show panel + `openConversation`),
  **Settings… ⌘,**, and **Quit ⌘Q** — all with key-equivalent glyphs.
- **8d. Build/install polish** — `build-app.sh` now starts from a clean bundle
  (reproducible; fixes stale read-only SwiftPM `.bundle` copy failures), embeds the icon,
  stamps `CFBundleVersion` from the git commit count (marketing version stays in
  `CFBundleShortVersionString`), and **validates** the result (`plutil -lint` + `codesign
  --verify --strict` + icon-present check) before declaring success. Keeps ad-hoc sign +
  entitlements. Documents install/update (replace-then-copy). Autostart fully migrated to
  `SMAppService` (Phase 5) — the redundant `com.hermes.voice.plist` launchd file was
  **removed**.

**New files:** `tools/make-icon.swift`, `tools/generate-icns.sh`, `Resources/AppIcon.icns`,
`Sources/HermesVoice/{OnboardingView,OnboardingWindowController}.swift`.
**Files changed:** `build-app.sh`, `Resources/Info.plist`, `App.swift`, `AppDelegate.swift`,
`OverlayViewModel.swift`. **Removed:** `com.hermes.voice.plist`.

**Verification:** `swift build -c release` ✅ · `swift run HermesVoiceTests` → 145 checks,
0 failures ✅ · `./build-app.sh` (clean) — icon embedded, `CFBundleVersion` stamped (build
13), `plutil`/`codesign` validation pass ✅ · launch smoke test via `open` (launches, lock
acquired, no crash, clean quit + lock released) ✅.
⚠️ **Still needs a manual on-device pass:** confirm the Dock/Cmd-Tab/About icon renders;
walk the first-run onboarding (grant mic + speech, reach the hotkey step); open the
menu-bar menu and check the connection line, recents (open one), New Chat, Settings, Quit.

<details><summary>Original task list</summary>

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

</details>

### Phase 9 — QA, tests, verification  ✅ DONE (2026-06-07)
**Goal:** Lock it in.

**What shipped:**
- **Expanded `HermesVoiceKit` tests** — **145 → 209 checks, 0 failures** (+64).
  - *SSE named-event/tool parsing:* no-leading-space `data:` lines, unsolicited
    tool-progress data without an `event:` qualifier, unknown named events clearing the
    pending state, keep-alive comments, and full `ToolActivity` Codable round-trip
    (incl. required-only fields + invalid-status rejection).
  - *ConversationStore round-trip:* `SessionMeta` source/messageCount defaults, custom
    source/model round-trip, `upsert` appends-new (not just replace), `encodeRecordLine`
    single-line + sorted-keys, multi-record order + trailing-newline framing,
    `relativeTime` bucket boundaries (60s→"1m", 3600s→"1h", 86400s→"1d", 604800s→"1w").
    *(Atomic temp+rename IO lives in the app-layer `ConversationFileStore`, which the Kit
    test target doesn't link; the pure encode/decode it wraps is fully covered.)*
  - *Settings serialization:* `baseURLString` with custom host/port, wrong-typed field
    falling back per-field without wiping siblings, explicit-null model → nil, and
    `VoiceFlow`/`AppearanceMode` all-cases-have-labels.
  - *Error classification:* every unreachable URL code → `.offline`, unrecognized code
    (unknown before stream / drop mid-stream), timeout invariant across stream phase,
    `http` kind carrying its status code.
  - *Hotkey-string formatting:* empty modifier string, each modifier→glyph, named key
    codes (↩ ⎋ ← ↑ F1), `hasModifier` for each single modifier.
- **Manual verification checklist** — consolidated every phase's "needs on-device pass"
  into `tasks/manual-verification-checklist.md` (per-feature + the cross-cutting
  regression pass: hotkey single-fire, single-instance, panel state machine, light/dark,
  reduce-motion). The pure logic behind hotkey single-fire and the panel state machine is
  already unit-tested (`PanelStateMachineTests`).
- **Release build + tests green; bundle builds, validates, launches, quits clean.**

**Verification:** `swift build -c release` ✅ · `swift run HermesVoiceTests` → **209
checks, 0 failures** ✅ · `./build-app.sh` (clean) — icon embedded, `CFBundleVersion`
stamped (build 14), `plutil`/`codesign`/icon validation pass ✅ · launch smoke test via
`open` (launches, runs, clean quit) ✅.
⚠️ **Remaining manual on-device pass:** see `tasks/manual-verification-checklist.md` —
the human-in-the-loop items (real keystrokes, mic, screen eyeballing, light/dark +
reduce-motion) that can't be automated in this headless environment.

<details><summary>Original task list</summary>

**Tasks:**
- Expand `HermesVoiceKit` tests: SSE named-event/tool parsing, ConversationStore
  round-trip + atomic writes, settings serialization, error classification, hotkey-string
  formatting.
- Manual verification checklist per feature; regression pass on hotkey single-fire,
  single-instance, panel state machine, light/dark, reduce-motion.
- Confirm release build + tests green.

</details>

---

## 5. Cross-cutting rules ("don't break the app")
- **Per phase:** build (release) + tests + launch smoke test must pass; then commit.
- Keep new pure logic in **`HermesVoiceKit`** with tests; no AppKit there.
- Preserve the **Carbon hotkey**, **flock single-instance**, **PanelStateMachine**, and
  **debouncers**. Only Phase 5 makes the hotkey configurable.
- Stay on **SPM / no Xcode**; verify any new dependency resolves under CLT.
- One phase per session; rely on git checkpoints for rollback.

## 6. Open items to verify during implementation
1. ✅ **Verified (2026-06-07).** Repeating an identical request *with* a fixed
   `X-Hermes-Session-Id` grows `prompt_tokens` (20639 → 20648); *without* the header it's
   stable (20659 → 20659). Confirms accumulation; the Phase 2c fix (drop the header) is correct.
2. ✅ **Verified (2026-06-07).** The gateway **accepts** a per-request `model` (200, and
   echoes it back in the response) but treats it as a **no-op** — even a bogus id
   (`"definitely-not-a-model"`) still answers normally. `/v1/models` advertises a single
   model (`hermes-agent`). So the model is effectively **global**; the Phase 5 picker
   sends `body.model` (harmless) and is populated from `/v1/models` to stay future-proof,
   but switching it won't change behavior on the current single-model gateway.
3. ✅ **Verified (2026-06-07).** The gateway accepts OpenAI Chat-Completions multimodal
   `content`: an array of `{"type":"text","text":…}` and
   `{"type":"image_url","image_url":{"url":"data:image/…;base64,…"}}` parts (data URLs must
   be `data:image/…` with a comma; http(s) URLs also allowed). A live `text + 1×1 PNG`
   request streamed `200`/SSE with no `invalid_image` error. Used by Phase 4c
   (`OutgoingMessage.contentJSON`).
4. ✅ **Verified (2026-06-07).** With no header, a multi-turn request answered correctly
   from client-owned history ("What is my name?" → "Your name is Taohid.") — the server
   derives its own session and grouping works.
5. ✅ **Verified (2026-06-07).** `GET /v1/health` → `{"status":"ok","platform":"hermes-agent"}`,
   sub-second. Used for the reachability indicator (`connectionState`).
