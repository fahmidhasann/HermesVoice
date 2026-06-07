import Foundation
import Combine
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

    init(role: Role,
         content: String,
         isStreaming: Bool = false,
         isIncomplete: Bool = false,
         timestamp: Date = Date(),
         id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.isIncomplete = isIncomplete
        self.timestamp = timestamp
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

    /// Local id of the conversation currently shown. Stable for the life of the
    /// conversation; the server derives its own session id from the first message.
    private(set) var conversationId: String
    private var conversationStartedAt: Date
    private var conversationModel: String?

    private let maxAttempts = 3

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
            Task { @MainActor in
                guard let self else { return }
                self.transcribedText = text
                self.isRecording = false
                self.state = .transcribing
                self.voiceEngine?.stopRecording()
                // Auto-send on silence
                self.sendToHermes(text: text)
            }
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
                        timestamp: Date(timeIntervalSince1970: record.ts))
        }
    }

    // MARK: - Voice

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
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
        engine.startRecording()
    }

    private func stopRecording() {
        isRecording = false
        voiceEngine?.stopRecording()
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            sendToHermes(text: text)
        } else if state == .listening {
            state = .idle
        }
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sendToHermes(text: text)
    }

    private func sendToHermes(text: String) {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        guard state != .sending, state != .responding else { return }

        if isRecording {
            isRecording = false
            voiceEngine?.stopRecording()
        }
        transcribedText = ""
        errorMessage = ""

        registerConversationIfNeeded(firstUserText: messageText)
        let userMessage = ChatMessage(role: .user, content: messageText)
        chatMessages.append(userMessage)
        persist(userMessage)

        generateResponse()
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
            .map { (role: $0.role.rawValue, content: $0.content) }

        chatMessages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))
        let assistantIndex = chatMessages.count - 1
        activeTools = []

        state = .sending
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runStream(messages: messages, assistantIndex: assistantIndex)
        }
    }

    private func runStream(messages: [(role: String, content: String)], assistantIndex: Int) async {
        var attempt = 0
        while true {
            attempt += 1
            var receivedContent = chatMessages.indices.contains(assistantIndex)
                ? !chatMessages[assistantIndex].content.isEmpty
                : false
            do {
                state = .responding
                if chatMessages.indices.contains(assistantIndex) {
                    chatMessages[assistantIndex].isIncomplete = false
                }

                let stream = try await apiClient.streamCompletion(messages: messages)
                connectionState = .online

                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .text(let chunk):
                        receivedContent = true
                        if chatMessages.indices.contains(assistantIndex) {
                            chatMessages[assistantIndex].content += chunk
                        }
                    case .tool(let activity):
                        applyToolActivity(activity)
                    }
                }

                finishAssistant(at: assistantIndex)
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

                handleStreamFailure(apiError, assistantIndex: assistantIndex, hadContent: receivedContent)
                return
            }
        }
    }

    /// Finalize a fully-streamed assistant message: stop the spinner and persist
    /// it, or drop an empty placeholder if nothing arrived.
    private func finishAssistant(at index: Int) {
        guard chatMessages.indices.contains(index) else { return }
        activeTools = []
        chatMessages[index].isStreaming = false
        chatMessages[index].isIncomplete = false
        if chatMessages[index].content.isEmpty {
            chatMessages.remove(at: index)
        } else {
            persist(chatMessages[index])
        }
    }

    private func handleStreamFailure(_ error: HermesAPIError, assistantIndex: Int, hadContent: Bool) {
        activeTools = []
        if error.kind == .offline { connectionState = .offline }

        if hadContent,
           chatMessages.indices.contains(assistantIndex),
           !chatMessages[assistantIndex].content.isEmpty {
            // Keep the partial response, mark it incomplete, and offer a retry.
            chatMessages[assistantIndex].isStreaming = false
            chatMessages[assistantIndex].isIncomplete = true
            persist(chatMessages[assistantIndex])
        } else if chatMessages.indices.contains(assistantIndex),
                  chatMessages[assistantIndex].role == .assistant,
                  chatMessages[assistantIndex].content.isEmpty {
            // Nothing useful arrived — drop the empty placeholder.
            chatMessages.remove(at: assistantIndex)
        }

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
        if let lastIndex = chatMessages.indices.last,
           chatMessages[lastIndex].isStreaming {
            chatMessages[lastIndex].isStreaming = false
            if chatMessages[lastIndex].content.isEmpty {
                // Drop an empty assistant placeholder so the thread isn't blank.
                chatMessages.remove(at: lastIndex)
            } else {
                chatMessages[lastIndex].isIncomplete = true
                persist(chatMessages[lastIndex])
            }
        }
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
                                      ts: message.timestamp.timeIntervalSince1970)
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
                             ts: $0.timestamp.timeIntervalSince1970)
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
        voiceEngine?.stopRecording()
        chatMessages.removeAll()
        inputText = ""
        transcribedText = ""
        errorMessage = ""
        isRecording = false
        activeTools = []
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
                        timestamp: Date(timeIntervalSince1970: record.ts))
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
