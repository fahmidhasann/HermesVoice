# Implementation brief: fixed-size overlay panel (kill resize jitter)

**Status:** ready to implement. Design is locked (decisions below). This file is a
complete, self-contained spec — exact before/after edits for every site. Start a
fresh session, read this, and execute. No re-investigation needed.

---

## 0. Context (what you're touching)

HermesVoice is a macOS SwiftUI menu-bar app. The main UI is a floating, borderless
`NSPanel` (`OverlayPanel`) toggled with ⌃⇧H. It hosts an `NSHostingView` with the
SwiftUI `OverlayView`, which shows either the chat surface or, when
`viewModel.showingHistory`, the `HistoryView` — both in the *same* panel.

Today the panel **resizes its window height to fit its SwiftUI content**. That
coupling is the bug.

Relevant files (all under `Sources/HermesVoice/`):
- `Theme.swift` — design tokens incl. `Theme.Layout` height constants.
- `OverlayPanel.swift` — the `NSPanel`; holds the resize machinery (`updateHeight`).
- `OverlayView.swift` — SwiftUI root; measures content height and pushes it up.
- `HistoryView.swift` — alternate content in the same panel; same pattern.
- `AppDelegate.swift` — show/hide; calls `panel.positionPanel()` (no change needed).

Out of scope (separate windows, do **not** touch): `SettingsView.swift`,
`OnboardingView.swift`. Their `.fixedSize(...)` usages are unrelated.

---

## 1. Goal & locked decisions

The panel must be a **fixed size** and must **not** auto-resize to conversation
length. Decisions already made with the user:

1. **Fixed height = 540pt.** Width is already fixed at 540pt. So the panel is a
   constant 540×540.
2. **Top-aligned thread, vertically-centered empty state.** Messages start at the
   top and grow down; the existing scroll-to-bottom autoscroll stays. When the
   conversation is too short to fill the window, the empty-state prompt is
   centered in the open area (not stranded at the top).
3. **Window-lock only.** Remove the content→height coupling. Leave all existing
   content animations (status pill, tool rows, bubble arrival) untouched. Input
   multi-line growth (`lineLimit(1...4)`) and the pending-images strip are absorbed
   by the scroll area shrinking — the window never changes size.

---

## 2. Root cause (why it jitters)

`OverlayView` measures its natural content height each layout pass via a
`ContentHeightKey` PreferenceKey + `GeometryReader`, clamps it, and calls
`panelRef?.updateHeight(...)`. `OverlayPanel.updateHeight` responds to every change
with a **0.28s animated `setFrame`** that also shifts the window origin to keep the
top edge anchored. During streaming, content height changes many times per second
(markdown reflow, tool rows appearing/collapsing, status pill, spinner), so
animated window resizes stack on top of each other with recomputed origins → the
visible bounce. Existing rounding + `targetHeight` gating only dampens it.

Fix = sever the coupling: constant window height, content scrolls inside.

---

## 3. Exact edits

### 3a. `Theme.swift` — collapse height constants to one

Find the `struct Layout` block (around line 191). Replace the height constants.

**Before:**
```swift
    struct Layout {
        static let panelWidth: CGFloat = 540
        static let panelMinHeight: CGFloat = 220
        static let panelMaxHeight: CGFloat = 540
        /// Height the panel window is created at before SwiftUI reports the
        /// content's real height. Chosen ≥ the empty-state natural height so the
        /// first frame never clips the input row.
        static let panelInitialHeight: CGFloat = 300
        static let cornerRadius: CGFloat = 16
        static let screenTopOffset: CGFloat = 0.18

        static let shadowRadius: CGFloat = 32
        static let shadowOffsetY: CGFloat = -12
        static let shadowOpacity: CGFloat = 0.22

        // Animation durations (used by AppDelegate)
        static let appearDuration: CGFloat = 0.22
        static let disappearDuration: CGFloat = 0.16
        static let heightDuration: CGFloat = 0.28
    }
```

