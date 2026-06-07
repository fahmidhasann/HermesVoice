# Graph Report - HermesVoice  (2026-06-07)

## Corpus Check
- 35 files · ~19,869 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 549 nodes · 1100 edges · 26 communities (21 shown, 5 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 29 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5703755a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_App Lifecycle & Hotkeys|App Lifecycle & Hotkeys]]
- [[_COMMUNITY_Conversation View Model|Conversation View Model]]
- [[_COMMUNITY_API Client & Streaming|API Client & Streaming]]
- [[_COMMUNITY_Conversation Storage & History|Conversation Storage & History]]
- [[_COMMUNITY_Error Handling & Utilities|Error Handling & Utilities]]
- [[_COMMUNITY_History & Overlay UI|History & Overlay UI]]
- [[_COMMUNITY_SSE Parsing|SSE Parsing]]
- [[_COMMUNITY_Overhaul Plan & Design Decisions|Overhaul Plan & Design Decisions]]
- [[_COMMUNITY_Panel State Machine|Panel State Machine]]
- [[_COMMUNITY_Button Styles & Visuals|Button Styles & Visuals]]
- [[_COMMUNITY_Overlay Panel Transitions|Overlay Panel Transitions]]
- [[_COMMUNITY_Theme & Appearance|Theme & Appearance]]
- [[_COMMUNITY_Voice & Speech Engine|Voice & Speech Engine]]
- [[_COMMUNITY_Conversation File Store|Conversation File Store]]
- [[_COMMUNITY_Configuration|Configuration]]
- [[_COMMUNITY_Build Targets|Build Targets]]
- [[_COMMUNITY_Claude Settings & Hooks|Claude Settings & Hooks]]
- [[_COMMUNITY_API Key Parser|API Key Parser]]
- [[_COMMUNITY_Build Script|Build Script]]
- [[_COMMUNITY_Project Docs|Project Docs]]
- [[_COMMUNITY_Panel Transition Guard|Panel Transition Guard]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]

## God Nodes (most connected - your core abstractions)
1. `OverlayViewModel` - 58 edges
2. `OverlayViewModel` - 47 edges
3. `AppDelegate` - 29 edges
4. `AppDelegate` - 25 edges
5. `ChatMessage` - 19 edges
6. `VoiceEngine` - 19 edges
7. `OverlayViewModel.persist` - 19 edges
8. `OverlayPanel` - 18 edges
9. `SwiftUI` - 17 edges
10. `SessionMeta` - 17 edges

## Surprising Connections (you probably didn't know these)
- `Drop X-Hermes-Session-Id decision` --rationale_for--> `HermesAPIClient.streamCompletion`  [INFERRED]
  tasks/overhaul-plan.md → Sources/HermesVoice/HermesAPIClient.swift
- `Warm-amber editorial visual identity` --rationale_for--> `Theme design tokens`  [INFERRED]
  tasks/overhaul-plan.md → Sources/HermesVoice/Theme.swift
- `Local-only conversation storage under ~/.hermes/hermes_voice/` --rationale_for--> `ConversationFileStore (disk IO)`  [INFERRED]
  tasks/overhaul-plan.md → Sources/HermesVoice/ConversationFileStore.swift
- `Resume-last-conversation on launch` --rationale_for--> `OverlayViewModel`  [INFERRED]
  tasks/overhaul-plan.md → Sources/HermesVoice/OverlayViewModel.swift
- `Reliability primitives (retry, keep-partial, offline)` --rationale_for--> `OverlayViewModel.persist`  [INFERRED]
  tasks/overhaul-plan.md → Sources/HermesVoice/OverlayViewModel.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Conversation persistence flow (VM -> file store -> pure store)** — hermesvoice_overlayviewmodel_overlayviewmodel, hermesvoice_conversationfilestore_conversationfilestore, hermesvoicekit_conversationstore_conversationstore [INFERRED 0.85]
- **In-panel history browser feature** — hermesvoice_historyview_historyview, hermesvoice_overlayviewmodel_filteredhistory, hermesvoice_overlayviewmodel_openconversation, hermesvoicekit_conversationstore_conversationstore [INFERRED 0.75]
- **Persisted local data model (SessionMeta + TranscriptRecord)** — hermesvoicekit_conversationstore_sessionmeta, hermesvoicekit_conversationstore_transcriptrecord, hermesvoice_conversationfilestore_conversationfilestore, hermesvoice_overlayviewmodel_overlayviewmodel [INFERRED 0.75]

## Communities (26 total, 5 thin omitted)

### Community 0 - "App Lifecycle & Hotkeys"
Cohesion: 0.07
Nodes (33): Any, HermesVoiceApp main entry, makeMainMenu (Edit responder chain), AppDelegate, AppDelegate, AppDelegate.claimSingleInstanceLock (flock), AppDelegate.hidePanel, AppDelegate.installClickOutsideMonitor (+25 more)

### Community 1 - "Conversation View Model"
Cohesion: 0.08
Nodes (38): HermesAPIError, ChatMessage, ConnectionState, offline, online, unknown, HistoryEntry, OverlayViewModel (+30 more)

### Community 2 - "API Client & Streaming"
Cohesion: 0.10
Nodes (30): AsyncThrowingStream, Config (endpoints + API key), Config.loadAPIKey, Error, HermesAPIClient.checkHealth, HermesAPIError, HermesStreamEvent, HermesAPIClient.streamCompletion (+22 more)

