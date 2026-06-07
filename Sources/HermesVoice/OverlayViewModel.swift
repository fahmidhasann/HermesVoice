import Foundation
import Combine
import AppKit
import HermesVoiceKit

enum OverlayState: Equatable {
    case idle
    case listening
    case transcribing
    case sending
    case responding
    case done
    case error
}

/// Reachability of the Hermes gateway, surfaced for an offline indicator.
enum ConnectionState: Equatable {
    case unknown
    case online
    case offline
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    var isStreaming: Bool
    /// True when a response was cut short (drop/cancel) and may be retried.
    var isIncomplete: Bool
    let timestamp: Date
    /// Image attachments (`data:image/...;base64,…` URLs) sent with this message.
    var imageDataURLs: [String]

    init(role: Role,
         content: String,
         isStreaming: Bool = false,
         isIncomplete: Bool = false,
         timestamp: Date = Date(),
         imageDataURLs: [String] = [],
         id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.isIncomplete = isIncomplete
        self.timestamp = timestamp
        self.imageDataURLs = imageDataURLs
    }

    enum Role: String {
        case user
        case assistant
        case error
    }
}

/// Facade over exactly one foreground `ChatSession`. The SwiftUI layer observes
/// this single object and reads both per-session fields (mirrored from the
/// foreground session) and global fields (input draft, voice, connection,
/// history). Per-session work is forwarded to the session; the views never need
/// to know a session was swapped underneath them.
@MainActor
class OverlayViewModel: ObservableObject {
    // MARK: - Per-session fields, mirrored from the foreground session

    @Published var state: OverlayState = .idle
    @Published var chatMessages: [ChatMessage] = []
    @Published var errorMessage: String = ""
    /// Tool steps currently running, surfaced for live "Hermes is using…" rows.
    @Published var activeTools: [ToolActivity] = []

    // MARK: - Global fields (owned by the facade)

    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var transcribedText: String = ""
    @Published var panelShouldFocus: Bool = false
    @Published var audioLevel: CGFloat = 0.1
    /// Images staged in the input (paste/drag) to send with the next message.
    @Published var pendingImages: [ImageAttachment] = []
    /// Reachability of the gateway (drives the offline indicator).
    @Published var connectionState: ConnectionState = .unknown

    // MARK: - History browser state

    /// One row in the in-panel history list: session metadata + a preview of the
    /// most recent message.
    struct HistoryEntry: Identifiable, Equatable {
        let meta: SessionMeta
        let preview: String
        var id: String { meta.id }
    }

    /// True while the panel is flipped to the searchable history list.
    @Published var showingHistory = false
    /// Live search text for the history list.
    @Published var historyQuery = ""
    /// All stored conversations, loaded when the history view opens.
    @Published var historyEntries: [HistoryEntry] = []
    /// Pulses true to ask the history view to focus its search field.
    @Published var historySearchShouldFocus = false

    /// Entries matching the current search text (or all, when the box is empty).
    var filteredHistory: [HistoryEntry] {
        historyEntries.filter {
            ConversationStore.matchesQuery(title: $0.meta.title,
                                           preview: $0.preview,
                                           query: historyQuery)
        }
    }

    // MARK: - Collaborators

    private var voiceEngine: VoiceEngine?
    private let apiClient = HermesAPIClient()
    private let store = ConversationFileStore()
    private let indexWriter: SessionIndexWriter

    /// Holds every live session so streams survive panel hide / focus loss /
    /// switch, and ref-counts the App Nap assertion across them (§4.3). Owned
    /// here because the facade is a forever-singleton.
    private let manager = SessionManager()

    /// The conversation currently shown. Per-session state is mirrored from here.
    private(set) var foreground: ChatSession
    /// Subscriptions mirroring the foreground session's published fields. Torn
    /// down and rebuilt on every session swap (§4.1).
    private var sessionCancellables = Set<AnyCancellable>()

