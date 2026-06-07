# Background & Concurrent Sessions — Implementation Plan

> Single source of truth for making Hermes chat sessions keep running in the
> background. Built from a codebase investigation + adversarial design review
> (2026-06-07). Execute roughly **one Phase per Claude Code session**. Each phase is
> dependency-ordered and individually shippable: **the app must build, pass tests,
> and launch after every phase.** Phases 0–2 are behavior-preserving; the user-visible
> behavior change lands in Phase 3.
>
> This plan assumes the `tasks/overhaul-plan.md` work (Phases 1–9) is already done.

---

## Progress checklist (update after each phase)

> **For the next session:** find the first unchecked phase below, read its section in
> §5, and implement it. Build + test + `graphify update .` after, then tick its boxes and
> add a short "Done" note. Phases are dependency-ordered — do not skip ahead.

- [x] **Phase 0 — Pure, testable algorithms** *(done 2026-06-08)*
  - [x] `ActivityRefCounter` — `Sources/HermesVoiceKit/ActivityRefCounter.swift` (`begin()`/`end()` ref-count, clamps at 0)
  - [x] `PartialReconciler` — `Sources/HermesVoiceKit/PartialReconciler.swift` (`.fold`/`.deleteOnly`/`.ignore` per §4.7)
  - [x] `EvictionPolicy` + `SessionLifecycleState` — `Sources/HermesVoiceKit/EvictionPolicy.swift` (per §4.10)
  - [x] Tests added (`ActivityRefCounterTests`/`PartialReconcilerTests`/`EvictionPolicyTests`) + registered in `Tests/HermesVoiceTests/main.swift`
  - [x] Verified: `swift build -c release` OK; `swift run HermesVoiceTests` → 249 checks, 0 failures (21 new); app behavior unchanged
  - _Note: `SessionLifecycleState` is a toolchain-pure mirror of `OverlayState`; the app maps onto it 1:1 when calling `EvictionPolicy`. These types are NOT wired into the app yet — wiring starts Phase 1+._
- [x] **Phase 1 — id-based streaming target** (single VM, behavior-preserving) — §5, traps §4.4 *(done 2026-06-08)*
  - [x] Replace positional `assistantIndex` with stored `streamingMessageId: UUID?` in `OverlayViewModel`
  - [x] Re-resolve `firstIndex(where:{$0.id==streamingMessageId})` fresh at every access in `runStream`/`finishAssistant`/`handleStreamFailure`/`cancelStreaming`/`retryLast`; clear id on every terminal path
  - [x] Verify by hand in the running app: stream / Stop / Retry / failure-retry behave identically
  - _Note: added `streamingMessageId: UUID?` + private `streamingIndex()` helper. `generateResponse` captures the placeholder's id (no longer passes an index into the Task); `runStream`/`finishAssistant`/`handleStreamFailure`/`cancelStreaming` all resolve the index fresh via `streamingIndex()` and bail if absent. Id cleared on every terminal path (finish/fail/cancel) and in `startBlankConversation`/`retryLast`; deliberately NOT cleared on `Task.isCancelled` returns since `generateResponse` cancels the old task only after setting the new id. `swift build -c release` OK; `swift run HermesVoiceTests` → 249 checks, 0 failures (unchanged — VM layer is not CLT-unit-testable); `./build-app.sh` OK; `graphify update .` done. Manual in-app verification still pending a live gateway run._
- [x] **Phase 2 — Extract `ChatSession`; VM becomes a facade over ONE session** — §5, traps §4.1/§4.9 *(done 2026-06-08)*
  - [x] New `@MainActor ChatSession: ObservableObject` owns per-session state + `runStream`/`generateResponse`/`persist` keyed off its OWN immutable `conversationId` (fixes `:464`)
  - [x] VM facade mirrors foreground session via explicit `.sink` + synchronous pre-copy + `sessionCancellables` teardown
  - [x] Serialize `sessions.json` writes through one `@MainActor` helper
  - [x] Verify: `OverlayView.swift` unchanged; app behaves exactly as before; tests pass
  - _Note: new `Sources/HermesVoice/ChatSession.swift` holds `ChatSession` (per-session state + streaming/persistence keyed off its immutable `let conversationId`/`startedAt`/`model`) and `SessionIndexWriter` (a `@MainActor` `update(id:transform:)` helper that serializes the `sessions.json` load→upsert→save; §4.9). `OverlayViewModel` is now a facade: keeps the global @Published fields (input draft, pendingImages, voice/mic, audioLevel, connectionState, history) + four mirror fields (`state`/`chatMessages`/`errorMessage`/`activeTools`) updated from `foreground` via explicit `.sink` in `bindForeground`, with the mandatory synchronous pre-copy before re-subscribe and `sessionCancellables.removeAll()` teardown on swap. Voice/mic transitions write into `foreground.state`/`.errorMessage` (foreground-only, per §3 note). `send`/`retry`/`cancel`/`canRetry` forward to `foreground`; `routeSend` does global housekeeping then guards on `foreground.isBusy` so a blocked send clears nothing (matches old order). `connectionState` stays global — the session reports up via an `onConnectionState` callback wired in `bindForeground`. `newChat`/`openConversation`/`deleteConversation` still swap a single session (call `foreground.teardown()` to cancel the old stream — destructive, like before); keeping old sessions alive is Phase 3. `OverlayView.swift` is byte-for-byte unchanged (verified via `git diff --stat`). `swift build -c release` OK; `swift run HermesVoiceTests` → 249 checks, 0 failures (unchanged — facade/session layer is not CLT-unit-testable); `./build-app.sh` OK (build 21); `graphify update .` done. Manual in-app verification (stream/switch/new-chat/retry/voice behave identically) still pending a live gateway run._