**After:**
```swift
    struct Layout {
        static let panelWidth: CGFloat = 540
        /// Fixed panel height. The window no longer resizes to fit content; the
        /// conversation/history scroll inside this constant frame. This severs the
        /// content→window-height coupling that caused the resize-jitter.
        static let panelHeight: CGFloat = 540
        static let cornerRadius: CGFloat = 16
        static let screenTopOffset: CGFloat = 0.18

        static let shadowRadius: CGFloat = 32
        static let shadowOffsetY: CGFloat = -12
        static let shadowOpacity: CGFloat = 0.22

        // Animation durations (used by AppDelegate)
        static let appearDuration: CGFloat = 0.22
        static let disappearDuration: CGFloat = 0.16
    }
```

Removed: `panelMinHeight`, `panelMaxHeight`, `panelInitialHeight`, `heightDuration`.
Added: `panelHeight`. (Verified by grep: those four are referenced *only* by the
machinery being deleted in 3b/3c/3d.)

### 3b. `OverlayPanel.swift` — delete the resize machinery

**(i) Remove the `targetHeight` property and its doc comment** (lines ~17–22):

Before:
```swift
    /// The height we last asked the window to animate toward. Height updates are
    /// gated against THIS rather than the live `frame.height`, because during an
    /// in-flight resize animation `frame.height` holds an intermediate value —
    /// comparing against it re-issues the same target every frame and the
    /// animation visibly restarts on itself (the resize-jitter bug).
    private var targetHeight: CGFloat = Theme.Layout.panelInitialHeight

    init(viewModel: OverlayViewModel) {
```
After:
```swift
    init(viewModel: OverlayViewModel) {
```

**(ii) Fix the two init height references** — change `panelInitialHeight` →
`panelHeight` in both `super.init(contentRect:...)` and the `wrapper` frame:

- `contentRect: NSRect(x: 0, y: 0, width: Theme.Layout.panelWidth, height: Theme.Layout.panelInitialHeight)`
  → `...height: Theme.Layout.panelHeight)`
- `let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: Theme.Layout.panelWidth, height: Theme.Layout.panelInitialHeight))`
  → `...height: Theme.Layout.panelHeight))`

**(iii) Update the hosting-view construction** — `OverlayView` no longer needs the
panel reference (see 3c-ii). Change:
```swift
        let overlayView = OverlayView(viewModel: viewModel, panelRef: self)
```
to:
```swift
        let overlayView = OverlayView(viewModel: viewModel)
```

**(iv) Delete the entire `updateHeight(_:)` method** (lines ~106–137, including its
leading blank line). The whole block to remove:
```swift

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
```
The shadow path is already set once in `init` and never needs updating now (size is
constant). `positionPanel()` is unchanged — `self.frame.height` is now a constant
540, so the 18%-from-top anchor is computed once per show. Leave `positionPanel`
and everything below (`beginShow`/`finishShow`/etc.) as-is.

### 3c. `OverlayView.swift` — stop measuring; fill the fixed frame

**(i) Delete the `ContentHeightKey` PreferenceKey** (lines ~5–12, including the
trailing blank line):
```swift
/// Carries the overlay content's measured natural height up to the panel so
/// the NSPanel can size itself to fit (preventing the input row from clipping).
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

**(ii) Remove the now-unused `panelRef`.** Delete the property (line ~21):
```swift
    weak var panelRef: OverlayPanel?
```
and simplify the initializer:
```swift
    init(viewModel: OverlayViewModel, panelRef: OverlayPanel? = nil) {
        self.viewModel = viewModel
        self.panelRef = panelRef
    }
```
→
```swift
    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
    }
```
(Keep this explicit init — don't rely on the synthesized memberwise init, to avoid
SwiftUI `@State`/`@FocusState` init subtleties.)

**(iii) Replace the body's height-driving modifiers.**

Before:
```swift
        .frame(width: Theme.Layout.panelWidth)
        // Take the content's *natural* height rather than being forced into the
        // panel's proposed height. Without this the bottom input row was being
        // clipped whenever the content was taller than the panel window.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            let clamped = min(max(height, Theme.Layout.panelMinHeight), Theme.Layout.panelMaxHeight)
            panelRef?.updateHeight(clamped)
        }
        .background(Color.clear)
        .animation(Theme.Motion.ifMotion(.easeInOut(duration: 0.2)), value: viewModel.isRecording)
        .onAppear {
            inputFocused = true
        }