### Community 3 - "Conversation Storage & History"
Cohesion: 0.10
Nodes (26): Double, ConversationFileStore.deleteConversation, ConversationFileStore.loadIndex, ConversationFileStore.loadPreview, ConversationFileStore.loadTranscript, ConversationFileStore.rewriteTranscript, OverlayViewModel.openConversation, OverlayViewModel.registerConversationIfNeeded (+18 more)

### Community 4 - "Error Handling & Utilities"
Cohesion: 0.08
Nodes (32): APIKeyParser.parse(env:), Debouncer.shouldFire(at:), HermesErrorClassifier.classify, HermesErrorClassifier, HermesErrorKind, auth, http, offline (+24 more)

### Community 5 - "History & Overlay UI"
Cohesion: 0.09
Nodes (28): ConversationFileStore.atomicWrite, ConversationFileStore (disk IO), ConversationFileStore.appendRecord, HistoryRow, HistoryView, OverlayViewModel.filteredHistory, OverlayState, done (+20 more)

### Community 6 - "SSE Parsing"
Cohesion: 0.14
Nodes (23): Codable, Decodable, Equatable, Choice, Chunk, Delta, SSEParser.parse(line:), SSEParser.parseContent(payload:) (+15 more)

### Community 7 - "Overhaul Plan & Design Decisions"
Cohesion: 0.12
Nodes (23): HermesVoice Overhaul Plan, Client-owned history model, Drop X-Hermes-Session-Id decision, 0. Orientation (read first), 1. Confirmed decisions (the spec), 2. Hermes server API reference (verified from `~/.hermes/hermes-agent/gateway/platforms/api_server.py`), 3. Known bugs / gaps (root causes), 4. Phased implementation plan (+15 more)

### Community 8 - "Panel State Machine"
Cohesion: 0.09
Nodes (16): Debouncer, PanelStateMachine.beginHide, PanelStateMachine.beginShow, PanelPhase, hidden, hiding, showing, visible (+8 more)

### Community 9 - "Button Styles & Visuals"
Cohesion: 0.07
Nodes (43): ButtonStyle, CircleButtonStyle (mic toggle), IconButtonStyle, SendButtonStyle, ChatMessage, Color, Configuration, CircleButtonStyle (+35 more)

### Community 10 - "Overlay Panel Transitions"
Cohesion: 0.17
Nodes (8): OverlayPanel, NSEvent, NSPanel, PanelPhase, Bool, CGFloat, OverlayViewModel, Void

### Community 11 - "Theme & Appearance"
Cohesion: 0.16
Nodes (12): Notification.Name, Appearance, Colors, Font, Layout, Motion, resolvedColor(), Spacing (+4 more)

### Community 12 - "Voice & Speech Engine"
Cohesion: 0.15
Nodes (12): AVAudioEngine, VoiceEngine, SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask, SFSpeechRecognizerAuthorizationStatus, Bool, CGFloat, Date (+4 more)

### Community 13 - "Conversation File Store"
Cohesion: 0.32
Nodes (8): ConversationFileStore, SessionMeta, Data, SessionMeta, String, URL, TranscriptRecord, URL

### Community 14 - "Configuration"
Cohesion: 0.47
Nodes (3): Config, String, URL

### Community 15 - "Build Targets"
Cohesion: 0.50
Nodes (4): build-app.sh bundle build script, HermesVoice executable target, HermesVoiceKit target, HermesVoiceTests target

### Community 23 - "Community 23"
Cohesion: 0.18
Nodes (11): CodeBlockConfiguration, CodeSyntaxHighlighter, HermesCodeBlockView, HermesCodeSyntaxHighlighter, HighlightrEngine, MarkdownMessageView, MarkdownUI.Theme, MarkdownUI (+3 more)

### Community 24 - "Community 24"
Cohesion: 0.31
Nodes (8): ImageAttachment, ImageEncoder, Bool, CGFloat, Data, NSImage, String, UUID

### Community 25 - "Community 25"
Cohesion: 0.29
Nodes (5): EventHandlerRef, EventHotKeyRef, HotKeyManager, Void, UInt32

## Knowledge Gaps
- **112 isolated node(s):** `PreToolUse`, `Notification.Name`, `Bool`, `URL`, `Any` (+107 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `OverlayViewModel` connect `Conversation View Model` to `App Lifecycle & Hotkeys`, `API Client & Streaming`, `History & Overlay UI`, `Button Styles & Visuals`, `Conversation File Store`?**
  _High betweenness centrality (0.387) - this node is a cross-community bridge._
- **Why does `AppDelegate` connect `App Lifecycle & Hotkeys` to `Conversation View Model`?**
  _High betweenness centrality (0.154) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `Theme & Appearance` to `App Lifecycle & Hotkeys`, `Button Styles & Visuals`, `History & Overlay UI`, `Community 23`?**
  _High betweenness centrality (0.120) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `OverlayViewModel` (e.g. with `Resume-last-conversation on launch` and `VoiceEngine (Speech + AVAudioEngine)`) actually correct?**
  _`OverlayViewModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PreToolUse`, `Notification.Name`, `Bool` to the rest of the system?**
  _116 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `App Lifecycle & Hotkeys` be split into smaller, more focused modules?**
  _Cohesion score 0.07402031930333818 - nodes in this community are weakly interconnected._
- **Should `Conversation View Model` be split into smaller, more focused modules?**
  _Cohesion score 0.08020344287949922 - nodes in this community are weakly interconnected._