- [x] **Phase 3 — `SessionManager` + non-destructive hide/switch (THE behavior change)** — §5, traps §4.2/§4.3/§4.6 *(done 2026-06-08)*
  - [x] Add `SessionManager` (`[id: ChatSession]`, owned by the VM facade)
  - [x] Remove `streamTask?.cancel()` from `cleanup()`; reduce `reset()` to global-only
  - [x] Non-destructive `newChat()`/`openConversation()` (re-point to live session if present, §4.11)
  - [x] Wire ref-counted `ProcessInfo.beginActivity(.userInitiated)` via `ActivityRefCounter`, bracket network loop only
  - [x] Per-target-session `send`/`retry` guards; pin voice transcripts to record-start session
  - [ ] Verify acceptance criteria §0 #1–4 by hand *(pending live-gateway run)*
  - _Note: new `Sources/HermesVoice/SessionManager.swift` is a `@MainActor` registry (`[id: ChatSession]`) that also owns the process-wide App Nap assertion via the Phase-0 `ActivityRefCounter` — `register()` wires each session's `onStreamingBegin/End` to the ref-counter, which acquires `ProcessInfo.beginActivity(.userInitiated)` on 0→1 and releases on 1→0. Owned by `OverlayViewModel` (a forever-singleton owned by `AppDelegate`), so streams + assertion survive panel hide. `ChatSession.runStream` now brackets **only the network loop**: `onStreamingBegin?()` at entry, an idempotent `releaseActivity()` called explicitly right after `finishAssistant()` (before the cosmetic 1.5s done→idle sleep) plus a `defer` safety-net so the cancellation/failure early-returns can't leak the ref-count (§4.3). `cleanup()` (panel hide) no longer tears down the foreground — only stops the mic; `reset()` (panel show) dropped the `.done/.error → .idle` block so reopening a live/errored session isn't wiped (§4.2). `newChat`/`startBlankConversation` and `openConversation` are non-destructive: a new `releaseForegroundIfDisposable()` drops the outgoing foreground from the manager ONLY when `!isBusy && !canRetry` (streaming/errored sessions stay resident; clean idle ones reload identically from disk — keeps live memory bounded without Phase-4 eviction). `openConversation` re-points to a live resident session with no disk load when present, else loads from disk (§4.11). Per-target send guard: `routeSend(text:images:to:)` guards on the **target** session's `isBusy` (not always foreground), so a different session can send concurrently; `ChatSession.send`/`retryLast` already guard their own state. Voice transcripts pinned via a `weak recordingTarget` captured at record-start and re-validated against the manager in `handleTranscript`'s `.send` case (§4.6). `deleteConversation` now tears down + removes any live session BEFORE deleting disk (ordering per §4.5; the in-flight-chunk resurrection race is hardened in Phase 4). One small `OverlayView` change: an `.onChange(of: viewModel.conversationId)` resets `streamingContentLength` so the first post-switch chunk autoscrolls (§4.1). `swift build -c release` OK; `swift run HermesVoiceTests` → 249 checks, 0 failures (unchanged — manager/facade/session layer is not CLT-unit-testable; the ref-counter algorithm itself is covered by Phase-0 `ActivityRefCounterTests`); `./build-app.sh` OK (build 22); `graphify update .` done. Manual in-app verification of acceptance criteria §0 #1–4 (hide-keeps-streaming / A-streams-while-viewing-B / two concurrent streams / backgrounded app keeps streaming) still pending a live gateway run._
