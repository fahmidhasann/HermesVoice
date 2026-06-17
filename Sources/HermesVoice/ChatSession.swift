import Foundation
import Combine
import HermesVoiceKit

/// Serializes read-modify-write updates to the shared `sessions.json` index.
///
/// Each session only ever upserts its **own** id, and every call runs on the
/// main actor with no suspension point between `load` and `save`, so concurrent
/// sessions can't clobber each other's metadata (§4.9). The `transform` closure
/// receives the current `SessionMeta` for the id (or `nil` if absent) and
/// returns the value to write, or `nil` to leave the index untouched.
@MainActor
final class SessionIndexWriter {
    private let store: ConversationFileStore

    init(store: ConversationFileStore) {
        self.store = store
    }

    func update(id: String, _ transform: (SessionMeta?) -> SessionMeta?) {
        let sessions = store.loadIndex()
        let existing = sessions.first(where: { $0.id == id })
        guard let meta = transform(existing) else { return }
        store.saveIndex(ConversationStore.upsert(meta, into: sessions))
    }
}

/// One chat conversation: owns its transcript, streaming task, and per-session
/// UI state, keyed off its **own immutable** `conversationId` so a late or
/// background completion always writes to the right conversation (fixes the old
/// "persist keys off mutable self.conversationId" bug). The `OverlayViewModel`
/// facade mirrors exactly one of these as the foreground session.
@MainActor
final class ChatSession: ObservableObject {
    // MARK: - Identity (immutable for the life of the conversation)

    /// Local id of this conversation. Stable for its whole life; the server
    /// derives its own session id from the first message.
    let conversationId: String
    let startedAt: Date
    var model: String?

    // MARK: - Mirrored per-session UI state

    @Published var state: OverlayState = .idle
    @Published var chatMessages: [ChatMessage] = []
    @Published var errorMessage: String = ""
    /// Tool steps currently running, surfaced for live "Hermes is using…" rows.
    @Published var activeTools: [ToolActivity] = []

    // MARK: - Collaborators (shared, stateless)

    private let apiClient: HermesAPIClient
    private let store: ConversationFileStore
    private let indexWriter: SessionIndexWriter

    private var streamTask: Task<Void, Never>?

    /// Stable id of the assistant message currently being streamed into. The
    /// positional index is invalid across the async boundary and across
    /// in-session mutations (retry removes a row), so we resolve the index fresh
    /// from this id at every access and clear it on every terminal path.
    private var streamingMessageId: UUID?

    private let maxAttempts = 3

    /// Set once this conversation is being deleted. Every disk write guards on
    /// it so a late chunk arriving after `cancel()` but before the Task observes
    /// cancellation can't resurrect a just-deleted transcript / index entry
    /// (§4.5). Race-free because everything here runs on the main actor.
    private(set) var isDeleted = false

    /// Leading-edge debounce so streamed chunks flush to the `.partial`
    /// side-file at most a few times per second instead of on every token. The
    /// write is synchronous and inline in the `.text` case, so there is no async
    /// timer to invalidate on delete — stopping the stream + the `isDeleted`
    /// guard fully cover §4.5.
    private var partialDebouncer = Debouncer(interval: 0.5)

    /// Called when a stream reveals gateway reachability. Global connection
    /// state lives on the facade, so the session reports up rather than owning it.
    var onConnectionState: ((ConnectionState) -> Void)?

    /// Called when this session's network loop starts / ends, so the
    /// `SessionManager` can ref-count the process-wide App Nap assertion (§4.3).
    /// Wired by the manager at registration and kept for the session's whole
    /// life, so a backgrounded stream still holds the assertion.
    var onStreamingBegin: (() -> Void)?
    var onStreamingEnd: (() -> Void)?

    /// Fired once with this session's id when a response finishes successfully
    /// (a non-empty assistant message was committed). Used by `SessionManager`
    /// to surface a background-completion cue — read at `finishAssistant` time
    /// rather than inferred from `state == .done`, which evaporates after the
    /// cosmetic 1.5s done→idle window (§4.8).
    var onFinished: ((String) -> Void)?

