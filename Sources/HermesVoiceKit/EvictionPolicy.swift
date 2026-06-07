import Foundation

/// A toolchain-pure mirror of the app's `OverlayState`, so the eviction rule
/// can be unit-tested without importing the AppKit/`@MainActor` layer. The app
/// maps its `OverlayState` onto this 1:1 when consulting the policy.
public enum SessionLifecycleState: Equatable, Sendable {
    case idle
    case listening
    case transcribing
    case sending
    case responding
    case done
    case error
}

/// Decides whether a live, in-memory `ChatSession` may be evicted (dropped from
/// the session dictionary and reloaded from disk on demand) to bound memory
/// (plan §4.10).
///
/// A session is evictable only when it is fully at rest: a terminal lifecycle
/// state (`idle`/`done`/`error`), **not** streaming, and with no pending
/// partial-flush timer. A streaming session — or one with unflushed partial
/// state — is never evictable.
public enum EvictionPolicy {
    /// - Parameters:
    ///   - state: the session's current lifecycle state.
    ///   - isStreaming: whether a `streamTask` is in flight.
    ///   - hasPendingPartial: whether a debounced `.partial` write is queued.
    public static func isEvictable(state: SessionLifecycleState,
                                   isStreaming: Bool,
                                   hasPendingPartial: Bool) -> Bool {
        guard !isStreaming, !hasPendingPartial else { return false }
        switch state {
        case .idle, .done, .error:
            return true
        case .listening, .transcribing, .sending, .responding:
            return false
        }
    }
}
