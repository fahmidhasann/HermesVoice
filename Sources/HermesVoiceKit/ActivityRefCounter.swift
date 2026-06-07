import Foundation

/// Ref-counts how many sessions are actively streaming so the app can hold a
/// single process-wide `ProcessInfo.beginActivity` assertion (App Nap
/// suppression) for as long as *any* stream is in flight.
///
/// The owner acquires the OS activity token when `begin()` returns `true`
/// (the count rose 0→1) and releases it when `end()` returns `true` (the count
/// fell 1→0). All other calls just adjust the count and return `false`, so the
/// token is acquired exactly once and released exactly once per streaming
/// "burst", no matter how many sessions overlap.
///
/// `end()` clamps at zero: an extra/unbalanced `end()` is a no-op rather than
/// driving the count negative, which keeps a leaked release from later
/// suppressing a legitimate acquire.
public struct ActivityRefCounter: Equatable, Sendable {
    public private(set) var count: Int

    public init(count: Int = 0) {
        self.count = max(0, count)
    }

    /// Registers a new active stream. Returns `true` only on the 0→1
    /// transition, i.e. when the caller should *acquire* the OS token.
    @discardableResult
    public mutating func begin() -> Bool {
        count += 1
        return count == 1
    }

    /// Registers that a stream ended. Returns `true` only on the 1→0
    /// transition, i.e. when the caller should *release* the OS token.
    /// Clamps at zero (an unbalanced `end()` is a no-op).
    @discardableResult
    public mutating func end() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }
}
