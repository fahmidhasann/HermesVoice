import AppKit
import SwiftUI
import HermesVoiceKit

class OverlayPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var viewModel: OverlayViewModel

    /// Hard state-machine guard against double-toggle races. The transition
    /// logic lives in `PanelStateMachine` (HermesVoiceKit) so it can be
    /// unit-tested independently of AppKit.
    private var stateMachine = PanelStateMachine()

    /// Current lifecycle phase, mirrored from the state machine.
    var phase: PanelPhase { stateMachine.phase }

    /// The height we last asked the window to animate toward. Height updates are
    /// gated against THIS rather than the live `frame.height`, because during an
    /// in-flight resize animation `frame.height` holds an intermediate value —
    /// comparing against it re-issues the same target every frame and the
    /// animation visibly restarts on itself (the resize-jitter bug).
    private var targetHeight: CGFloat = Theme.Layout.panelInitialHeight

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.Layout.panelWidth, height: Theme.Layout.panelInitialHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false  // handled via layer
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Wrapper view: holds the shadow layer (masksToBounds = false so shadow is visible)
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: Theme.Layout.panelWidth, height: Theme.Layout.panelInitialHeight))
        wrapper.autoresizingMask = [.width, .height]
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = false

        // Visual effect view (rounded + clips content)
        let visualEffect = NSVisualEffectView(frame: wrapper.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Theme.Layout.cornerRadius
        visualEffect.layer?.masksToBounds = true
        // Hairline edge so the panel reads as a crisp, lifted object on both
        // light and dark wallpapers (the blur alone can dissolve into bright bg).
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        // Shadow on wrapper — visible because wrapper.masksToBounds = false.
        // Deeper + softer than before for a more grounded, premium float.
        wrapper.layer?.shadowColor = NSColor.black.cgColor
        wrapper.layer?.shadowOpacity = 0.28
        wrapper.layer?.shadowRadius = 34
        wrapper.layer?.shadowOffset = NSSize(width: 0, height: -12)
        wrapper.layer?.shadowPath = CGPath(
            roundedRect: wrapper.bounds,
            cornerWidth: Theme.Layout.cornerRadius,
            cornerHeight: Theme.Layout.cornerRadius,
            transform: nil
        )

        wrapper.addSubview(visualEffect)
        self.contentView = wrapper

        // Host SwiftUI view inside the visual effect
        let overlayView = OverlayView(viewModel: viewModel, panelRef: self)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)

        positionPanel()
    }

    func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            self.center()
            return
        }

        let screenFrame = screen.visibleFrame
        let panelWidth = Theme.Layout.panelWidth

        // Anchor the panel's TOP edge at 18% from the top of the screen,
        // regardless of the current panel height.
        let topOffset = screenFrame.height * Theme.Layout.screenTopOffset
        let x = screenFrame.midX - (panelWidth / 2)
        let y = screenFrame.maxY - topOffset - self.frame.height

        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func updateHeight(_ newHeight: CGFloat) {
        // Round to whole points so sub-pixel reflows from SwiftUI don't churn.
        let rounded = newHeight.rounded()

        // Gate against the last requested target (not the live, possibly
        // mid-animation `frame.height`). The threshold absorbs minor layout
        // noise so streaming text grows in clean steps instead of jittering.
        guard abs(rounded - targetHeight) >= 1.0 else { return }
        targetHeight = rounded

        var frame = self.frame
        // Anchor the top edge: compute the delta from the current live frame so
        // the top stays put even if a previous resize animation is still running.
        let heightDelta = rounded - frame.height
        frame.origin.y -= heightDelta
        frame.size.height = rounded

        // Keep the drop-shadow path in sync with the new size.
        let shadowBounds = NSRect(x: 0, y: 0, width: frame.width, height: rounded)
        contentView?.layer?.shadowPath = CGPath(
            roundedRect: shadowBounds,
            cornerWidth: Theme.Layout.cornerRadius,
            cornerHeight: Theme.Layout.cornerRadius,
            transform: nil
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Layout.heightDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - State-machine-guarded show / hide

    /// Returns `true` if the transition was allowed, `false` if the
    /// current phase prevents it (prevents double-toggle).
    func beginShow() -> Bool { transition { $0.beginShow() } }

    /// Called after the fade-in animation completes.
    func finishShow() { transition { $0.finishShow(); return true } }

    /// Returns `true` if the transition was allowed.
    func beginHide() -> Bool { transition { $0.beginHide() } }

    /// Called after the fade-out animation completes.
    func finishHide() { transition { $0.finishHide(); return true } }

    /// Force-reset to hidden (used in startup / error recovery).
    func forceHidden() { transition { $0.forceHidden(); return true } }

    /// Applies a state-machine mutation and logs phase changes for debugging
    /// without polluting release output.
    @discardableResult
    private func transition(_ body: (inout PanelStateMachine) -> Bool) -> Bool {
        let before = stateMachine.phase
        let result = body(&stateMachine)
        if before != stateMachine.phase {
            NSLog("HermesVoice: panel phase \(before) → \(stateMachine.phase)")
        }
        return result
    }

    // MARK: - NSWindow overrides

    override var canBecomeKey: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        // Don't auto-dismiss on focus loss — user controls dismissal
    }
}