- [x] **Phase 4 — Durability + delete/evict safety** — §5, traps §4.5/§4.7/§4.10 *(done 2026-06-08)*
  - [x] `writePartial`/`readPartial`/`clearPartial` on `ConversationFileStore` (`.partial` side file)
  - [x] Debounce-write in-flight partial; `clearPartial` at `generateResponse` entry + `retryLast` + every terminal path
  - [x] On launch, fold leftover `.partial` via `PartialReconciler`
  - [x] `deleteConversation` safe cancel+evict (`isDeleted`, invalidate timer, remove from manager, THEN delete disk)
  - [x] Optional eviction via `EvictionPolicy` — **deferred by design** (Open Decision D); memory is already bounded by Phase 3's `releaseForegroundIfDisposable`, and the pure `EvictionPolicy` stays available + tested for a future session
  - [ ] Verify acceptance criterion §0 #5 (⌘Q mid-stream → relaunch recovers); delete-while-streaming leaves no resurrected files *(pending live-gateway run)*
  - _Note: durability is now a `.partial` side-file per conversation (`transcripts/<id>.partial`), a NEW `PartialRecord {content, ts}` codable in `HermesVoiceKit/ConversationStore.swift` — deliberately NOT `TranscriptRecord`, so the agent-shared transcript schema is untouched. `ConversationFileStore` gained `writePartial`/`readPartial`/`clearPartial` (atomic write, tolerant read) + `deleteConversation` now also removes the `.partial`. `ChatSession.runStream`'s `.text` case debounce-writes the growing assistant text via a leading-edge `Debouncer(interval: 0.5)` (reset at each `generateResponse` so the first chunk flushes promptly) — ~2 writes/sec, not per-token. `clearPartial` runs at `generateResponse` entry, in `retryLast` (after the dropped-partial removal), and on every terminal path (`finishAssistant`/`handleStreamFailure`/`cancelStreaming`) — the final/incomplete record lives in `.jsonl`, so the side-file is only ever the uncommitted crash window. The chosen debounce is **synchronous + leading-edge** (write happens inline in `.text`), so there is no async timer to invalidate per §4.5 — `markDeleted()` (sets `isDeleted` + cancels the stream) plus an `isDeleted` guard on every disk write (`writePartial`/`persist`/`updateIndexMeta`/`rewritePersistedTranscript`/`registerConversationIfNeeded`) fully covers the late-chunk resurrection race. `deleteConversation` now: `markDeleted()` → `manager.remove` → delete disk (ordering §4.5). Recovery: a new static `OverlayViewModel.loadMessages(id:store:)` runs `PartialReconciler.decide` over the leftover `.partial` on EVERY load path (`init` resume + `openConversation` disk-load) — `.fold` appends the partial as a trailing **incomplete (retryable)** assistant message + clears the file; `.deleteOnly` just clears; `.ignore` leaves it. `swift build -c release` OK; `swift run HermesVoiceTests` → 252 checks, 0 failures (3 new: `PartialRecord` round-trip + tolerant decode; the fold rule itself is covered by the Phase-0 `PartialReconcilerTests`); `./build-app.sh` OK (build 23); `graphify update .` done. Manual verification of §0 #5 (⌘Q mid-stream → relaunch shows a retryable partial) and delete-while-streaming-leaves-no-resurrected-files still pending a live gateway run._
- [ ] **Phase 5 — UX surfacing of background activity** — §5, traps §4.8
  - [ ] `SessionManager` publishes "any session streaming" flag + one-shot `didFinish(id)`
  - [ ] Animated menu-bar status item reflects background activity; in-panel pill stays foreground-only
  - [ ] Verify: panel hidden + background stream → menu-bar shows activity; finish posts a cue

---

## 0. The goal (read first)

**What the user wants.** Today, when a chat response is streaming and the user hides
the panel, backgrounds the app, lets it lose focus, or opens/creates another session,
the in-flight response is **killed**. The user wants the opposite: a started session's
task keeps executing no matter what the UI does, and **multiple sessions can stream
concurrently** — switch away from a streaming session and it keeps going; come back and
it's intact (still streaming or finished).

**Acceptance criteria (the "done when").**
1. Start a stream, hide the panel (click outside / Esc / ✕ / ⌘W / hotkey toggle) → the
   stream keeps running; reopen → the transcript shows the grown/finished response.
2. Start a stream in A, open/create session B → A keeps streaming in the background;
   B is fully usable; returning to A shows its live progress.
3. Two (or more) sessions stream **at the same time**, each into its own transcript.
4. Backgrounding the whole app (lose focus, another app frontmost) does not stall or
   kill an in-flight stream.
5. App quit (⌘Q) mid-stream → on relaunch, the partial answer is recovered as a
   retryable incomplete message (best-effort durability).
6. No regressions to the single-session experience, voice flow, history, or persistence
   format read by the Hermes agent.

**This is feasible and is NOT blocked by macOS.** This is a `.accessory` + `LSUIElement`
menu-bar agent (`App.swift:7`, `Resources/Info.plist:21`). The run loop (`App.swift:32`)
and process stay alive with the panel hidden — `hidePanel()` only `orderOut`s the window
(`AppDelegate.swift:462`); nothing terminates on hide/background (no
`applicationShouldTerminateAfterLastWindowClosed`; `terminate` only on the single-instance
lock bailout and the Quit menu). The app is **not sandboxed** (`entitlements.plist` has
only `audio-input`). Streaming is a detached `Task` driving `URLSession.shared.bytes`
(`OverlayViewModel.swift:105/313`, `HermesAPIClient.swift:75`), fully independent of window
or view lifecycle. **The session dies only because the app explicitly cancels it.**

---

## 1. Orientation — the app & how to build it

**What it is.** A macOS 14+ menu-bar utility (Swift Package, **no Xcode project**) that
shows a Spotlight-style floating `NSPanel` on **⌃⇧H**, captures voice
(`SFSpeechRecognizer` + `AVAudioEngine`) or typed text, and streams replies from the local
**Hermes gateway** (`127.0.0.1:8642`, OpenAI-compatible SSE).