```
After:
```swift
        // Fixed window: fill the panel's constant frame exactly. Content no longer
        // drives window height (that coupling caused resize-jitter); the
        // conversation/history scroll inside this fixed size instead.
        .frame(width: Theme.Layout.panelWidth, height: Theme.Layout.panelHeight)
        .background(Color.clear)
        .animation(Theme.Motion.ifMotion(.easeInOut(duration: 0.2)), value: viewModel.isRecording)
        .onAppear {
            inputFocused = true
        }
```
(NOTE: there is a *second*, unrelated `.fixedSize(horizontal: false, vertical: true)`
on the status label, ~line 239 in the original. **Leave that one** — it only governs
text wrapping. Only the root one above is removed.)

**(iv) Make `conversationView` fill the space between header and input.**

Before:
```swift
    private var conversationView: some View {
        Group {
            if viewModel.chatMessages.isEmpty {
                emptyStateView
            } else {
                chatThreadView
            }
        }
        .frame(maxHeight: Theme.Layout.panelMaxHeight - 160)
    }
```
After:
```swift
    private var conversationView: some View {
        Group {
            if viewModel.chatMessages.isEmpty {
                emptyStateView
            } else {
                chatThreadView
            }
        }
        // Fill the gap between header and input in the fixed window; the inner
        // ScrollView handles overflow. The empty state centers within this.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```
This flexible child is what lets the `chatContent` VStack expand to the proposed
540pt (header/input/dividers are intrinsic; conversationView absorbs the rest).

**(v) Center the empty state vertically.**

In `emptyStateView`, change the trailing frame:
```swift
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl + Theme.Spacing.sm)
```
→
```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.xxl + Theme.Spacing.sm)
```
(The intrinsic VStack centers within the now-infinite frame by default.)

### 3d. `HistoryView.swift` — same treatment (same panel)

**(i) Remove the root `.fixedSize`** so the VStack fills the fixed window.
In `body`, delete this line (~line 20):
```swift
        .fixedSize(horizontal: false, vertical: true)
```

**(ii) Make the list fill.** In `listView`, change (~line 130):
```swift
                .frame(maxHeight: Theme.Layout.panelMaxHeight - 150)
```
→
```swift
                .frame(maxHeight: .infinity)
```

**(iii) Make the history empty state fill/center.** In `emptyState` (~line 154):
```swift
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
```
→
```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
```

---

## 4. Final grep check (must come back clean)

After editing, none of these should remain anywhere in `Sources/`:
```
panelMinHeight   panelMaxHeight   panelInitialHeight   heightDuration
ContentHeightKey   updateHeight   targetHeight
```
Run:
```
grep -rn "panelMinHeight\|panelMaxHeight\|panelInitialHeight\|heightDuration\|ContentHeightKey\|updateHeight\|targetHeight" Sources/
```
Also confirm `panelRef` is gone:
```
grep -rn "panelRef" Sources/
```

## 5. Build / test / verify

1. `swift build` — must compile clean (watch for a leftover `panelRef` reference if
   any edit was partial).
2. `swift test` — regression. None of these tests touch the height machinery
   (PanelStateMachine tests cover phases only), so they should pass unchanged.
3. Run the app, ⌃⇧H to open the panel:
   - Stream a long response → window stays exactly 540pt, **zero** bounce.
   - New chat → empty-state prompt centered. Short chat → top-aligned thread.
   - ⌘F History → fills the window, list scrolls, no gap/clip; empty history centers.
   - Type 4+ lines / attach an image → window does **not** resize; scroll area shrinks.
4. `graphify update .` — keep the knowledge graph current (AST-only, per CLAUDE.md).

## 6. Gotchas

- Keep the status-label `.fixedSize` in `OverlayView` (3c-iv note) — only the root
  one is removed.
- The `OverlayView` initializer should stay explicit (don't delete it when removing
  `panelRef`) to avoid SwiftUI memberwise-init surprises.
- 540pt was already the previous max height, so the fixed size introduces **no new**
  off-screen risk on small displays versus today's behavior.
- Don't touch `SettingsView`/`OnboardingView` — separate windows.