    init(conversationId: String,
         startedAt: Date,
         model: String?,
         store: ConversationFileStore,
         apiClient: HermesAPIClient,
         indexWriter: SessionIndexWriter,
         initialMessages: [ChatMessage] = []) {
        self.conversationId = conversationId
        self.startedAt = startedAt
        self.model = model
        self.store = store
        self.apiClient = apiClient
        self.indexWriter = indexWriter
        self.chatMessages = initialMessages
    }

    /// Map persisted records into thread messages. Shared by the facade's
    /// resume/open paths so every load builds messages identically.
    static func mapRecords(_ records: [TranscriptRecord]) -> [ChatMessage] {
        records.map { record in
            ChatMessage(role: ChatMessage.Role(rawValue: record.role) ?? .assistant,
                        content: record.content,
                        timestamp: Date(timeIntervalSince1970: record.ts),
                        imageDataURLs: record.images ?? [])
        }
    }

    /// True while a response is in flight; a new send is blocked until it ends.
    var isBusy: Bool { state == .sending || state == .responding }

    /// Toolchain-pure mirror of `state`, consulted by `EvictionPolicy` when the
    /// facade sweeps finished background sessions (§4.10).
    var lifecycleState: SessionLifecycleState {
        switch state {
        case .idle:         return .idle
        case .listening:    return .listening
        case .transcribing: return .transcribing
        case .sending:      return .sending
        case .responding:   return .responding
        case .done:         return .done
        case .error:        return .error
        }
    }

    /// Resolve the live index of the streaming target, fresh at each access.
    /// Returns nil if the target was removed (reset/retry/delete).
    private func streamingIndex() -> Int? {
        guard let id = streamingMessageId else { return nil }
        return chatMessages.firstIndex(where: { $0.id == id })
    }

    // MARK: - Messaging

    /// Append a user message and start generating the response. Global concerns
    /// (mic, pending images, transcription preview) are handled by the facade
    /// before this is called.
    func send(text: String, images: [ImageAttachment]) {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty || !images.isEmpty else { return }
        guard !isBusy else { return }

        errorMessage = ""
        let imageURLs = images.map { $0.dataURL }
        registerConversationIfNeeded(
            firstUserText: messageText.isEmpty ? "Image message" : messageText)
        let userMessage = ChatMessage(role: .user, content: messageText, imageDataURLs: imageURLs)
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
        guard canRetry, !isBusy else { return }
        if let lastIndex = chatMessages.indices.last,
           chatMessages[lastIndex].role == .assistant,
           chatMessages[lastIndex].isIncomplete {
            // Drop the kept partial. Clear any stale streaming target pointing at
            // it so the row removal can't be mis-resolved by a late access.
            if streamingMessageId == chatMessages[lastIndex].id { streamingMessageId = nil }
            chatMessages.remove(at: lastIndex)
            rewritePersistedTranscript()
        }
        // Drop any stale `.partial` so the upcoming stream starts clean and a
        // crash can't mis-fold a superseded partial (§4.7).
        store.clearPartial(id: conversationId)
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

        // Start from a clean slate: drop any leftover `.partial` before the new
        // placeholder, and reset the debounce window so the first chunk flushes
        // promptly (§4.7).
        store.clearPartial(id: conversationId)
        partialDebouncer = Debouncer(interval: 0.5)

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
        // Every resumption point in this task is a cancellation boundary: a
        // cancelled task must never write `state` or run `finishAssistant()`,
        // because `cancelStreaming()` already finalized this stream and a newer
        // stream may have re-pointed `streamingMessageId` at its own
        // placeholder. In particular, a cancelled `for try await` loop ends
        // *without throwing*, so falling through to `finishAssistant()` would
        // silently destroy the next response's placeholder.
        if Task.isCancelled { return }

        // Hold the App Nap assertion for the duration of the network burst only
        // (across retry backoffs too), and release it *before* the cosmetic 1.5s
        // done→idle sleep. The explicit `releaseActivity()` calls do the release
        // at the right moment; the `defer` is a safety net so the early-returns
        // (cancellation / failure) can never leak the ref-count (§4.3).
        onStreamingBegin?()
        var releasedActivity = false
        func releaseActivity() {
            guard !releasedActivity else { return }
            releasedActivity = true
            onStreamingEnd?()
        }
        defer { releaseActivity() }

        func appendStreamedText(_ text: String) {
            guard let index = streamingIndex() else { return }
            chatMessages[index].content += text
            // Best-effort durability: flush the growing text to
            // the `.partial` side-file at most ~2×/s (§4.7).
            if partialDebouncer.shouldFire() {
                writePartial(chatMessages[index].content,
                             ts: chatMessages[index].timestamp)
            }
        }

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
                onConnectionState?(.online)
                // The raw SSE stream can produce token-rate events. Drain and
                // batch that stream off the main actor so SwiftUI only sees a
                // bounded number of markdown mutations.
                let coalescedStream = StreamEventCoalescer.coalesce(stream, flushInterval: 0.08)

                for try await event in coalescedStream {
                    if Task.isCancelled { return }
                    switch event {
                    case .text(let chunk):
                        receivedContent = true
                        appendStreamedText(chunk)
                    case .tool(let activity):
                        applyToolActivity(activity)
                    }
                }

                // A cancelled stream terminates the loop without throwing —
                // bail before finalizing as if it completed.
                if Task.isCancelled { return }

                finishAssistant()
                releaseActivity() // network done — don't hold the assertion through the sleep
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
                    // `try?` swallows the sleep's CancellationError — a cancel
                    // during the backoff must end the task, not retry over the
                    // `.idle` that `cancelStreaming()` just set.
                    if Task.isCancelled { return }
                    continue
                }

