# Graph Report - HermesVoice  (2026-06-07)

## Corpus Check
- 35 files · ~19,869 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 485 nodes · 881 edges · 32 communities (22 shown, 10 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `745d4e05`
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
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]

## God Nodes (most connected - your core abstractions)
1. `OverlayViewModel` - 47 edges
2. `AppDelegate` - 25 edges
3. `VoiceEngine` - 19 edges
4. `OverlayPanel` - 18 edges
5. `SwiftUI` - 17 edges
6. `ChatMessage` - 15 edges
7. `SessionMeta` - 15 edges
8. `TranscriptRecord` - 15 edges
9. `HermesAPIError` - 14 edges
10. `View` - 13 edges

## Surprising Connections (you probably didn't know these)
- `SSEParserTests` --references--> `SSEParser.parse(line:)`  [EXTRACTED]
  Tests/HermesVoiceTests/SSEParserTests.swift → Sources/HermesVoiceKit/SSEParser.swift
- `main test runner entry point` --references--> `PanelStateMachine`  [EXTRACTED]
  Tests/HermesVoiceTests/main.swift → Sources/HermesVoice/OverlayPanel.swift
- `PanelStateMachine` --references--> `TestCase`  [EXTRACTED]
  Sources/HermesVoice/OverlayPanel.swift → Tests/HermesVoiceTests/TestHarness.swift
- `PanelStateMachine` --references--> `TestCase`  [EXTRACTED]
  Sources/HermesVoice/OverlayPanel.swift → Tests/HermesVoiceTests/PanelStateMachineTests.swift
- `SSEParserTests` --references--> `ToolActivity`  [EXTRACTED]
  Tests/HermesVoiceTests/SSEParserTests.swift → Sources/HermesVoiceKit/SSEParser.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Conversation persistence flow (VM -> file store -> pure store)** — hermesvoice_overlayviewmodel_overlayviewmodel, hermesvoice_conversationfilestore_conversationfilestore, hermesvoicekit_conversationstore_conversationstore [INFERRED 0.85]
- **In-panel history browser feature** — hermesvoice_historyview_historyview, hermesvoice_overlayviewmodel_filteredhistory, hermesvoice_overlayviewmodel_openconversation, hermesvoicekit_conversationstore_conversationstore [INFERRED 0.75]
- **Persisted local data model (SessionMeta + TranscriptRecord)** — hermesvoicekit_conversationstore_sessionmeta, hermesvoicekit_conversationstore_transcriptrecord, hermesvoice_conversationfilestore_conversationfilestore, hermesvoice_overlayviewmodel_overlayviewmodel [INFERRED 0.75]

## Communities (32 total, 10 thin omitted)

### Community 0 - "App Lifecycle & Hotkeys"
Cohesion: 0.08
Nodes (16): EventHandlerRef, EventHotKeyRef, AppDelegate, HotKeyManager, HotKeyManager, Int32, Notification, NSApplicationDelegate (+8 more)

### Community 1 - "Conversation View Model"
Cohesion: 0.08
Nodes (29): HermesAPIError, ChatMessage, ConnectionState, offline, online, unknown, HistoryEntry, OverlayViewModel (+21 more)

### Community 2 - "API Client & Streaming"
Cohesion: 0.10
Nodes (22): AsyncThrowingStream, Error, HermesErrorKind, HermesAPIClient, HermesAPIError, auth, http, invalidResponse (+14 more)

### Community 3 - "Conversation Storage & History"
Cohesion: 0.12
Nodes (24): Codable, Double, Equatable, ConversationFileStore.appendRecord, ConversationFileStore.deleteConversation, ConversationFileStore.loadIndex, ConversationFileStore.loadPreview, ConversationFileStore.loadTranscript (+16 more)

### Community 4 - "Error Handling & Utilities"
Cohesion: 0.12
Nodes (20): APIKeyParser.parse(env:), Debouncer.shouldFire(at:), APIKeyParserTests, DebouncerTests, main test runner entry point, SSEParserTests, check(), checkEqual() (+12 more)

### Community 5 - "History & Overlay UI"
Cohesion: 0.25
Nodes (8): OverlayState, done, error, idle, listening, responding, sending, transcribing

### Community 6 - "SSE Parsing"
Cohesion: 0.19
Nodes (14): Decodable, Choice, Chunk, Delta, SSEParser.parse(line:), SSEParser.parseContent(payload:), SSEEvent, content (+6 more)