**Constraints (do not change without reason):**
- Swift Package Manager only; builds under Command Line Tools (no full Xcode → **XCTest is
  unavailable**). Pure, hardware-free logic lives in **`HermesVoiceKit`** and is tested by
  a custom executable harness. **Keep new testable logic in `HermesVoiceKit`** — the test
  runner links only `HermesVoiceKit` and **cannot exercise `@MainActor` AppKit/VM code.**
- The on-disk transcript schema is **shared with the Hermes agent's tooling**
  (`HermesVoiceKit/ConversationStore.swift:33` `TranscriptRecord {role,content,ts,images?}`,
  comment at `:54`). **Do not change the persisted `TranscriptRecord` schema or the JSONL
  format.** New durability state must go in *separate* side files.
- Single-instance via `flock` at `~/.hermes/hermes_voice.lock` (`AppDelegate.swift:108`).
  Concurrency is achieved with **multiple in-process sessions**, never multiple processes.
- Panel race-safety via `PanelStateMachine` + debouncers — preserve.

**Build / run / test:**
```bash
swift build -c release          # compile
swift run HermesVoiceTests      # run the pure-logic test suite
./build-app.sh                  # produce build/HermesVoice.app (ad-hoc signed)
open build/HermesVoice.app      # launch
```
After changing code, run `graphify update .` to keep `graphify-out/` current (AST-only, no
API cost), per `CLAUDE.md`.

**Files you will touch most:**
```
Sources/HermesVoice/OverlayViewModel.swift   the single session controller (becomes a facade)
Sources/HermesVoice/AppDelegate.swift        owns the VM; hidePanel/cleanup/reset; status menu
Sources/HermesVoice/HermesAPIClient.swift    SSE streaming (already stateless/per-call — keep)
Sources/HermesVoice/ConversationFileStore.swift  disk IO (add .partial side-file methods)
Sources/HermesVoice/OverlayView.swift        SwiftUI root (should change ZERO lines — verify)
Sources/HermesVoiceKit/ConversationStore.swift   pure store logic (do NOT change schema)
Sources/HermesVoiceKit/*                      add new PURE testable types here (Phase 0)
Tests/HermesVoiceTests/                       add tests for the Phase-0 pure types
```
> ⚠️ Line numbers in this plan are from the 2026-06-07 snapshot and **will drift** as you
> edit. Treat them as "look near here," not as exact addresses. Re-grep symbol names.

---

## 2. Why the current architecture fights us — the 3 root blockers

There is exactly **one** `OverlayViewModel` (`AppDelegate.swift:17`) holding **one**
`streamTask` (`OverlayViewModel.swift:105`), **one** `chatMessages` array (`:60`), and
**one** mutable `conversationId` (`:109`). Three things must be fixed or concurrency
silently corrupts data:

1. **Positional streaming target.** `runStream` captures `assistantIndex =
   chatMessages.count - 1` (`:308`) into the Task (`:314`) and writes
   `chatMessages[assistantIndex].content += chunk` (`:340`). Once the view switches
   conversations or a second session appends, that integer index points at the **wrong row
   or out of bounds**. → Must become a lookup by a **stable `ChatMessage.id`**, re-resolved
   *fresh at every access*.

2. **`persist()` keys off mutable `self.conversationId`** (`:464`). A late/background
   `finishAssistant` would append to **whatever conversation is now displayed**. → Persist
   must key off the **session's own immutable id**. And `updateIndexMeta` (`:468`) does a
   read-modify-write of the shared `sessions.json`; concurrent sessions clobber each other.
   → **Serialize** index writes.

3. **Destructive lifecycle.** `hidePanel() → cleanup() → streamTask?.cancel()`
   (`AppDelegate.swift:447`, `OverlayViewModel.swift:641-643`);
   `startBlankConversation()` cancels + wipes (`:561-575`); `openConversation()` and
   `deleteConversation()` route through it (`:614`, `:637`). → Hiding/switching must become
   **non-destructive** (re-point to a live session; never cancel on hide/switch).

There is also **no incremental persistence** — streamed chunks live only in
`chatMessages[assistantIndex]` and reach disk only at completion/failure/cancel
(`finishAssistant :380`, `handleStreamFailure :394`, `cancelStreaming :434`).

---

## 3. Target architecture

```
AppDelegate
  └─ SessionManager  (@MainActor, NEW; owned by AppDelegate; outlives panel hide & new-chat)
       ├─ [conversationId : ChatSession]   live sessions, never cancelled on hide/switch
       ├─ ref-counted ProcessInfo activity assertion (App Nap suppression)
       ├─ serialized sessions.json index writes
       └─ relaunch reattach (live session vs load-from-disk + fold .partial)

  └─ OverlayViewModel  (FACADE; the single ObservableObject the views still observe)
       ├─ mirrors the FOREGROUND ChatSession's per-session @Published fields
       ├─ owns GLOBAL state (input draft, pending images, voice, focus, connection, history)
       ├─ owns the single VoiceEngine; routes transcripts to a pinned session
       └─ forwards send/retry/cancel/new/open/delete to the manager/session

ChatSession  (@MainActor ObservableObject, NEW; one per conversation)
       ├─ owns: conversationId(let)/startedAt/model, chatMessages, state, activeTools,
       │        errorMessage, streamTask, streamingMessageId
       ├─ runStream/generateResponse/retryLast/cancelStreaming/finishAssistant/
       │  handleStreamFailure/applyToolActivity  (streams by ChatMessage.id, not index)
       └─ per-session persist/register/updateIndexMeta/rewrite/writePartial/clearPartial
          (keyed off its OWN id); calls manager.streamingDidBegin/End

OverlayView / WaveformView / HistoryView   UNCHANGED — keep observing the VM facade
ConversationFileStore                       UNCHANGED methods + additive writePartial/readPartial/clearPartial
HermesAPIClient                             UNCHANGED — already stateless/per-call, safe to share
```

