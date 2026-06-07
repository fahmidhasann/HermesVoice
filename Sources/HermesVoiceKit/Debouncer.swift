import Foundation

/// Coalesces rapid repeated calls into a single "fire" within a time window.
///
/// Key-repeat and accidental double-fires from Carbon can dispatch a single
/// keypress as 2-3 events within ~50ms. `shouldFire` returns `true` only for
/// the first call in each `interval` window, so one press = one action.
public struct Debouncer {
    public let interval: TimeInterval
    private var lastFire: Date

    public init(interval: TimeInterval, lastFire: Date = .distantPast) {
        self.interval = interval
        self.lastFire = lastFire
    }

    /// Returns `true` if enough time has elapsed since the last accepted call
    /// (and records `now` as the new reference point); `false` otherwise.
    public mutating func shouldFire(at now: Date = Date()) -> Bool {
        if now.timeIntervalSince(lastFire) < interval {
            return false
        }
        lastFire = now
        return true
    }
}
