import Foundation

/// Tracks the overlay panel's lifecycle to prevent rapid-show/hide races
/// that can occur when Carbon delivers duplicate hotkey events.
public enum PanelPhase: Equatable, Sendable {
    case hidden
    case showing   // fade-in animation in progress
    case visible
    case hiding    // fade-out animation in progress
}

/// Hard state-machine guard against double-toggle races.
///
/// Transitions:
///   hidden  → showing    (beginShow)
///   showing → visible    (finishShow)
///   visible → hiding     (beginHide)
///   showing → hiding     (beginHide — interrupting a fade-in)
///   hiding  → hidden     (finishHide)
/// All other transitions are no-ops. This is the core guarantee that one
/// physical hotkey press produces at most one panel.
public struct PanelStateMachine {
    public private(set) var phase: PanelPhase

    public init(phase: PanelPhase = .hidden) {
        self.phase = phase
    }

    /// Returns `true` if the show transition was allowed, `false` if the
    /// current phase prevents it (prevents double-toggle).
    @discardableResult
    public mutating func beginShow() -> Bool {
        guard phase == .hidden else { return false }
        phase = .showing
        return true
    }

    /// Called after the fade-in animation completes.
    public mutating func finishShow() {
        if phase == .showing { phase = .visible }
    }

    /// Returns `true` if the hide transition was allowed.
    @discardableResult
    public mutating func beginHide() -> Bool {
        guard phase == .visible || phase == .showing else { return false }
        phase = .hiding
        return true
    }

    /// Called after the fade-out animation completes.
    public mutating func finishHide() {
        if phase == .hiding { phase = .hidden }
    }

    /// Force-reset to hidden (used in startup / error recovery).
    public mutating func forceHidden() {
        phase = .hidden
    }
}
