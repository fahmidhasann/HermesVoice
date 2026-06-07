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

@MainActor
class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .idle
    @Published var chatMessages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var errorMessage: String = ""
    @Published var isRecording: Bool = false
    @Published var transcribedText: String = ""
    @Published var panelShouldFocus: Bool = false
    @Published var audioLevel: CGFloat = 0.1
    /// Tool steps currently running, surfaced for live "Hermes is using…" rows.
    @Published var activeTools: [ToolActivity] = []
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

    private var voiceEngine: VoiceEngine?
    private let apiClient = HermesAPIClient()
    private let store = ConversationFileStore()
    private var streamTask: Task<Void, Never>?

    /// Stable id of the assistant message currently being streamed into. The
    /// positional index is invalid across the async boundary and across
    /// in-session mutations (retry removes a row), so we resolve the index fresh
    /// from this id at every access and clear it on every terminal path.
    private var streamingMessageId: UUID?

    /// Resolve the live index of the streaming target, fresh at each access.
    /// Returns nil if the target was removed (reset/retry/delete).
    private func streamingIndex() -> Int? {
        guard let id = streamingMessageId else { return nil }
        return chatMessages.firstIndex(where: { $0.id == id })
    }

    /// Local id of the conversation currently shown. Stable for the life of the
    /// conversation; the server derives its own session id from the first message.
    private(set) var conversationId: String
    private var conversationStartedAt: Date
    private var conversationModel: String?

    private let maxAttempts = 3
    /// Upper bound on images staged for a single message.
    let maxAttachments = 6

    init() {
        // Resume the most recent conversation (or start a blank one).
        let sessions = store.loadIndex()
        if let recent = ConversationStore.mostRecent(in: sessions) {
            conversationId = recent.id
            conversationStartedAt = Date(timeIntervalSince1970: recent.startedAt)
            conversationModel = recent.model
        } else {
            conversationId = UUID().uuidString
            conversationStartedAt = Date()
            conversationModel = nil
        }

        voiceEngine = VoiceEngine()
        voiceEngine?.onPartialResult = { [weak self] text in
            Task { @MainActor in self?.transcribedText = text }
        }
        voiceEngine?.onFinalResult = { [weak self] text in
            Task { @MainActor in self?.handleTranscript(text) }
        }
        voiceEngine?.onError = { [weak self] error in
            Task { @MainActor in
                self?.state = .error
                self?.errorMessage = error
                self?.isRecording = false
            }
        }
        voiceEngine?.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }

        // Load the resumed transcript into the thread.
        let records = store.loadTranscript(id: conversationId)
        chatMessages = records.map { record in
            ChatMessage(role: ChatMessage.Role(rawValue: record.role) ?? .assistant,
                        content: record.content,
                        timestamp: Date(timeIntervalSince1970: record.ts),
                        imageDataURLs: record.images ?? [])
        }
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
            state = .error
            errorMessage = "Speech recognition unavailable"
            return
        }
        transcribedText = ""
        errorMessage = ""
        isRecording = true
        state = .listening
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
            if state == .listening || state == .transcribing { state = .idle }
            pulseInputFocus()
        case .fill(let transcript):
            let existing = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            inputText = existing.isEmpty ? transcript : existing + " " + transcript
            if state == .listening { state = .idle }
            pulseInputFocus()
        case .send(let transcript):
            state = .transcribing
            sendToHermes(text: transcript)
        }
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty else { return }
        inputText = ""
        sendToHermes(text: text, images: images)
    }

    private func sendToHermes(text: String, images: [ImageAttachment] = []) {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty || !images.isEmpty else { return }
        guard state != .sending, state != .responding else { return }

        if isRecording {
            isRecording = false
            voiceEngine?.stopRecording()
        }
        transcribedText = ""
        errorMessage = ""

        let imageURLs = images.map { $0.dataURL }
        registerConversationIfNeeded(
            firstUserText: messageText.isEmpty ? "Image message" : messageText)
        let userMessage = ChatMessage(role: .user, content: messageText, imageDataURLs: imageURLs)
        chatMessages.append(userMessage)
        pendingImages = []
        persist(userMessage)

        generateResponse()
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

    /// Whether a retry affordance should be offered (last attempt failed or was
    /// interrupted, and there is a user message to re-answer).
    var canRetry: Bool {
        guard chatMessages.contains(where: { $0.role == .user }) else { return false }
        if state == .error { return true }
        if let last = chatMessages.last, last.role == .assistant, last.isIncomplete { return true }
        return false
    }

    /// Re-run the last response. Drops a kept partial first so the retry is clean.
    func retryLast() {
        guard canRetry, state != .sending, state != .responding else { return }
        if let lastIndex = chatMessages.indices.last,
           chatMessages[lastIndex].role == .assistant,
           chatMessages[lastIndex].isIncomplete {
            // Drop the kept partial. Clear any stale streaming target pointing at
            // it so the row removal can't be mis-resolved by a late access.
            if streamingMessageId == chatMessages[lastIndex].id { streamingMessageId = nil }
            chatMessages.remove(at: lastIndex)
            rewritePersistedTranscript()
        }
        errorMessage = ""
        guard chatMessages.contains(where: { $0.role == .user }) else { return }
        generateResponse()
    }

    /// Appends a streaming assistant placeholder and fills it from the stream,
    /// auto-retrying transient failures until the first content arrives.
    private func generateResponse() {
        // Full message array for the request: user + assistant turns so far,
        // excluding any error rows (and the placeholder we're about to add).
        let messages = chatMessages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { OutgoingMessage(role: $0.role.rawValue,
                                   text: $0.content,
                                   imageDataURLs: $0.imageDataURLs) }

        let placeholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
        chatMessages.append(placeholder)
        streamingMessageId = placeholder.id
        activeTools = []

        state = .sending
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runStream(messages: messages)
        }
    }

    private func runStream(messages: [OutgoingMessage]) async {
        var attempt = 0
        while true {
            attempt += 1
            var receivedContent = streamingIndex().map { !chatMessages[$0].content.isEmpty } ?? false
            do {
                state = .responding
                if let index = streamingIndex() {
                    chatMessages[index].isIncomplete = false
                }

                let stream = try await apiClient.streamCompletion(messages: messages)
                connectionState = .online

                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .text(let chunk):
                        receivedContent = true
                        if let index = streamingIndex() {
                            chatMessages[index].content += chunk
                        }
                    case .tool(let activity):
                        applyToolActivity(activity)
                    }
                }

                finishAssistant()
                state = .done
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                if state == .done { state = .idle }
                return
            } catch {
                if Task.isCancelled { return }
                let apiError = (error as? HermesAPIError) ?? .streamDropped

                // Retry transient failures, but only before any content arrives —
                // once text is streaming we keep it instead of restarting.
                if apiError.isTransient, !receivedContent, attempt < maxAttempts {
                    let backoff = UInt64(Double(attempt) * 0.5 * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }

                handleStreamFailure(apiError, hadContent: receivedContent)
                return
            }
        }
    }

    /// Finalize a fully-streamed assistant message: stop the spinner and persist
    /// it, or drop an empty placeholder if nothing arrived.
    private func finishAssistant() {
        activeTools = []
        defer { streamingMessageId = nil }
        guard let index = streamingIndex() else { return }
        chatMessages[index].isStreaming = false
        chatMessages[index].isIncomplete = false
        if chatMessages[index].content.isEmpty {
            chatMessages.remove(at: index)
        } else {
            persist(chatMessages[index])
        }
    }

    private func handleStreamFailure(_ error: HermesAPIError, hadContent: Bool) {
        activeTools = []
        if error.kind == .offline { connectionState = .offline }

        if let index = streamingIndex() {
            if hadContent, !chatMessages[index].content.isEmpty {
                // Keep the partial response, mark it incomplete, and offer a retry.
                chatMessages[index].isStreaming = false
                chatMessages[index].isIncomplete = true
                persist(chatMessages[index])
            } else if chatMessages[index].role == .assistant,
                      chatMessages[index].content.isEmpty {
                // Nothing useful arrived — drop the empty placeholder.
                chatMessages.remove(at: index)
            }
        }

        streamingMessageId = nil
        errorMessage = error.errorDescription ?? "Something went wrong."
        state = .error
    }

    private func applyToolActivity(_ activity: ToolActivity) {
        switch activity.status {
        case .running:
            if let index = activeTools.firstIndex(where: { $0.toolCallId == activity.toolCallId }) {
                activeTools[index] = activity
            } else {
                activeTools.append(activity)
            }
        case .completed:
            activeTools.removeAll { $0.toolCallId == activity.toolCallId }
        }
    }

    /// Cancels an in-flight streamed response, keeping whatever text has
    /// already arrived (marked incomplete), and returns to idle.
    func cancelStreaming() {
        guard state == .sending || state == .responding else { return }
        streamTask?.cancel()
        streamTask = nil
        activeTools = []
        if let index = streamingIndex(), chatMessages[index].isStreaming {
            chatMessages[index].isStreaming = false
            if chatMessages[index].content.isEmpty {
                // Drop an empty assistant placeholder so the thread isn't blank.
                chatMessages.remove(at: index)
            } else {
                chatMessages[index].isIncomplete = true
                persist(chatMessages[index])
            }
        }
        streamingMessageId = nil
        state = .idle
    }

    // MARK: - Persistence

    /// Register a brand-new conversation in the index on its first message.
    private func registerConversationIfNeeded(firstUserText: String) {
        var sessions = store.loadIndex()
        guard !sessions.contains(where: { $0.id == conversationId }) else { return }
        let now = Date().timeIntervalSince1970
        let meta = SessionMeta(id: conversationId,
                               title: ConversationStore.deriveTitle(from: firstUserText),
                               startedAt: conversationStartedAt.timeIntervalSince1970,
                               lastActiveAt: now,
                               messageCount: 0,
                               model: conversationModel)
        sessions = ConversationStore.upsert(meta, into: sessions)
        store.saveIndex(sessions)
    }

    /// Append one message to the transcript and refresh the index metadata.
    private func persist(_ message: ChatMessage) {
        guard message.role == .user || message.role == .assistant else { return }
        let record = TranscriptRecord(role: message.role.rawValue,
                                      content: message.content,
                                      ts: message.timestamp.timeIntervalSince1970,
                                      images: message.imageDataURLs.isEmpty ? nil : message.imageDataURLs)
        store.appendRecord(record, to: conversationId)
        updateIndexMeta()
    }

    private func updateIndexMeta() {
        var sessions = store.loadIndex()
        let count = persistedMessages.count
        if let existing = sessions.first(where: { $0.id == conversationId }) {
            var meta = existing
            meta.lastActiveAt = Date().timeIntervalSince1970
            meta.messageCount = count
            meta.model = conversationModel
            sessions = ConversationStore.upsert(meta, into: sessions)
        } else {
            let title = ConversationStore.deriveTitle(
                from: chatMessages.first(where: { $0.role == .user })?.content ?? "")
            let meta = SessionMeta(id: conversationId,
                                   title: title,
                                   startedAt: conversationStartedAt.timeIntervalSince1970,
                                   lastActiveAt: Date().timeIntervalSince1970,
                                   messageCount: count,
                                   model: conversationModel)
            sessions = ConversationStore.upsert(meta, into: sessions)
        }
        store.saveIndex(sessions)
    }

    /// Rewrite the whole transcript from the current in-memory thread (used after
    /// dropping a retried partial so the persisted copy stays consistent).
    private func rewritePersistedTranscript() {
        let records = persistedMessages.map {
            TranscriptRecord(role: $0.role.rawValue,
                             content: $0.content,
                             ts: $0.timestamp.timeIntervalSince1970,
                             images: $0.imageDataURLs.isEmpty ? nil : $0.imageDataURLs)
        }
        store.rewriteTranscript(id: conversationId, records: records)
        updateIndexMeta()
    }

    private var persistedMessages: [ChatMessage] {
        chatMessages.filter { $0.role == .user || $0.role == .assistant }
    }

    // MARK: - Lifecycle

    func reset() {
        // Called when panel is shown — keep conversation but stop any recording
        voiceEngine?.stopRecording()
        isRecording = false
        transcribedText = ""
        if state == .done || state == .error {
            state = .idle
        }
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

    /// Reset all in-memory conversation state to a fresh, unregistered
    /// conversation. Shared by New Chat and "deleted the open conversation".
    private func startBlankConversation() {
        streamTask?.cancel()
        streamingMessageId = nil
        voiceEngine?.stopRecording()
        chatMessages.removeAll()
        inputText = ""
        transcribedText = ""
        errorMessage = ""
        isRecording = false
        activeTools = []
        pendingImages = []
        state = .idle
        conversationId = UUID().uuidString
        conversationStartedAt = Date()
        conversationModel = nil
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

    /// Load a stored conversation into the thread and return to the chat view.
    func openConversation(id: String) {
        // Re-opening the conversation already shown is a no-op beyond closing.
        guard id != conversationId else { closeHistory(); return }
        guard let meta = historyEntries.first(where: { $0.id == id })?.meta
                ?? store.loadIndex().first(where: { $0.id == id }) else { return }

        startBlankConversation()
        conversationId = meta.id
        conversationStartedAt = Date(timeIntervalSince1970: meta.startedAt)
        conversationModel = meta.model

        chatMessages = store.loadTranscript(id: meta.id).map { record in
            ChatMessage(role: ChatMessage.Role(rawValue: record.role) ?? .assistant,
                        content: record.content,
                        timestamp: Date(timeIntervalSince1970: record.ts),
                        imageDataURLs: record.images ?? [])
        }

        showingHistory = false
        historyQuery = ""
        pulseInputFocus()
    }

    /// Delete a stored conversation (index entry + transcript file). If it's the
    /// one currently open, fall back to a fresh blank conversation.
    func deleteConversation(id: String) {
        store.deleteConversation(id: id)
        reloadHistory()
        if id == conversationId {
            startBlankConversation()
        }
    }

    func cleanup() {
        streamTask?.cancel()
        voiceEngine?.stopRecording()
        isRecording = false
    }
}