### Community 7 - "Overhaul Plan & Design Decisions"
Cohesion: 0.11
Nodes (18): 0. Orientation (read first), 1. Confirmed decisions (the spec), 2. Hermes server API reference (verified from `~/.hermes/hermes-agent/gateway/platforms/api_server.py`), 3. Known bugs / gaps (root causes), 4. Phased implementation plan, 5. Cross-cutting rules ("don't break the app"), 6. Open items to verify during implementation, HermesVoice Overhaul Plan (+10 more)

### Community 8 - "Panel State Machine"
Cohesion: 0.09
Nodes (16): Debouncer, PanelStateMachine.beginHide, PanelStateMachine.beginShow, PanelPhase, hidden, hiding, showing, visible (+8 more)

### Community 9 - "Button Styles & Visuals"
Cohesion: 0.09
Nodes (26): ChatMessage, Color, HistoryRow, HistoryView, ContentHeightKey, MessageBubble, OverlayView, PendingImageChip (+18 more)

### Community 10 - "Overlay Panel Transitions"
Cohesion: 0.17
Nodes (8): OverlayPanel, NSEvent, NSPanel, PanelPhase, Bool, CGFloat, OverlayViewModel, Void

### Community 11 - "Theme & Appearance"
Cohesion: 0.12
Nodes (15): AppDelegate, HermesVoiceApp, Notification.Name, Appearance, Colors, Font, Layout, Motion (+7 more)

### Community 12 - "Voice & Speech Engine"
Cohesion: 0.14
Nodes (13): AVAudioEngine, VoiceEngine, ObservableObject, SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask, SFSpeechRecognizerAuthorizationStatus, Bool, CGFloat (+5 more)

### Community 13 - "Conversation File Store"
Cohesion: 0.29
Nodes (9): ConversationFileStore.atomicWrite, ConversationFileStore (disk IO), ConversationFileStore, Data, SessionMeta, String, URL, TranscriptRecord (+1 more)

### Community 14 - "Configuration"
Cohesion: 0.47
Nodes (3): Config, String, URL

### Community 15 - "Build Targets"
Cohesion: 0.19
Nodes (17): ButtonStyle, CircleButtonStyle (mic toggle), IconButtonStyle, SendButtonStyle, Configuration, CircleButtonStyle, IconButtonStyle, SendButtonStyle (+9 more)

### Community 23 - "Community 23"
Cohesion: 0.18
Nodes (11): CodeBlockConfiguration, CodeSyntaxHighlighter, HermesCodeBlockView, HermesCodeSyntaxHighlighter, HighlightrEngine, MarkdownMessageView, MarkdownUI.Theme, MarkdownUI (+3 more)

### Community 24 - "Community 24"
Cohesion: 0.31
Nodes (8): ImageAttachment, ImageEncoder, Bool, CGFloat, Data, NSImage, String, UUID

### Community 25 - "Community 25"
Cohesion: 0.16
Nodes (14): HermesErrorClassifier.classify, HermesErrorClassifier, HermesErrorKind, auth, http, offline, streamDropped, timeout (+6 more)

### Community 26 - "Community 26"
Cohesion: 0.67
Nodes (3): VoiceEngine.startRecording, VoiceEngine.startSilenceDetection, VoiceEngine (Speech + AVAudioEngine)

## Knowledge Gaps
- **126 isolated node(s):** `Notification.Name`, `NSStatusItem`, `NSRunningApplication`, `Int32`, `Bool` (+121 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Task` connect `Conversation View Model` to `App Lifecycle & Hotkeys`, `Button Styles & Visuals`, `API Client & Streaming`?**
  _High betweenness centrality (0.192) - this node is a cross-community bridge._
- **Why does `OverlayViewModel` connect `Conversation View Model` to `Voice & Speech Engine`, `History & Overlay UI`?**
  _High betweenness centrality (0.189) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `Theme & Appearance` to `App Lifecycle & Hotkeys`, `Button Styles & Visuals`, `Community 23`, `Build Targets`?**
  _High betweenness centrality (0.136) - this node is a cross-community bridge._
- **What connects `Notification.Name`, `NSStatusItem`, `NSRunningApplication` to the rest of the system?**
  _126 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `App Lifecycle & Hotkeys` be split into smaller, more focused modules?**
  _Cohesion score 0.08367071524966262 - nodes in this community are weakly interconnected._
- **Should `Conversation View Model` be split into smaller, more focused modules?**
  _Cohesion score 0.07932310946589106 - nodes in this community are weakly interconnected._
- **Should `API Client & Streaming` be split into smaller, more focused modules?**
  _Cohesion score 0.10461538461538461 - nodes in this community are weakly interconnected._