                // The coalescer flushes any buffered text before throwing, so
                // a kept partial includes everything that actually arrived.
                handleStreamFailure(apiError, hadContent: receivedContent)
                return
            }
        }
    }

    /// Finalize a fully-streamed assistant message: stop the spinner and persist
    /// it, or drop an empty placeholder if nothing arrived.
    private func finishAssistant() {
        activeTools = []
        // The final record goes to `.jsonl` below; the crash-recovery side-file
        // is no longer needed (§4.7).
        store.clearPartial(id: conversationId)
        defer { streamingMessageId = nil }
        guard let index = streamingIndex() else { return }
        chatMessages[index].isStreaming = false
        chatMessages[index].isIncomplete = false
        if chatMessages[index].content.isEmpty {
            chatMessages.remove(at: index)
        } else {
            persist(chatMessages[index])
            // A real answer landed — fire the one-shot completion cue so a
            // background finish can be surfaced in the menu bar (§4.8). Guarded
            // like every other side effect so a deleted conversation can't
            // flash a completion cue for a thread that no longer exists.
            if !isDeleted { onFinished?(conversationId) }
        }
    }

    private func handleStreamFailure(_ error: HermesAPIError, hadContent: Bool) {
        activeTools = []
        // Whatever survived is committed to `.jsonl` below (kept incomplete) or
        // dropped — either way the side-file is now stale (§4.7).
        store.clearPartial(id: conversationId)
        if error.kind == .offline { onConnectionState?(.offline) }

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

    /// Row to update for `activity`. Matches on `toolCallId` when the gateway
    /// provides one; otherwise falls back to the tool name, so two concurrent
    /// id-less tools can't collide on `nil == nil` and overwrite each other.
    private func toolRowIndex(for activity: ToolActivity) -> Int? {
        if let id = activity.toolCallId {
            return activeTools.firstIndex(where: { $0.toolCallId == id })
        }
        return activeTools.firstIndex(where: { $0.toolCallId == nil && $0.tool == activity.tool })
    }

    private func applyToolActivity(_ activity: ToolActivity) {
        switch activity.status {
        case .running:
            if let index = toolRowIndex(for: activity) {
                activeTools[index] = activity
            } else {
                activeTools.append(activity)
            }
        case .completed:
            guard let index = toolRowIndex(for: activity) else { return }
            activeTools[index] = activity
            let toolCallId = activity.toolCallId
            let toolName = activity.tool
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                // Only sweep rows that are actually completed, so an id-less
                // cleanup can't wipe a still-running row for the same tool.
                self?.activeTools.removeAll { row in
                    guard row.status == .completed else { return false }
                    if let toolCallId { return row.toolCallId == toolCallId }
                    return row.toolCallId == nil && row.tool == toolName
                }
            }
        }
    }

    /// Cancels an in-flight streamed response, keeping whatever text has
    /// already arrived (marked incomplete), and returns to idle.
    func cancelStreaming() {
        guard state == .sending || state == .responding else { return }
        streamTask?.cancel()
        streamTask = nil
        activeTools = []
        // The kept partial (if any) is committed to `.jsonl` below; drop the
        // side-file (§4.7).
        store.clearPartial(id: conversationId)
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

    /// Cancel any in-flight stream. Used when the facade discards this session
    /// (new chat / open another). Phase 2 keeps the old destructive semantics;
    /// Phase 3 stops calling this on hide/switch so sessions live on.
    func teardown() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Mark this session deleted and stop its stream so no further disk write
    /// can resurrect the conversation. The caller deletes disk **after** this
    /// returns and after removing the session from the manager (ordering §4.5).
    func markDeleted() {
        isDeleted = true
        streamTask?.cancel()
        streamTask = nil
    }

    /// Flush the in-flight assistant text to the `.partial` side-file, unless
    /// the conversation is being deleted (§4.5).
    private func writePartial(_ content: String, ts: Date) {
        guard !isDeleted else { return }
        store.writePartial(id: conversationId,
                           content: content,
                           ts: ts.timeIntervalSince1970)
    }

    // MARK: - Persistence

    /// Register a brand-new conversation in the index on its first message.
    private func registerConversationIfNeeded(firstUserText: String) {
        guard !isDeleted else { return }
        indexWriter.update(id: conversationId) { [startedAt, model] existing in
            guard existing == nil else { return nil }
            return SessionMeta(id: conversationId,
                               title: ConversationStore.deriveTitle(from: firstUserText),
                               startedAt: startedAt.timeIntervalSince1970,
                               lastActiveAt: Date().timeIntervalSince1970,
                               messageCount: 0,
                               model: model)
        }
    }

    /// Append one message to the transcript and refresh the index metadata.
    private func persist(_ message: ChatMessage) {
        guard !isDeleted else { return }
        guard message.role == .user || message.role == .assistant else { return }
        let record = TranscriptRecord(role: message.role.rawValue,
                                      content: message.content,
                                      ts: message.timestamp.timeIntervalSince1970,
                                      images: message.imageDataURLs.isEmpty ? nil : message.imageDataURLs)
        store.appendRecord(record, to: conversationId)
        updateIndexMeta()
    }

    private func updateIndexMeta() {
        guard !isDeleted else { return }
        let count = persistedMessages.count
        let firstUserText = chatMessages.first(where: { $0.role == .user })?.content ?? ""
        indexWriter.update(id: conversationId) { [startedAt, model] existing in
            if var meta = existing {
                meta.lastActiveAt = Date().timeIntervalSince1970
                meta.messageCount = count
                meta.model = model
                return meta
            } else {
                return SessionMeta(id: conversationId,
                                   title: ConversationStore.deriveTitle(from: firstUserText),
                                   startedAt: startedAt.timeIntervalSince1970,
                                   lastActiveAt: Date().timeIntervalSince1970,
                                   messageCount: count,
                                   model: model)
            }
        }
    }

    /// Rewrite the whole transcript from the current in-memory thread (used after
    /// dropping a retried partial so the persisted copy stays consistent).
    private func rewritePersistedTranscript() {
        guard !isDeleted else { return }
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
}