**Why a facade and not "view observes the session directly."** `OverlayView`,
`WaveformView`, and `HistoryView` each take a single `@ObservedObject var viewModel:
OverlayViewModel` and read **both** per-session fields (`chatMessages`, `state`,
`activeTools`, `errorMessage`) **and** global fields (`inputText`, `pendingImages`,
`isRecording`, `audioLevel`, `showingHistory`, `historyQuery`, `connectionState`,
`panelShouldFocus`). A `ChatSession` is neither a clean subset nor superset the views could
bind to alone — observing the session directly would force every view to take *two*
observed objects and split every call site. The facade keeps the SwiftUI layer **untouched**
(e.g. `OverlayView.swift:295` `ForEach(viewModel.chatMessages)`, `:314/:322` scroll-on-stream,
`:489-524` send/stop/retry gating, `:247` empty-state). The view never shows two sessions at
once, so a facade-over-foreground is exactly right.

### Per-session vs global state split

| Per-session → move onto `ChatSession` | Global → stays on the VM facade |
|---|---|
| `streamTask` (`:105`) | `inputText` draft (`:61`) — *see Open Decision A* |
| `conversationId` (`:109`, becomes immutable `let`) | `pendingImages` (`:70`) — *see Open Decision A* |
| `conversationStartedAt`, `conversationModel` (`:110-111`) | `isRecording`, `transcribedText`, `audioLevel` (`:63-66`, one mic) |
| `chatMessages` (`:60`) | `voiceEngine` (`:102/130`, one mic) |
| `state` (`:59`) **and** `errorMessage` (`:62`) — see note | `panelShouldFocus` (`:65`) |
| `activeTools` (`:68`) | `connectionState` (`:72`, gateway is app-wide) |
| streaming target → `streamingMessageId: UUID?` (replaces positional `assistantIndex`) | `showingHistory`, `historyQuery`, `historyEntries`, `historySearchShouldFocus` (`:85-91`) |
| `runStream/generateResponse/retryLast/canRetry/cancelStreaming/finishAssistant/handleStreamFailure/applyToolActivity` | `store: ConversationFileStore` (`:104`, shared disk layer) |
| `persist/register/updateIndexMeta/rewrite/persistedMessages` (key off own id) | `apiClient: HermesAPIClient` (`:103`, stateless — share) |
| `maxAttempts` retry budget (`:113`) | history browser methods (`openHistory/closeHistory/reloadHistory/recentSessions`) |

> **Note on `state`/`errorMessage`.** Both are per-session (a backgrounded session must
> remember it's `.responding` or that it errored). BUT the voice/mic transitions
> (`.listening`/`.transcribing` at `:193/:221`) and voice errors (`:140`, `:187`) only ever
> apply to the **foreground** session — the facade writes them into the foreground session's
> state. `connectionState` stays global (only `.offline`-kind failures flip it, `:386`).

---

## 4. Critical implementation details (the traps — read before coding)

These come from an adversarial review; the **five HIGH-severity** ones cause real bugs.

1. **[HIGH] Facade mirroring must use cancellable `.sink`, NOT `assign(to:&$published)`.**
   `assign(to:&$published)` binds its lifetime to the publisher's storage — you **cannot**
   tear it down via your `Set<AnyCancellable>` on re-point, so the *old* session keeps
   writing into the facade forever. Use explicit
   `foreground.$chatMessages.sink { [weak self] in self?.chatMessages = $0 }` stored in
   `sessionCancellables`. On switch: (1) tear down `sessionCancellables`, (2) set
   `foreground = newSession`, (3) **synchronously copy** all mirrored fields
   (`chatMessages`, `state`, `activeTools`, `errorMessage`) from the new session, (4)
   re-subscribe. **The synchronous pre-copy before re-subscribe is mandatory** — without it,
   reopening a backgrounded session shows one stale frame (the previous transcript) before
   Combine catches up. Also reset `OverlayView`'s `@State streamingContentLength`
   (`OverlayView.swift:17`) on switch or the first post-switch chunk won't autoscroll.

2. **[HIGH] `reset()` is called on every `showPanel`** (`AppDelegate.swift:423`;
   `OverlayViewModel.swift:510-522`) and today forces `.done/.error → .idle` (`:515-517`)
   and stops the mic. Reopening to a **live/errored** foreground session would wipe the very
   state the user needs to see/retry. → Reduce `reset()` to **global concerns only**:
   refresh `connectionState`, pulse focus, (decide on mic). It must **not** touch the
   foreground session's `state`/`errorMessage`. Delete the `.done/.error → .idle` block (the
   per-session 1.5s timer already handles `done → idle`).

