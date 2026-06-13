import Foundation
import Combine
import HermesVoiceKit

/// Registry of live `ChatSession`s plus the process-wide App Nap assertion.
///
/// Owned by the `OverlayViewModel` facade (which is itself a forever-singleton
/// owned by `AppDelegate`), so the sessions it holds — and the activity
/// assertion — survive panel hide, focus loss, and new-chat/switch. This is what
/// lets a started stream keep running in the background instead of being
/// cancelled by the UI.
///
/// A session is registered when created and removed when it's torn down
/// (delete, or switched away while not worth keeping resident). Streaming
/// sessions are never removed underneath a live stream.
@MainActor
final class SessionManager: ObservableObject {
    /// Live sessions keyed off their immutable `conversationId`.
    private(set) var sessions: [String: ChatSession] = [:]

    /// True while at least one registered session is streaming (foreground or
    /// background). Published so the menu-bar status item can animate while a
    /// background stream runs with the panel hidden (§4.8). The in-panel pill
    /// stays foreground-only and is unaffected.
    @Published private(set) var isAnyStreaming = false

    /// Set of conversation IDs that are currently streaming. Published so the
    /// history list can show a live indicator on background-streaming rows.
    @Published private(set) var streamingSessionIds: Set<String> = []

    /// Fires the id of a session that just finished a response. One-shot per
    /// completion (driven by `ChatSession.onFinished`), so a background finish
    /// can post an ambient cue without inferring it from a transient state.
    let didFinish = PassthroughSubject<String, Never>()

    /// Ref-counts how many sessions are streaming so the OS activity token is
    /// acquired exactly once (0→1) and released exactly once (1→0), §4.3.
    private var activity = ActivityRefCounter()
    /// The held `ProcessInfo.beginActivity` token; nil when no stream is in flight.
    private var activityToken: NSObjectProtocol?

    /// Register a freshly created session and wire its streaming-activity and
    /// completion callbacks. Wiring here (not in the facade) means a session
    /// keeps holding the App Nap assertion — and still reports its finish —
    /// even after it drops to the background.
    func register(_ session: ChatSession) {
        sessions[session.conversationId] = session
        let id = session.conversationId
        session.onStreamingBegin = { [weak self] in self?.streamingDidBegin(id: id) }
        session.onStreamingEnd = { [weak self] in self?.streamingDidEnd(id: id) }
        session.onFinished = { [weak self] id in self?.didFinish.send(id) }
    }

    /// Look up a still-live session by id (nil if it was torn down / evicted).
    func session(for id: String) -> ChatSession? { sessions[id] }

    /// Drop a session from the registry. The caller is responsible for tearing
    /// down its stream first.
    func remove(id: String) {
        sessions[id] = nil
    }

    // MARK: - App Nap suppression (§4.3)

    /// A stream started. Acquire the OS activity token on the 0→1 transition.
    private func streamingDidBegin(id: String) {
        streamingSessionIds.insert(id)
        defer { isAnyStreaming = activity.count > 0 }
        guard activity.begin() else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Streaming a Hermes response")
    }

    /// A stream ended. Release the OS activity token on the 1→0 transition.
    private func streamingDidEnd(id: String) {
        streamingSessionIds.remove(id)
        defer { isAnyStreaming = activity.count > 0 }
        guard activity.end() else { return }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