    /// The session that owned the mic when recording started. A finished
    /// transcript is routed back to it (if still live) rather than to whatever
    /// is foreground when the async result lands, so switching mid-record can't
    /// misdeliver speech (§4.6). Weak so a torn-down target falls back cleanly.
    private weak var recordingTarget: ChatSession?

    /// Upper bound on images staged for a single message.
    let maxAttachments = 6

    /// Local id of the conversation currently shown (forwarded for callers that
    /// compare against the open conversation, e.g. menu-bar recents).
    var conversationId: String { foreground.conversationId }

    // MARK: - Background-activity surfacing (Phase 5)

    /// True while any session — foreground or background — is streaming. The
    /// menu-bar status item observes this to animate while a hidden-panel
    /// background stream runs (§4.8). The manager is private, so the facade
    /// re-publishes its signals for `AppDelegate`.
    var anyStreamingPublisher: AnyPublisher<Bool, Never> {
        manager.$isAnyStreaming.eraseToAnyPublisher()
    }

    /// Fires the id of a session that just finished a response, so the app can
    /// post an ambient completion cue for background finishes (§4.8).
    var sessionFinishedPublisher: AnyPublisher<String, Never> {
        manager.didFinish.eraseToAnyPublisher()
    }

    init() {
        indexWriter = SessionIndexWriter(store: store)

        // Resume the most recent conversation (or start a blank one).
        let sessions = store.loadIndex()
        let initial: ChatSession
        if let recent = ConversationStore.mostRecent(in: sessions) {
            initial = ChatSession(conversationId: recent.id,
                                  startedAt: Date(timeIntervalSince1970: recent.startedAt),
                                  model: recent.model,
                                  store: store,
                                  apiClient: apiClient,
                                  indexWriter: indexWriter,
                                  initialMessages: OverlayViewModel.loadMessages(id: recent.id, store: store))
        } else {
            initial = ChatSession(conversationId: UUID().uuidString,
                                  startedAt: Date(),
                                  model: nil,
                                  store: store,
                                  apiClient: apiClient,
                                  indexWriter: indexWriter)
        }
        foreground = initial
        // All stored properties are initialized — now legal to touch `self`.
        manager.register(initial)

        voiceEngine = VoiceEngine()
        voiceEngine?.onPartialResult = { [weak self] text in
            Task { @MainActor in self?.transcribedText = text }
        }
        voiceEngine?.onFinalResult = { [weak self] text in
            Task { @MainActor in self?.handleTranscript(text) }
        }
        voiceEngine?.onError = { [weak self] error in
            Task { @MainActor in
                self?.foreground.state = .error
                self?.foreground.errorMessage = error
                self?.isRecording = false
            }
        }
        voiceEngine?.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }

        bindForeground(foreground)
    }

    // MARK: - Foreground mirroring (§4.1)

    /// Point the facade at `session`: tear down the old subscriptions, swap the
    /// foreground reference, **synchronously copy** every mirrored field (so the
    /// view never shows one stale frame before Combine catches up), then
    /// re-subscribe with cancellable `.sink`s.
    private func bindForeground(_ session: ChatSession) {
        sessionCancellables.removeAll()
        foreground = session

        // 1. Synchronous pre-copy — mandatory; without it a reopened session
        //    shows the previous transcript for one frame.
        state = session.state
        chatMessages = session.chatMessages
        errorMessage = session.errorMessage
        activeTools = session.activeTools

        // 2. Re-subscribe. Explicit `.sink` (NOT `assign(to:&$…)`) so the old
        //    session stops writing into the facade the moment we re-point.
        session.$state.sink { [weak self] in self?.state = $0 }.store(in: &sessionCancellables)
        session.$chatMessages.sink { [weak self] in self?.chatMessages = $0 }.store(in: &sessionCancellables)
        session.$errorMessage.sink { [weak self] in self?.errorMessage = $0 }.store(in: &sessionCancellables)
        session.$activeTools.sink { [weak self] in self?.activeTools = $0 }.store(in: &sessionCancellables)

        // Global connection state is reported up from the session's stream.
        session.onConnectionState = { [weak self] in self?.connectionState = $0 }
    }

    /// Create a session and register it with the manager so it survives in the
    /// background. Single chokepoint so every new/loaded session is registered.
    private func makeSession(id: String,
                             startedAt: Date,
                             model: String?,
                             initialMessages: [ChatMessage] = []) -> ChatSession {
        let session = ChatSession(conversationId: id,
                                  startedAt: startedAt,
                                  model: model,
                                  store: store,
                                  apiClient: apiClient,
                                  indexWriter: indexWriter,
                                  initialMessages: initialMessages)
        manager.register(session)
        return session
    }

    /// Load a conversation's messages from disk, folding any leftover `.partial`
    /// crash-recovery side-file into a trailing **incomplete** (retryable)
    /// assistant message per the deterministic rule (§4.7), and clearing the
    /// side-file once reconciled. Static so it can run during `init` before all
    /// stored properties are set. Every load path goes through here so a ⌘Q
    /// mid-stream is recovered identically on relaunch and on reopen.
    private static func loadMessages(id: String, store: ConversationFileStore) -> [ChatMessage] {
        let records = store.loadTranscript(id: id)
        var messages = ChatSession.mapRecords(records)
        guard let partial = store.readPartial(id: id) else { return messages }

        let lastRole = records.last?.role
        let trailingAssistant = lastRole == "assistant" ? records.last?.content : nil
        switch PartialReconciler.decide(lastJSONLRole: lastRole,
                                        partialContent: partial.content,
                                        trailingAssistantContent: trailingAssistant) {
        case .fold:
            messages.append(ChatMessage(role: .assistant,
                                        content: partial.content,
                                        isIncomplete: true,
                                        timestamp: Date(timeIntervalSince1970: partial.ts)))
            store.clearPartial(id: id)
        case .deleteOnly:
            store.clearPartial(id: id)
        case .ignore:
            break
        }
        return messages
    }

    /// Before switching the foreground away, drop the outgoing session from the
    /// manager **unless** it's worth keeping resident — i.e. it's streaming, or
    /// has a retryable error/partial. Streaming/errored sessions stay alive in
    /// the background so returning to them shows live or retryable state
    /// (§0 #1/#5); clean idle/done sessions are reloaded identically from disk,
    /// which keeps live-session memory bounded without Phase-4 eviction.
    private func releaseForegroundIfDisposable() {
        let outgoing = foreground
        guard !outgoing.isBusy, !outgoing.canRetry else { return }
        outgoing.teardown()
        manager.remove(id: outgoing.conversationId)
    }

    // MARK: - Voice

    /// Current voice flow from Settings (read fresh so changes apply next record).
    private var voiceFlow: VoiceFlow { AppSettingsStore.loadCurrent().voiceFlow }

    /// Tap behavior for the mic button in toggle modes (review / auto-send).
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Push-to-talk: begin capture while the mic button is held.
    func startHoldRecording() {
        guard !isRecording else { return }
        startRecording()
    }

    /// Push-to-talk: release → finalize the transcript (which sends, per flow).
    func endHoldRecording() {
        guard isRecording else { return }
        stopRecording()
    }

    private func startRecording() {
        guard let engine = voiceEngine, engine.isAvailable else {
            foreground.state = .error
            foreground.errorMessage = "Speech recognition unavailable"
            return
        }
        transcribedText = ""
        foreground.errorMessage = ""
        isRecording = true
        foreground.state = .listening
        // Pin the transcript's destination to the session that owned the mic at
        // record-start, so switching sessions mid-record can't misroute it (§4.6).
        recordingTarget = foreground
        engine.startRecording(autoStopOnSilence: voiceFlow.stopsOnSilence)
    }

    /// Manually end capture and let the engine deliver the transcript through
    /// `handleTranscript`, which routes it per the active voice flow.
    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false   // snappy UI; the transcript arrives via onFinalResult
        voiceEngine?.finish()
    }

    /// Route a finished transcript according to the active voice flow: fill the
    /// input for review (default), or send it immediately (auto-send / PTT).
    private func handleTranscript(_ text: String) {
        isRecording = false
        transcribedText = ""
        switch voiceFlow.outcome(for: text) {
        case .ignore:
            // No speech recognized — return to idle quietly and refocus input.
            if foreground.state == .listening || foreground.state == .transcribing {
                foreground.state = .idle
            }
            pulseInputFocus()
        case .fill(let transcript):
            let existing = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            inputText = existing.isEmpty ? transcript : existing + " " + transcript
            if foreground.state == .listening { foreground.state = .idle }
            pulseInputFocus()
        case .send(let transcript):
            // Route to the record-start session if it's still live, else fall
            // back to the current foreground (§4.6).
            let target = recordingTarget.flatMap { manager.session(for: $0.conversationId) } ?? foreground
            target.state = .transcribing
            routeSend(text: transcript, images: [], to: target)
        }
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty else { return }
        inputText = ""
        routeSend(text: text, images: images, to: foreground)
    }

    /// Global pre-send housekeeping (stop mic, clear transcription/staged
    /// images), then hand the message to `target`. Guarding on the **target's**
    /// busy state (not always the foreground's) lets a different session send
    /// concurrently. Bails when the target is busy so nothing global is cleared
    /// on a blocked send.
    private func routeSend(text: String, images: [ImageAttachment], to target: ChatSession) {
        guard !target.isBusy else { return }
        if isRecording {
            isRecording = false
            voiceEngine?.stopRecording()
        }
        transcribedText = ""
        pendingImages = []
        target.send(text: text, images: images)
    }

    // MARK: - Image attachments

    /// Stage an image (from paste or drag-drop) to send with the next message.
    func attachImage(_ image: NSImage) {
        guard pendingImages.count < maxAttachments else { return }
        guard let attachment = ImageAttachment(image: image) else { return }
        pendingImages.append(attachment)
        pulseInputFocus()
    }

    func removePendingImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    /// Whether a retry affordance should be offered (delegated to the session).
    var canRetry: Bool { foreground.canRetry }

    /// Re-run the last response on the foreground session.
    func retryLast() {
        foreground.retryLast()
    }

    /// Stop an in-flight streamed response on the foreground session.
    func cancelStreaming() {
        foreground.cancelStreaming()
    }

    // MARK: - Lifecycle

    func reset() {
        // Called when the panel is shown. GLOBAL concerns only — must NOT touch
        // the foreground session's state/errorMessage, or reopening to a
        // live/errored session would wipe the very thing the user came back to
        // see or retry (§4.2). The per-session 1.5s timer handles done→idle.
        voiceEngine?.stopRecording()
        isRecording = false
        transcribedText = ""
        // Refresh the reachability indicator each time the panel opens.
        checkConnection()
        // Trigger focus on next render
        pulseInputFocus()
    }

    /// Briefly raises `panelShouldFocus` so the input field grabs focus on the
    /// next render, then lowers it.
    private func pulseInputFocus() {
        panelShouldFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.panelShouldFocus = false
        }
    }

    /// Briefly raises `historySearchShouldFocus` so the history search field
    /// grabs focus on the next render.
    private func pulseHistorySearchFocus() {
        historySearchShouldFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.historySearchShouldFocus = false
        }
    }

    /// Probe `/v1/health` and update `connectionState`.
    func checkConnection() {
        Task { [weak self] in
            guard let self else { return }
            let healthy = await self.apiClient.checkHealth()
            self.connectionState = healthy ? .online : .offline
        }
    }

    /// Start a fresh, empty conversation. The previous one stays persisted; the
    /// new one is written to the index only once the user sends a message.
    func newChat() {
        startBlankConversation()
        showingHistory = false
        pulseInputFocus()
    }

    /// Swap the foreground to a fresh blank conversation **without** killing the
    /// previous one: a streaming/errored session is left running in the
    /// background (§0 #1/#2); only a disposable idle session is released.
    private func startBlankConversation() {
        releaseForegroundIfDisposable()
        voiceEngine?.stopRecording()
        inputText = ""
        transcribedText = ""
        isRecording = false
        pendingImages = []
        let session = makeSession(id: UUID().uuidString, startedAt: Date(), model: nil)
        bindForeground(session)
    }

    // MARK: - History browser

    /// Flip the panel to the history list, loading the current index + previews.
    func openHistory(focusSearch: Bool = false) {
        reloadHistory()
        showingHistory = true
        if focusSearch { pulseHistorySearchFocus() }
    }

    /// Return from the history list to the conversation, refocusing the input.
    func closeHistory() {
        showingHistory = false
        historyQuery = ""
        pulseInputFocus()
    }

    /// Most-recent conversations for the menu-bar recents list. The index is
    /// kept most-recent-first, but sort defensively so ordering never depends on
    /// write order.
    func recentSessions(limit: Int) -> [SessionMeta] {
        Array(store.loadIndex().sorted { $0.lastActiveAt > $1.lastActiveAt }.prefix(limit))
    }

    /// Re-read the on-disk index and build preview snippets for each row.
    func reloadHistory() {
        historyEntries = store.loadIndex().map { meta in
            HistoryEntry(meta: meta, preview: store.loadPreview(id: meta.id))
        }
    }

    /// Switch to a stored conversation. Identity is the foreground session id: a
    /// no-op if it's already shown; otherwise re-point to its **live** session if
    /// one is resident (no disk load, so a still-streaming background session is
    /// reattached with its live progress), else load it from disk (§4.11).
    /// Either way the previously-foreground stream is left running.
    func openConversation(id: String) {
        // Re-opening the conversation already shown is a no-op beyond closing.
        guard id != foreground.conversationId else { closeHistory(); return }

        let target: ChatSession
        if let live = manager.session(for: id) {
            releaseForegroundIfDisposable()
            target = live
        } else {
            guard let meta = historyEntries.first(where: { $0.id == id })?.meta
                    ?? store.loadIndex().first(where: { $0.id == id }) else { return }
            releaseForegroundIfDisposable()
            target = makeSession(id: meta.id,
                                 startedAt: Date(timeIntervalSince1970: meta.startedAt),
                                 model: meta.model,
                                 initialMessages: Self.loadMessages(id: meta.id, store: store))
        }

        voiceEngine?.stopRecording()
        inputText = ""
        transcribedText = ""
        isRecording = false
        pendingImages = []
        bindForeground(target)

        showingHistory = false
        historyQuery = ""
        pulseInputFocus()
    }

    /// Delete a stored conversation (index entry + transcript + `.partial`). If
    /// a live session exists for it: (1) `markDeleted()` — set `isDeleted` and
    /// cancel its stream so no late chunk can write disk, (2) remove it from the
    /// manager, (3) **then** delete disk (§4.5). A chunk arriving after cancel
    /// but before the Task observes it is now blocked by the `isDeleted` guard,
    /// so the just-deleted files can't be resurrected. If it's the one currently
    /// open, fall back to a fresh blank conversation.
    func deleteConversation(id: String) {
        if let live = manager.session(for: id) {
            live.markDeleted()
            manager.remove(id: id)
        }
        store.deleteConversation(id: id)
        reloadHistory()
        if id == foreground.conversationId {
            startBlankConversation()
        }
    }

    func cleanup() {
        // Panel hidden — stop only the mic. The foreground session keeps
        // streaming in the background (the whole point of Phase 3); it is NOT
        // torn down here anymore.
        voiceEngine?.stopRecording()
        isRecording = false
    }
}