3. **[HIGH] App Nap assertion must be a single guaranteed-once `defer`.** Hold **one**
   process-wide `ProcessInfo.processInfo.beginActivity(options:.userInitiated, reason:)`
   ref-counted across all streaming sessions, owned by `SessionManager` (so it survives
   panel hide). `streamingDidBegin()` increments a count and acquires the token if nil;
   `streamingDidEnd()` decrements and releases at 0. **Bracket only the network loop**, not
   the cosmetic 1.5s `done → idle` sleep (`OverlayViewModel.swift:347-351`) — call
   `streamingDidEnd()` right after the `for try await` loop completes/throws, **before** the
   sleep. If `end` is attached to one line instead of a `defer`, the early-returns at `:335`
   / `:353` / `:365` leak the ref-count and the assertion is held **forever, app-wide**
   (defeating App Nap for the whole process). Use `.userInitiated` only — **not**
   `.idleSystemSleepDisabled` (a chat stream shouldn't keep the whole Mac awake; see Open
   Decision B).

4. **[HIGH] The streaming target id must be re-resolved fresh at EVERY access.** Store
   `streamingMessageId: UUID?` on `ChatSession`. In `runStream`/`finishAssistant`/
   `handleStreamFailure`/`cancelStreaming`, resolve
   `chatMessages.firstIndex(where: { $0.id == streamingMessageId })` *at each read/write/
   remove* and bail if not found (the session may have been reset/retried/deleted). The
   captured positional `assistantIndex` is invalid both across the async boundary **and**
   across in-session mutations (`retryLast` removes a row at `:288`, shifting positions).
   Clear `streamingMessageId` at every terminal path.

5. **[HIGH] Delete must not be resurrected by a late chunk.** `ConversationFileStore.append
   Record` (`:61-67`) has a create-fallback (`data.write(to:url,.atomic)`) that **re-creates**
   a deleted `.jsonl`. A chunk arriving after `cancel()` but before the Task observes
   `Task.isCancelled` can call `persist()` and resurrect a just-deleted transcript;
   `updateIndexMeta` can re-add the `SessionMeta`. → On delete: (1) set `session.isDeleted =
   true`, (2) cancel `streamTask` **and** invalidate the partial-debounce timer, (3) remove
   the session from `SessionManager`'s dict, (4) **then** delete disk (`.jsonl` + `.partial`
   + index). Every disk write in `ChatSession` (`persist`/`updateIndexMeta`/`writePartial`)
   guards `guard !isDeleted else { return }` (race-free since all `@MainActor`).

6. **[MED] Pin voice transcripts to the record-start session.** `VoiceEngine.finish()`
   delivers the transcript **asynchronously** via `DispatchQueue.main.async` with a strong
   `self` (`VoiceEngine.swift:204-206`), so stopping the mic on switch does **not** cancel an
   already-queued `onFinalResult`. → Capture `let recordingTarget = foreground` when
   recording **starts**, and route `handleTranscript`'s `.send`/`.fill` outcome to
   `recordingTarget` (if still alive in the manager, else drop/fall back). Deterministic
   regardless of switch timing.

7. **[MED] `.partial` crash-window dedup rule.** `finishAssistant` appends the final JSONL
   record (`:380`) **then** deletes `.partial`; a crash between those leaves both. On load,
   use this deterministic rule (no ids needed, no schema change): read `.jsonl`; **only fold**
   the `.partial` as an incomplete trailing message **when the last JSONL record is a USER
   turn** (no assistant answer was committed). If the last record is an assistant turn whose
   content **starts with** the `.partial` content, the partial was superseded → delete it,
   don't fold. Additionally, **`clearPartial(id)` at the START of `generateResponse`** (before
   creating the placeholder) **and in `retryLast`** (after the `:288` removal), not only at
   terminal paths — otherwise a retry/new stream leaves a stale `.partial` that mis-folds.

8. **[MED] Background completion is silent.** A finished background session transitions
   `.done → .idle` after 1.5s (`:348-350`) with no notification. For the UX indicator
   (§5 Phase 5), have the session post a **one-shot `didFinish(id)`** event to
   `SessionManager` at `finishAssistant` time — do not infer it from `state == .done`, which
   evaporates.

9. **[LOW] `sessions.json` serialization, not field-merge.** Each session only ever
   `upsert`s its **own** id, so plain serialization of the `load → upsert → save` sequence
   through one `@MainActor`-confined helper suffices. Do **not** attempt field-level merge of
   `messageCount`/`lastActiveAt` across sessions — that's a red herring that introduces bugs.

10. **[LOW] Memory eviction (optional, Phase 4).** Unbounded live sessions each retain a full
    `chatMessages` buffer (with base64 images). Optionally evict sessions with `state ∈
    {idle, done, error}` **and** `streamTask == nil` **and** no pending partial timer, flushing
    + `clearPartial` first. **Streaming sessions are never evictable.** Reopening an evicted
    session loads it from disk into a fresh `ChatSession`.

11. **[LOW] `openConversation` identity = foreground session id.** Define precisely:
    if `id == foreground.id` → just `closeHistory()`; else if the manager has a live session
    for `id` → re-point the facade (no disk load); else → load-from-disk into a new
    `ChatSession`, register, re-point.

---

## 5. Phased implementation

Each phase builds, tests, and launches. **Phases 0–2 are behavior-preserving** (pure
refactor); the visible behavior change is isolated to **Phase 3**. Commit after each phase.

### Phase 0 — Pure, testable algorithms (no wiring, no behavior change)
Add to `HermesVoiceKit` (so the executable test runner can cover them — it can't test
`@MainActor` VM/AppKit code):
- **`ActivityRefCounter`** — `mutating func begin() -> Bool` (true when 0→1, i.e. acquire
  token), `mutating func end() -> Bool` (true when 1→0, i.e. release token), clamps at 0.
- **`PartialReconciler`** — given `(lastJSONLRole: String?, partialContent: String,
  trailingAssistantContent: String?)` → `.fold | .deleteOnly | .ignore` per rule §4.7.
- **`EvictionPolicy`** — `(state, isStreaming, hasPendingPartial) -> Bool` per §4.10.
Write tests in `Tests/HermesVoiceTests/` and register them in the harness `main.swift`.
**Verify:** `swift run HermesVoiceTests` passes; app unchanged.

### Phase 1 — id-based streaming target (still single VM, behavior-preserving)
Inside the **existing** `OverlayViewModel`, replace the positional `assistantIndex`
(`:308/:314/:322-340`) and all `.last`/index uses in `finishAssistant` (`:372-382`),
`handleStreamFailure` (`:388-400`), `cancelStreaming` (`:426-435`), and `retryLast`
(`:285-288`) with a stored `streamingMessageId` + `firstIndex(where:{$0.id==…})` resolved
fresh at each access (§4.4). No `SessionManager`, no concurrency yet.
**Verify:** manually stream / Stop / Retry / failure-retry in the running app — identical
behavior. This is the single highest-bug-risk change; do it alone.

### Phase 2 — Extract `ChatSession`; VM becomes a facade over ONE session
Move per-session state + `runStream`/`generateResponse`/`persist` (keyed off the session's
**own immutable** `conversationId`, fixing `:464`) into a new `@MainActor` `ChatSession:
ObservableObject`. `OverlayViewModel` becomes a facade over exactly one session with
explicit `.sink` mirroring + synchronous pre-copy + `sessionCancellables` teardown (§4.1).
`newChat`/`openConversation` still create/swap a single session and do **not** yet keep old
ones alive. Serialize `sessions.json` writes (§4.9).
**Verify:** `OverlayView.swift` is **unchanged**; app behaves exactly as before (stream,
switch via history, new chat, retry, voice). Tests pass.

### Phase 3 — `SessionManager` + non-destructive hide/switch (THE behavior change)
- Add `SessionManager` (dict `[id: ChatSession]`, owned by `AppDelegate`, replacing the
  `var viewModel` ownership of streams).
- **Stop cancelling on hide:** remove `streamTask?.cancel()` from `cleanup()`
  (`OverlayViewModel.swift:642`); `cleanup()` only stops the mic. Reduce `reset()` to
  global-only (§4.2).
- **Non-destructive switch:** `newChat()` creates a **new** session (don't wipe the current
  one); `openConversation()` re-points to a **live** session if present, else loads from disk
  (§4.11); neither cancels the previously-foreground stream.
- Wire the ref-counted `ProcessInfo.beginActivity(.userInitiated)` via the Phase-0
  `ActivityRefCounter`, bracketing only the network loop (§4.3).
- Make the `sendToHermes` guard (`:239`) and `retryLast` guard (`:284`) check the **target
  session's** state, so a different session can send concurrently (scenarios 6, 8).
- Pin voice transcripts to the record-start session (§4.6).
**Verify:** acceptance criteria 1–4 (§0) pass by hand: hide-keeps-streaming;
A-streams-while-viewing-B; two concurrent streams; backgrounded app keeps streaming.

### Phase 4 — Durability + delete/evict safety
- Add `writePartial(id:content:ts:)` / `readPartial(id:)` / `clearPartial(id:)` to
  `ConversationFileStore` (side file `transcripts/<id>.partial`, a NEW small codable struct —
  **not** `TranscriptRecord**; use existing `atomicWrite` `:87-100`). Debounce-write the
  in-flight assistant partial from `runStream`'s `.text` case (reuse `HermesVoiceKit.Debouncer`
  pattern). `clearPartial` on every terminal path **and** at `generateResponse` entry +
  `retryLast` (§4.7).
- On launch, fold leftover `.partial` per the Phase-0 `PartialReconciler` (§4.7) in the load
  paths (`OverlayViewModel.init :148-155`, `openConversation :619-624`).
- Make `deleteConversation` cancel + evict the live session safely (§4.5): `isDeleted`,
  invalidate timer, remove from manager, **then** delete disk.
- Optional eviction via Phase-0 `EvictionPolicy` (§4.10).
**Verify:** acceptance criterion 5 (⌘Q mid-stream → relaunch recovers retryable partial);
delete a background-streaming session leaves no resurrected files.

### Phase 5 — UX surfacing of background activity (no correctness risk)
- `SessionManager` publishes an aggregate "any session streaming" flag + a one-shot
  `didFinish(id)` event (§4.8).
- Reflect it in the menu-bar status item (`App.swift:19-24`) — prefer an **animated status
  item image** over a menu line, because the status menu only rebuilds on open
  (`AppDelegate.swift:338-345`) and won't update live. Optionally mark the streaming session
  in the recents rows (`rebuildStatusMenu :366-380`).
- Keep the in-panel status pill **foreground-only** (`OverlayView.swift:170-241`).
**Verify:** with the panel hidden and a background stream running, the menu-bar icon shows
activity; finishing posts a cue.

---

## 6. Edge-case behavior matrix (condensed; full analysis in design notes)

| # | Situation | Expected |
|---|---|---|
| 1 | Stream A, open B, return to A | A keeps streaming; return shows live progress |
| 2 | Stream A, open B, stream B | both stream concurrently into own transcripts |
| 3 | Stream A, hide panel, reopen | stream survives hide; reopen reattaches |
| 4 | Stream A, ⌘Q, relaunch | partial recovered as retryable incomplete message |
| 5 | Background A errors while viewing B | A's error stays on A; B undisturbed; ambient cue |
| 6 | Retry/Stop | always act on the **foreground** session only |
| 7 | Voice while another streams | transcript → record-start (foreground) session; other unaffected |
| 8 | Send while foreground `.responding` | blocked for that session; a different session may send |
| 9 | Delete a background-streaming session | cancel + evict + delete; no resurrection |
| 10 | Foreground idle, background responding | ambient menu-bar/indicator cue |
| 11 | Single-instance flock | unchanged — concurrency is in-process |
| 12 | Stop/Retry/autoscroll vs `.last` | target by stable id, re-resolved per access |

---

## 7. Open decisions (pick before/while implementing)

- **A. Input draft scope.** Keeping `inputText`/`pendingImages` global (recommended for v1,
  matches today) means a half-typed draft is **lost** when switching sessions — a minor new
  regression. Alternative: move `draft`/`pendingImages` onto `ChatSession` and mirror them
  too. **Recommendation: global for v1; document the draft-loss.**
- **B. `.idleSystemSleepDisabled`.** Off for v1 (don't keep the Mac awake for a chat). If a
  future long agent run must outlast display sleep, gate it behind a setting.
- **C. Notify on background completion?** A finished background answer is easy to miss.
  Decide: silent (just the indicator) vs a subtle notification/sound. (Phase 5.)
- **D. Eviction.** Ship the simple unbounded-live-sessions version first; add `EvictionPolicy`
  only if memory is a concern (Phase 4, optional).

---

## 8. Testing strategy

- **Pure logic (automated):** `ActivityRefCounter`, `PartialReconciler`, `EvictionPolicy` in
  `HermesVoiceKit` with tests in `Tests/HermesVoiceTests/` (`swift run HermesVoiceTests`).
  This is where the riskiest *algorithms* live precisely so they're testable — the VM/AppKit
  layer can't be unit-tested under CLT.
- **Manual (per phase):** use `tasks/manual-verification-checklist.md` as a model; add a
  "background sessions" section covering acceptance criteria §0 1–6 and the matrix §6. The
  fastest manual rig: lower the gateway model's speed or send a long prompt so the stream
  lasts long enough to switch/hide/quit mid-flight.
- After code changes: `graphify update .` then `swift build -c release` + `./build-app.sh`.

---

## 9. Risk register (top items)

| Risk | Mitigation |
|---|---|
| Positional-index regression writes chunks into wrong conversation | Phase 1 id-based target, re-resolved per access (§4.4) |
| Facade `assign(to:)` leak — old session keeps writing | explicit cancellable `.sink` + teardown (§4.1) |
| App Nap assertion leaked forever (held on early-return) | single `defer`, bracket network loop only (§4.3) |
| `reset()` wipes a reopened live/errored session | reduce `reset()` to global-only (§4.2) |
| Deleted transcript resurrected by a late chunk | `isDeleted` guard + remove-before-delete (§4.5) |
| Concurrent `sessions.json` lost updates | serialize load→upsert→save (§4.9) |
| Misrouted voice transcript on switch | pin to record-start session (§4.6) |
| Orphaned/mis-folded `.partial` | `clearPartial` at entry+retry+terminal; prefix dedup (§4.7) |
| Unbounded memory from live sessions | optional `EvictionPolicy` (§4.10) |

---

## 10. Provenance

Derived from a full read of the session/lifecycle code (`OverlayViewModel`, `AppDelegate`,
`OverlayPanel`, `App`, `OverlayView`, `HermesAPIClient`, `ConversationFileStore`,
`ConversationStore`, `Info.plist`, `entitlements.plist`) plus two adversarial multi-agent
design passes (feasibility verification + architecture review). Core conclusion: **feasible,
not OS-blocked; the work is to stop self-cancelling and decouple per-session state from the
single shared view model, with careful attention to the 11 traps in §4.**
