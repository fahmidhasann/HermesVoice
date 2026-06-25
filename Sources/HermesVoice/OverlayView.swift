import SwiftUI
import UniformTypeIdentifiers
import HermesVoiceKit

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var settingsStore = AppSettingsStore.shared
    @State private var streamingContentLength: Int = 0
    @State private var isDropTargeted = false
    @State private var micHovering = false
    // True while the conversation is scrolled to (or near) the bottom. Autoscroll
    // follows the stream only while this holds; once the user scrolls up to read,
    // it suspends so programmatic scrollTo doesn't fight the manual scroll. The
    // value comes from `PinnedToBottomTracker`, which observes the scroll's own
    // geometry outside the content layout pass (see that type for why).
    @State private var isPinnedToBottom = true
    @FocusState private var inputFocused: Bool

    /// Identity of the zero-height view at the very bottom of the thread; the
    /// autoscroll target.
    private let chatBottomAnchor = "chatBottomAnchor"

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.showingHistory {
                HistoryView(viewModel: viewModel)
            } else {
                chatContent
            }
        }
        // Fixed window: fill the panel's constant frame exactly. Content no longer
        // drives window height (that coupling caused resize-jitter); the
        // conversation/history scroll inside this fixed size instead.
        .frame(width: Theme.Layout.panelWidth, height: Theme.Layout.panelHeight)
        // Fully solid panel: an opaque warm surface so text and edges read on any
        // wallpaper, plus a crisp appearance-aware rim. The drop shadow lives on
        // the AppKit wrapper (OverlayPanel). This supersedes ADR 0001's
        // translucent-chrome clause in favour of maximum legibility.
        .background(Theme.Colors.baseTint)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
        )
        .animation(Theme.Motion.ifMotion(Theme.Motion.content), value: viewModel.isRecording)
        .onAppear {
            inputFocused = true
        }
    }

    // MARK: - Chat content

    /// The normal conversation surface (header, thread, input). Swapped out for
    /// the history list when `viewModel.showingHistory` is true.
    private var chatContent: some View {
        VStack(spacing: 0) {
            // Recording accent line
            if viewModel.isRecording {
                Rectangle()
                    .fill(Theme.Gradients.recording)
                    .frame(height: 2)
                    .transition(.opacity)
            }

            // Header
            headerView

            // Conversation thread
            conversationView

            Divider().background(Theme.Colors.divider)

            // Input area
            inputView
        }
        // Drag an image (or image file) anywhere onto the panel to attach it.
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers, _ in
            handleImageDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .strokeBorder(Theme.Colors.accent.opacity(0.7),
                                  style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Load dropped images (raw image data or image files) into pending
    /// attachments. Returns true when at least one provider could be consumed.
    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    Task { @MainActor in viewModel.attachImage(image) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let image = NSImage(contentsOf: url) else { return }
                    Task { @MainActor in viewModel.attachImage(image) }
                }
            }
        }
        return handled
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                statusView
                Spacer()
                Button(action: viewModel.newChat) {
                    Image(systemName: "square.and.pencil")
                        .font(Theme.Icon.font(Theme.Icon.sm, weight: .regular))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("New chat (⌘N)")
                .accessibilityLabel("New chat")

                Button(action: { viewModel.openHistory() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(Theme.Icon.font(Theme.Icon.sm, weight: .regular))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("History (⌘F)")
                .accessibilityLabel("Conversation history")

                Button(action: {
                    NotificationCenter.default.post(name: .hermesAutoHide, object: nil)
                }) {
                    Image(systemName: "xmark")
                        .font(Theme.Icon.font(Theme.Icon.xs, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Close (Esc)")
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Gradients.header)

            Rectangle()
                .fill(Theme.Colors.divider)
                .frame(height: 1)
        }
    }

    // MARK: - Status (pill: dot + label on a state-tinted capsule)

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: Theme.Spacing.sm) {
            statusDot
            statusLabel
        }
        .padding(.leading, Theme.Spacing.sm)
        .padding(.trailing, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs2)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(statusColor.opacity(0.18), lineWidth: 0.5)
                )
        )
        .animation(Theme.Motion.ifMotion(Theme.Motion.state), value: viewModel.state)
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.25), lineWidth: 2)
                    .scaleEffect(viewModel.state == .listening || viewModel.state == .responding ? 1.5 : 1.0)
                    .opacity(viewModel.state == .listening || viewModel.state == .responding ? 0.6 : 0)
                    .animation(
                        viewModel.state == .listening || viewModel.state == .responding
                            ? Theme.Motion.ifMotion(Theme.Motion.breathe)
                            : .default,
                        value: viewModel.state
                    )
            )
            .animation(Theme.Motion.ifMotion(Theme.Motion.state), value: viewModel.state)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .idle:          return Theme.Colors.textSecondary
        case .listening:     return Theme.Colors.recordingRed
        case .transcribing:  return Theme.Colors.warning
        case .sending:       return Theme.Colors.warning
        case .responding:    return Theme.Colors.accent
        case .done:          return Theme.Colors.success
        case .error:         return Theme.Colors.error
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        let text: String = {
            switch viewModel.state {
            case .idle:          return "Ready"
            case .listening:     return "Listening"
            case .transcribing:  return "Transcribing"
            case .sending:       return "Sending"
            case .responding:    return "Responding"
            case .done:          return "Done"
            case .error:         return viewModel.errorMessage
            }
        }()
        Text(text)
            .font(Theme.Font.status(size: 10.5))
            .tracking(0.3)
            .foregroundColor(statusColor)
            .lineLimit(viewModel.state == .error ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .animation(Theme.Motion.ifMotion(Theme.Motion.state), value: viewModel.state)
    }

    // MARK: - Conversation

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

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                // Soft amber halo + gradient disc for a warm, cozy focal point.
                Circle()
                    .fill(Theme.Colors.accentSoft)
                    .frame(width: 64, height: 64)
                    .blur(radius: 6)
                Circle()
                    .fill(Theme.Gradients.accent.opacity(0.22))
                    .overlay(Circle().strokeBorder(Theme.Colors.accent.opacity(0.22), lineWidth: 1))
                    .frame(width: 54, height: 54)

                Image(systemName: "waveform")
                    .font(Theme.Icon.font(Theme.Icon.lg, weight: .light))
                    .foregroundStyle(Theme.Gradients.accent)
            }

            Text("Click the mic or type to begin")
                .font(Theme.Font.messageEmphasized(size: 13.5))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("\(HotKeyFormatter.displayString(keyCode: settingsStore.settings.hotKeyCode, modifiers: settingsStore.settings.hotKeyModifiers)) to toggle  ·  Enter to send")
                .font(Theme.Font.hint())
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm2)
                .padding(.vertical, Theme.Spacing.xs)
                .background(
                    Capsule(style: .continuous).fill(Theme.Colors.textPrimary.opacity(0.07))
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
    }

    private var visibleChatMessages: [ChatMessage] {
        viewModel.chatMessages.filter { message in
            !(message.role == .assistant
              && message.isStreaming
              && message.content.isEmpty
              && message.imageDataURLs.isEmpty)
        }
    }

    private var responseIsActive: Bool {
        switch viewModel.state {
        case .sending, .responding:
            return true
        default:
            return viewModel.chatMessages.last?.isStreaming == true
                || viewModel.approvalRequest != nil
                || !viewModel.activeTools.isEmpty
        }
    }

    private var chatThreadView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(visibleChatMessages) { message in
                        MessageBubble(message: message)
                            .equatable()
                            .id(message.id)
                    }

                    AgentActivityLane(state: viewModel.state,
                                      isResponseActive: responseIsActive,
                                      activeTools: viewModel.activeTools,
                                      approvalRequest: viewModel.approvalRequest,
                                      errorMessage: viewModel.errorMessage) { choice in
                        viewModel.resolveApproval(choice: choice)
                    }
                    .id("agentActivityLane")

                    // Live transcription preview while listening
                    if viewModel.isRecording && !viewModel.transcribedText.isEmpty {
                        transcriptionPreview
                    }

                    // Zero-height autoscroll target. Deliberately a plain anchor and
                    // NOT backed by a GeometryReader: measuring a marker's position
                    // in a named coordinate space from inside the LazyVStack and
                    // writing the result to @State during the layout pass made the
                    // scroll/stack layout re-measure without converging, pegging the
                    // main thread (~76% CPU) until force-quit. Pinned state now comes
                    // from `PinnedToBottomTracker` below, outside the layout pass.
                    Color.clear
                        .frame(height: 1)
                        .id(chatBottomAnchor)
                }
                .animation(Theme.Motion.ifMotion(Theme.Motion.activityLane), value: viewModel.activeTools)
                .animation(Theme.Motion.ifMotion(Theme.Motion.activityLane), value: viewModel.approvalRequest)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            // Observe pinned-to-bottom from the scroll's own geometry (macOS 15+),
            // outside the content layout pass, so toggling the state can never feed
            // back into layout. macOS 14 has no such hook and simply always follows.
            .modifier(PinnedToBottomTracker(isPinned: $isPinnedToBottom))
            // A new message (incl. a fresh streaming placeholder) restarts the
            // streamed-length tracker; without this, autoscroll for the next
            // response stays gated behind the longest previous one. Only scroll
            // when the user was already near the bottom; forcing scrollTo from
            // scrollback can make SwiftUI relayout the lazy transcript without
            // converging. The scroll itself is deferred so it runs after SwiftUI
            // has committed the message insertion, instead of during the same
            // layout transaction.
            .onChange(of: viewModel.chatMessages.count) { _, _ in
                streamingContentLength = viewModel.chatMessages.last?.content.count ?? 0
                if isPinnedToBottom, viewModel.chatMessages.last != nil {
                    scrollToBottom(proxy, animated: true)
                }
            }
            // Follow the stream by tracking content length — but only while pinned,
            // so a user reading scrollback isn't yanked back to the bottom.
            .onChange(of: viewModel.chatMessages.last?.content.count ?? 0) { _, newCount in
                guard isPinnedToBottom else { return }
                guard let last = viewModel.chatMessages.last, last.isStreaming else { return }
                if newCount > streamingContentLength {
                    streamingContentLength = newCount
                    scrollToBottom(proxy, animated: false)
                }
            }
            // Switching to a (possibly mid-stream) background session resets the
            // streamed-length tracker, so the first post-switch chunk autoscrolls
            // instead of being swallowed by the previous session's length (§4.1).
            .onChange(of: viewModel.conversationId) { _, _ in
                streamingContentLength = viewModel.chatMessages.last?.content.count ?? 0
                if viewModel.chatMessages.last != nil {
                    scrollToBottom(proxy, animated: false)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(Theme.Motion.ifMotion(Theme.Motion.content)) {
                    proxy.scrollTo(chatBottomAnchor, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(chatBottomAnchor, anchor: .bottom)
            }
        }
    }

    private var transcriptionPreview: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.transcribedText)
                    .font(Theme.Font.message(size: 13.5))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .italic()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.Colors.recordingRed)
                        .frame(width: 4, height: 4)
                    Text("LISTENING")
                        .font(Theme.Font.status(size: 10))
                        .tracking(0.3)
                        .foregroundColor(Theme.Colors.recordingRed.opacity(0.75))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous)
                    .fill(Theme.Colors.recordingRed.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous)
                            .strokeBorder(Theme.Colors.recordingRed.opacity(0.18), lineWidth: 0.5)
                    )
            )
            Spacer(minLength: 40)
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !viewModel.pendingImages.isEmpty {
                pendingImagesStrip
            }
            inputRow
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .animation(Theme.Motion.ifMotion(Theme.Motion.content), value: viewModel.pendingImages)
    }

    /// Horizontal strip of staged image thumbnails (paste/drag) with remove
    /// buttons, shown above the input row before sending.
    private var pendingImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.pendingImages) { attachment in
                    PendingImageChip(image: attachment.image) {
                        viewModel.removePendingImage(id: attachment.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xxs)
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nothing to send when there's neither text nor a staged image.
    private var sendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.pendingImages.isEmpty
    }

    /// Whether the mic should be disabled (a response is in flight).
    private var micDisabled: Bool {
        viewModel.state == .sending || viewModel.state == .responding
    }

    private var micIcon: some View {
        Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
            .font(Theme.Icon.font(Theme.Icon.md, weight: .medium))
            .foregroundColor(viewModel.isRecording ? .white : Theme.Colors.textPrimary)
    }

    /// In review / auto-send modes the mic is a tap-to-toggle button; in
    /// push-to-talk it's a press-and-hold control (release sends).
    @ViewBuilder
    private var micButton: some View {
        if settingsStore.settings.voiceFlow == .pushToTalk {
            pushToTalkMic
        } else {
            Button(action: viewModel.toggleRecording) { micIcon }
                .buttonStyle(CircleButtonStyle(isActive: viewModel.isRecording))
                .disabled(micDisabled)
                .help(viewModel.isRecording ? "Stop recording" : "Start recording")
                .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
        }
    }

    /// Hold-to-record mic for push-to-talk. A `DragGesture` with zero minimum
    /// distance gives us press (start) and release (stop+send) without relying
    /// on Button's tap semantics. Styled to match `CircleButtonStyle`.
    private var pushToTalkMic: some View {
        let active = viewModel.isRecording
        return micIcon
            .frame(width: 34, height: 34)
            .background {
                if active {
                    Circle().fill(Theme.Gradients.recording)
                } else {
                    Circle().fill(micHovering ? Theme.Colors.textPrimary.opacity(0.13)
                                              : Theme.Colors.textPrimary.opacity(0.08))
                }
            }
            .overlay(Circle().strokeBorder(Theme.Colors.hairline, lineWidth: active ? 0 : 0.5))
            .shadow(color: active ? Theme.Colors.recordingRed.opacity(0.45) : .clear,
                    radius: active ? 7 : 0, x: 0, y: active ? 2 : 0)
            .scaleEffect(active ? 0.94 : 1.0)
            .opacity(micDisabled ? 0.5 : 1)
            .contentShape(Circle())
            .animation(Theme.Motion.hover, value: micHovering)
            .animation(Theme.Motion.toggle, value: active)
            .onHover { micHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !micDisabled, !viewModel.isRecording else { return }
                        viewModel.startHoldRecording()
                    }
                    .onEnded { _ in
                        guard !micDisabled else { return }
                        viewModel.endHoldRecording()
                    }
            )
            .help("Hold to talk")
            .accessibilityLabel("Push to talk — hold to record")
    }

    private var inputRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Mic button — toggle (tap) in review/auto-send, hold-to-talk in PTT.
            micButton

            // Input area
            if viewModel.isRecording {
                WaveformView(audio: viewModel.audioLevel)
                    .frame(height: 36)
                    .transition(.opacity.combined(with: .scale))
            } else {
                inputTextField
                    .transition(.opacity.combined(with: .scale))
            }

            // Retry button — appears after a failed or interrupted response.
            if viewModel.canRetry && viewModel.state != .sending && viewModel.state != .responding {
                Button(action: viewModel.retryLast) {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.Icon.font(Theme.Icon.sm, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Retry response")
                .accessibilityLabel("Retry last response")
                .transition(.opacity)
            }

            // Send button — becomes a Stop button while a response streams in
            if viewModel.state == .sending || viewModel.state == .responding {
                Button(action: viewModel.cancelStreaming) {
                    Image(systemName: "stop.fill")
                        .font(Theme.Icon.font(Theme.Icon.sm, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(SendButtonStyle(isDisabled: false))
                .help("Stop response")
                .accessibilityLabel("Stop response")
                .transition(.opacity)
            } else {
                Button(action: viewModel.sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(Theme.Icon.font(Theme.Icon.sm, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(SendButtonStyle(isDisabled: sendDisabled))
                .disabled(sendDisabled)
                .help("Send (Return)")
                .accessibilityLabel("Send message")
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.ifMotion(Theme.Motion.state), value: viewModel.state)
    }

    /// Multi-line text field with Enter-to-send.
    /// Return sends the message; Shift+Return (or Option+Return) inserts a newline.
    @ViewBuilder
    private var inputTextField: some View {
        TextField("Type a message…", text: $viewModel.inputText, axis: .vertical)
            .font(Theme.Font.message(size: 13.5))
            .foregroundColor(Theme.Colors.textPrimary)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm2)
            .focused($inputFocused)
            // Return sends; Shift/Option+Return inserts a soft line break.
            // We insert the break ourselves via the field editor: returning
            // `.ignored` does NOT reliably fall through to a newline in an
            // axis: .vertical TextField on macOS — SwiftUI consumes the key and
            // the caret never advances. (`.onSubmit` is also unreliable here.)
            //
            // Read the modifier from the key *event* (`press.modifiers`), NOT
            // `NSEvent.modifierFlags`: the latter is process-global "what's
            // physically down now" state that is unreliable for a
            // `.nonactivatingPanel` whose app isn't active. When it misreports
            // the held Shift, the bare Return reaches the field editor, whose
            // NSTextField commit behavior selects the whole field instead of
            // inserting a newline.
            .onKeyPress(keys: [.return]) { press in
                if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                    _ = insertSoftBreak()
                    return .handled
                }
                viewModel.sendMessage()
                return .handled
            }
            .onKeyPress(.escape) {
                NotificationCenter.default.post(name: .hermesAutoHide, object: nil)
                return .handled
            }
            .onChange(of: viewModel.panelShouldFocus) { _, should in
                if should { inputFocused = true }
            }
            .disabled(viewModel.state == .sending || viewModel.state == .responding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Colors.textPrimary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(inputFocused ? Theme.Colors.accent.opacity(0.55)
                                                        : Theme.Colors.hairline,
                                          lineWidth: inputFocused ? 1.5 : 0.5)
                    )
            )
            .animation(Theme.Motion.ifMotion(Theme.Motion.toggle), value: inputFocused)
            .accessibilityLabel("Message input")
    }

    /// Inserts a soft line break at the caret in the active field editor,
    /// preserving the insertion point and any selection — the standard macOS
    /// "Shift+Return" behavior in a multi-line field. Returns `false` when no
    /// field editor can be found.
    ///
    /// `NSApp.keyWindow` can be nil for the `.nonactivatingPanel`, so check the
    /// obvious focused windows first, then scan every window before giving up.
    private func insertSoftBreak() -> Bool {
        let windows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
        var seen = Set<ObjectIdentifier>()

        for window in windows where seen.insert(ObjectIdentifier(window)).inserted {
            // While editing, the field editor (an NSTextView) is usually the
            // first responder directly; but if the responder is the NSTextField
            // itself, reach its active field editor via `currentEditor()`.
            if let editor = window.firstResponder as? NSTextView {
                editor.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            if let field = window.firstResponder as? NSTextField,
               let editor = field.currentEditor() as? NSTextView {
                editor.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            if let editor = window.fieldEditor(false, for: nil) as? NSTextView {
                editor.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
        }
        return false
    }
}

// MARK: - Scroll position

/// Reports whether the scroll view is at (or near) its bottom by observing the
/// scroll's own geometry, rather than measuring a marker placed inside the
/// content. Crucially this runs *outside* the content layout pass, so toggling
/// the pinned `@State` it drives can't invalidate layout and re-enter — the
/// feedback that previously made the stack/scroll layout re-measure without
/// converging and froze the app mid-stream (~76% CPU until force-quit).
///
/// `onScrollGeometryChange` is macOS 15+. On macOS 14 the binding is left at its
/// default (`true`), i.e. autoscroll always follows the stream.
private struct PinnedToBottomTracker: ViewModifier {
    @Binding var isPinned: Bool

    /// Distance from the bottom (pt) that still counts as "pinned" — generous
    /// enough that one streamed flush can't spuriously unpin, small enough that a
    /// deliberate scroll-up does.
    private static let threshold: CGFloat = 120

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                // Remaining scrollable distance below what's visible.
                geometry.contentSize.height - geometry.visibleRect.maxY <= Self.threshold
            } action: { _, pinned in
                if isPinned != pinned { isPinned = pinned }
            }
        } else {
            content
        }
    }
}

// MARK: - Message Bubble

private struct ThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == phase ? Theme.Colors.accent : Theme.Colors.textSecondary.opacity(0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(i == phase ? 1.15 : 0.85)
                    .animation(Theme.Motion.ifMotion(Theme.Motion.toggle), value: phase)
            }
        }
        .task {
            guard !Theme.Motion.reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 380_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

private struct StreamingCursor: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.Colors.accent.opacity(pulsing ? 0.3 : 0.85))
            .frame(width: 6, height: 6)
            .animation(
                pulsing ? Theme.Motion.ifMotion(Theme.Motion.breathe) : nil,
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

struct MessageBubble: View, Equatable {
    let message: ChatMessage
    @State private var appeared = false
    @State private var isHovered = false
    @State private var showCopied = false

    /// Compared via `.equatable()` so streaming updates to one message don't
    /// re-evaluate (and re-parse the markdown of) every other bubble. Only the
    /// message matters; the `@State` vars are SwiftUI-managed and excluded.
    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.message == rhs.message
    }

    var body: some View {
        HStack(spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 48)
                bubbleContent
            } else if message.role == .assistant {
                bubbleContent
                Spacer(minLength: 48)
            } else {
                bubbleContent
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .scaleEffect(appeared ? 1 : 0.98, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
        .onAppear {
            withAnimation(Theme.Motion.ifMotion(Theme.Motion.springBubble)) {
                appeared = true
            }
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovered = hovering
            }
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.xs) {
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.sm) {
                if !message.imageDataURLs.isEmpty {
                    messageImages
                }

                if !message.content.isEmpty || message.isStreaming {
                    if message.isStreaming && message.content.isEmpty {
                        HStack(spacing: Theme.Spacing.sm) {
                            ThinkingDots()
                            Text("Thinking…")
                                .font(Theme.Font.message(size: 13))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    } else {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            messageText
                                .textSelection(.enabled)

                            if message.isStreaming {
                                StreamingCursor()
                                    .padding(.top, 4)
                            }

                            // Copy is always present (discoverable) on both user and
                            // assistant bubbles — subtle at rest, full-strength on hover,
                            // with a "Copied" checkmark confirmation.
                            if !message.isStreaming && !message.content.isEmpty {
                                Button(action: copyMessage) {
                                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                        .font(Theme.Icon.font(Theme.Icon.xs, weight: .medium))
                                        .foregroundColor(showCopied ? .green : Theme.Colors.textSecondary)
                                        .frame(width: 22, height: 22)
                                        .background(Theme.Colors.textPrimary.opacity(showCopied ? 0.08 : 0.04))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .opacity(showCopied || isHovered ? 1 : 0.4)
                                .help(showCopied ? "Copied" : "Copy message")
                                .accessibilityLabel("Copy message")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md2)
            .padding(.vertical, Theme.Spacing.sm2)
            .background(bubbleBackground)

            Text(formatTimestamp(message.timestamp))
                .font(Theme.Font.caption(size: 9.5))
                .foregroundColor(Theme.Colors.textSecondary.opacity(0.45))
                .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private func copyMessage() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
        withAnimation { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showCopied = false }
        }
    }

    @ViewBuilder
    private var messageText: some View {
        if message.role == .assistant && !message.content.isEmpty {
            // Full GitHub-flavored markdown (themed) with highlighted, copyable
            // code blocks. Renders incrementally as the response streams in.
            MarkdownMessageView(content: message.content)
        } else {
            Text(message.content)
                .font(Theme.Font.message(size: 13.5))
                .foregroundColor(message.role == .error ? .red : Theme.Colors.textPrimary)
        }
    }

    /// Decode and render this message's attached images as rounded thumbnails.
    @ViewBuilder
    private var messageImages: some View {
        let images = message.imageDataURLs.compactMap { ImageEncoder.image(fromDataURL: $0) }
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 220, alignment: message.role == .user ? .trailing : .leading)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.image))
            }
        }
    }

    /// Shared because `DateFormatter` creation costs ~ms and this runs on every
    /// bubble render. Only touched from SwiftUI body evaluation (main thread).
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func formatTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    /// Rounded surface with a role-specific gradient tint, a hairline edge, and a
    /// near-invisible drop shadow so bubbles lift gently off the panel.
    @ViewBuilder
    private var bubbleBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous)
        shape
            .fill(bubbleFill)
            .overlay(shape.strokeBorder(bubbleStroke, lineWidth: 0.5))
            .shadow(color: Theme.Elevation.restColor,
                    radius: Theme.Elevation.restRadius,
                    x: 0, y: Theme.Elevation.restY)
    }

    private var bubbleFill: AnyShapeStyle {
        switch message.role {
        case .user:      return AnyShapeStyle(Theme.Gradients.userBubble)
        case .assistant: return AnyShapeStyle(Theme.Gradients.assistantBubble)
        case .error:     return AnyShapeStyle(Theme.Colors.error.opacity(0.10))
        }
    }

    private var bubbleStroke: Color {
        switch message.role {
        case .user:      return Theme.Colors.accent.opacity(0.18)
        case .assistant: return Theme.Colors.hairline
        case .error:     return Theme.Colors.error.opacity(0.22)
        }
    }
}

// MARK: - Agent Activity Lane

private struct ActivityPulseDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.Colors.accent.opacity(pulsing ? 0.25 : 0.8))
            .frame(width: 5, height: 5)
            .animation(
                pulsing ? Theme.Motion.ifMotion(Theme.Motion.breathe) : nil,
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

private struct ApprovalSelection: Equatable {
    let runId: String
    let choice: String
}

private struct AgentActivityPresentation: Equatable {
    enum Kind: Equatable {
        case waiting
        case toolRunning
        case toolCompleted
        case approvalRequest
        case approvalPending
        case approvalResolved
    }

    enum Tone: Equatable {
        case accent
        case success
        case warning
    }

    let id: String
    let kind: Kind
    let tone: Tone
    let title: String
    let detail: String?
    let symbolName: String?
    let emoji: String?
    let activeCount: Int
    let approval: RunApprovalRequest?
    let pendingChoice: String?

    var showsPulse: Bool {
        kind == .waiting || kind == .toolRunning || kind == .approvalPending
    }

    var extraCount: Int {
        max(activeCount - 1, 0)
    }

    var accessibilityLabel: String {
        if let detail, !detail.isEmpty {
            return "\(title), \(detail)"
        }
        return title
    }
}

private struct AgentActivityTransitionModifier: ViewModifier {
    let opacity: Double
    let offset: CGFloat
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
            .scaleEffect(scale, anchor: .topLeading)
            .blur(radius: Theme.Motion.reduceMotion ? 0 : blur)
    }
}

private extension AnyTransition {
    static var agentActivity: AnyTransition {
        .modifier(
            active: AgentActivityTransitionModifier(opacity: 0,
                                                    offset: Theme.Motion.activityLift,
                                                    scale: Theme.Motion.activityScale,
                                                    blur: Theme.Motion.activityBlurRadius),
            identity: AgentActivityTransitionModifier(opacity: 1,
                                                      offset: 0,
                                                      scale: 1,
                                                      blur: 0)
        )
    }

    static var agentActivitySwap: AnyTransition {
        .modifier(
            active: AgentActivityTransitionModifier(opacity: 0,
                                                    offset: Theme.Spacing.xs,
                                                    scale: Theme.Motion.activityScale,
                                                    blur: Theme.Motion.activityBlurRadius),
            identity: AgentActivityTransitionModifier(opacity: 1,
                                                      offset: 0,
                                                      scale: 1,
                                                      blur: 0)
        )
    }
}

/// One stable surface for transient agent state. Tool progress, approval, and
/// generic waiting copy all swap inside this lane instead of inserting separate
/// rows that churn the chat layout.
private struct AgentActivityLane: View {
    let state: OverlayState
    let isResponseActive: Bool
    let activeTools: [ToolActivity]
    let approvalRequest: RunApprovalRequest?
    let errorMessage: String
    let onChoice: (String) -> Void

    @State private var waitingPhraseIndex = 0
    @State private var pendingApproval: ApprovalSelection?
    @State private var resolvedApproval: ApprovalSelection?
    @State private var clearResolvedTask: Task<Void, Never>?

    private static let waitingPhrases = [
        "Thinking…",
        "Working through it…",
        "Preparing a response…"
    ]

    var body: some View {
        Group {
            if let presentation {
                laneContent(presentation)
                    .transition(.agentActivity)
            }
        }
        .animation(Theme.Motion.ifMotion(Theme.Motion.activityLane), value: presentation?.id)
        .task(id: presentation?.kind == .waiting) {
            guard presentation?.kind == .waiting, !Theme.Motion.reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Theme.Motion.activityWaitingPhraseInterval)
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(Theme.Motion.ifMotion(Theme.Motion.activitySwap)) {
                        waitingPhraseIndex = (waitingPhraseIndex + 1) % Self.waitingPhrases.count
                    }
                }
            }
        }
        .onChange(of: approvalRequest) { oldValue, newValue in
            handleApprovalChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: errorMessage) { _, newValue in
            guard !newValue.isEmpty, pendingApproval != nil else { return }
            withAnimation(Theme.Motion.ifMotion(Theme.Motion.activityLane)) {
                pendingApproval = nil
            }
        }
        .onDisappear {
            clearResolvedTask?.cancel()
        }
    }

    private var presentation: AgentActivityPresentation? {
        if let approvalRequest {
            if let pendingApproval, pendingApproval.runId == approvalRequest.runId {
                return AgentActivityPresentation(
                    id: "approval-pending-\(approvalRequest.runId)-\(pendingApproval.choice)",
                    kind: .approvalPending,
                    tone: .warning,
                    title: "Sending approval…",
                    detail: choiceResultTitle(pendingApproval.choice),
                    symbolName: "clock",
                    emoji: nil,
                    activeCount: 1,
                    approval: approvalRequest,
                    pendingChoice: pendingApproval.choice
                )
            }

            return AgentActivityPresentation(
                id: "approval-request-\(approvalRequest.runId)",
                kind: .approvalRequest,
                tone: .warning,
                title: approvalRequest.description,
                detail: "Approval required",
                symbolName: "exclamationmark.triangle.fill",
                emoji: nil,
                activeCount: 1,
                approval: approvalRequest,
                pendingChoice: nil
            )
        }

        if let resolvedApproval {
            return AgentActivityPresentation(
                id: "approval-resolved-\(resolvedApproval.runId)-\(resolvedApproval.choice)",
                kind: .approvalResolved,
                tone: resolvedApproval.choice == "deny" ? .warning : .success,
                title: choiceResultTitle(resolvedApproval.choice),
                detail: "Approval answered",
                symbolName: resolvedApproval.choice == "deny" ? "xmark" : "checkmark",
                emoji: nil,
                activeCount: 1,
                approval: nil,
                pendingChoice: nil
            )
        }

        if let running = activeTools.last(where: { $0.status == .running }) {
            let label = toolLabel(running)
            return AgentActivityPresentation(
                id: "tool-running-\(toolIdentity(running))-\(activeTools.count)",
                kind: .toolRunning,
                tone: .accent,
                title: "Hermes is using \(label)…",
                detail: nil,
                symbolName: running.emoji == nil ? "wrench.and.screwdriver" : nil,
                emoji: running.emoji,
                activeCount: activeTools.count,
                approval: nil,
                pendingChoice: nil
            )
        }

        if let completed = activeTools.last(where: { $0.status == .completed }) {
            let label = toolLabel(completed)
            return AgentActivityPresentation(
                id: "tool-completed-\(toolIdentity(completed))-\(activeTools.count)",
                kind: .toolCompleted,
                tone: .success,
                title: "\(label) done",
                detail: nil,
                symbolName: "checkmark",
                emoji: nil,
                activeCount: activeTools.count,
                approval: nil,
                pendingChoice: nil
            )
        }

        guard isResponseActive else { return nil }
        let phrase = Self.waitingPhrases[waitingPhraseIndex]
        return AgentActivityPresentation(
            id: "waiting-\(waitingPhraseIndex)-\(state)",
            kind: .waiting,
            tone: .accent,
            title: phrase,
            detail: nil,
            symbolName: "sparkles",
            emoji: nil,
            activeCount: 1,
            approval: nil,
            pendingChoice: nil
        )
    }

    @ViewBuilder
    private func laneContent(_ presentation: AgentActivityPresentation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                activityIcon(presentation)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(presentation.title)
                        .font(Theme.Font.messageEmphasized(size: 12))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    if let detail = presentation.detail {
                        Text(detail)
                            .font(Theme.Font.caption(size: 10))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .id("activity-copy-\(presentation.id)")
                .transition(.agentActivitySwap)

                if presentation.extraCount > 0 {
                    Text("+\(presentation.extraCount)")
                        .font(Theme.Font.caption(size: 9.5))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.Colors.textPrimary.opacity(0.06))
                        )
                        .accessibilityHidden(true)
                }

                if presentation.showsPulse {
                    ActivityPulseDot()
                }

                Spacer(minLength: Theme.Spacing.sm)
            }

            if let approval = presentation.approval {
                approvalDetails(approval, pendingChoice: presentation.pendingChoice)
                    .transition(.agentActivity)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(laneBackground(presentation))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private func activityIcon(_ presentation: AgentActivityPresentation) -> some View {
        if let emoji = presentation.emoji {
            Text(emoji)
                .font(Theme.Icon.font(Theme.Icon.sm))
                .frame(width: Theme.Spacing.lg, height: Theme.Spacing.lg)
        } else if let symbolName = presentation.symbolName {
            Image(systemName: symbolName)
                .font(Theme.Icon.font(Theme.Icon.sm, weight: .semibold))
                .foregroundColor(toneColor(presentation.tone))
                .frame(width: Theme.Spacing.lg, height: Theme.Spacing.lg)
        }
    }

    @ViewBuilder
    private func approvalDetails(_ approval: RunApprovalRequest, pendingChoice: String?) -> some View {
        let preview = commandPreview(for: approval)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !preview.isEmpty {
                Text(preview)
                    .font(Theme.Font.code(size: 11.5))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Theme.Colors.textPrimary.opacity(0.05))
                    )
            }

            if pendingChoice != nil {
                HStack(spacing: Theme.Spacing.xs2) {
                    ActivityPulseDot()
                    Text("Submitting decision…")
                        .font(Theme.Font.message(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer(minLength: Theme.Spacing.sm)
                }
                .transition(.agentActivitySwap)
            } else {
                HStack(spacing: Theme.Spacing.xs2) {
                    ForEach(visibleChoices(for: approval), id: \.self) { choice in
                        Button(action: { choose(choice, for: approval) }) {
                            Label(choiceLabel(choice), systemImage: choiceIcon(choice))
                        }
                        .buttonStyle(ApprovalChoiceButtonStyle(tone: choiceTone(choice)))
                        .help(choiceHelp(choice))
                        .accessibilityLabel(choiceLabel(choice))
                    }
                }
                .transition(.agentActivitySwap)
            }
        }
    }

    private func laneBackground(_ presentation: AgentActivityPresentation) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        return shape
            .fill(surfaceFill(presentation.tone))
            .overlay(shape.strokeBorder(surfaceStroke(presentation.tone), lineWidth: 0.5))
            .shadow(color: Theme.Elevation.restColor,
                    radius: Theme.Elevation.restRadius,
                    x: 0,
                    y: Theme.Elevation.restY)
    }

    private func choose(_ choice: String, for approval: RunApprovalRequest) {
        let selection = ApprovalSelection(runId: approval.runId, choice: choice)
        withAnimation(Theme.Motion.ifMotion(Theme.Motion.activityLane)) {
            pendingApproval = selection
        }
        onChoice(choice)
    }

    private func handleApprovalChange(oldValue: RunApprovalRequest?, newValue: RunApprovalRequest?) {
        if let newValue {
            if pendingApproval?.runId != newValue.runId {
                pendingApproval = nil
            }
            if resolvedApproval?.runId != newValue.runId {
                resolvedApproval = nil
            }
            return
        }

        guard let oldValue,
              let pendingApproval,
              pendingApproval.runId == oldValue.runId else { return }

        withAnimation(Theme.Motion.ifMotion(Theme.Motion.activityLane)) {
            self.pendingApproval = nil
            resolvedApproval = pendingApproval
        }
        scheduleResolvedClear(for: pendingApproval)
    }

    private func scheduleResolvedClear(for selection: ApprovalSelection) {
        clearResolvedTask?.cancel()
        clearResolvedTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Theme.Motion.activityResolutionHold)
            if Task.isCancelled { return }
            withAnimation(Theme.Motion.ifMotion(Theme.Motion.activityLane)) {
                if resolvedApproval == selection {
                    resolvedApproval = nil
                }
            }
        }
    }

    private func toolLabel(_ tool: ToolActivity) -> String {
        if let label = tool.label, !label.isEmpty { return label }
        return tool.tool
    }

    private func toolIdentity(_ tool: ToolActivity) -> String {
        tool.toolCallId ?? tool.tool
    }

    private func visibleChoices(for approval: RunApprovalRequest) -> [String] {
        approval.choices.filter { approval.allowPermanent || $0 != "always" }
    }

    private func commandPreview(for approval: RunApprovalRequest) -> String {
        let trimmed = approval.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 420 else { return trimmed }
        return String(trimmed.prefix(420)) + "..."
    }

    private func toneColor(_ tone: AgentActivityPresentation.Tone) -> Color {
        switch tone {
        case .accent: return Theme.Colors.accent
        case .success: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        }
    }

    private func surfaceFill(_ tone: AgentActivityPresentation.Tone) -> Color {
        switch tone {
        case .accent: return Theme.Colors.accentSoft
        case .success: return Theme.Colors.success.opacity(0.09)
        case .warning: return Theme.Colors.warning.opacity(0.10)
        }
    }

    private func surfaceStroke(_ tone: AgentActivityPresentation.Tone) -> Color {
        switch tone {
        case .accent: return Theme.Colors.accent.opacity(0.15)
        case .success: return Theme.Colors.success.opacity(0.22)
        case .warning: return Theme.Colors.warning.opacity(0.24)
        }
    }

    private func choiceLabel(_ choice: String) -> String {
        switch choice {
        case "once": return "Allow Once"
        case "session": return "Session"
        case "always": return "Always"
        case "deny": return "Deny"
        default: return choice.capitalized
        }
    }

    private func choiceResultTitle(_ choice: String) -> String {
        switch choice {
        case "once": return "Allowed once"
        case "session": return "Allowed for session"
        case "always": return "Always allowed"
        case "deny": return "Denied"
        default: return choiceLabel(choice)
        }
    }

    private func choiceIcon(_ choice: String) -> String {
        switch choice {
        case "deny": return "xmark"
        case "always": return "checkmark.seal"
        default: return "checkmark"
        }
    }

    private func choiceHelp(_ choice: String) -> String {
        switch choice {
        case "once": return "Approve this execution"
        case "session": return "Approve matching executions for this session"
        case "always": return "Approve matching executions permanently"
        case "deny": return "Deny this execution"
        default: return choiceLabel(choice)
        }
    }

    private func choiceTone(_ choice: String) -> ApprovalChoiceButtonStyle.Tone {
        choice == "deny" ? .destructive : .accent
    }
}

struct ApprovalChoiceButtonStyle: ButtonStyle {
    enum Tone {
        case accent
        case destructive
    }

    @State private var isHovered = false
    let tone: Tone

    private var foreground: Color {
        tone == .destructive ? Theme.Colors.error : Theme.Colors.accent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button(size: 11.5))
            .labelStyle(.titleAndIcon)
            .foregroundColor(foreground)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.sm2)
            .padding(.vertical, Theme.Spacing.xs2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(foreground.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.13 : 0.09)))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .strokeBorder(foreground.opacity(isHovered ? 0.28 : 0.18), lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.ifMotion(Theme.Motion.hover), value: isHovered)
            .animation(Theme.Motion.ifMotion(Theme.Motion.press), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Pending Image Chip

/// A staged image thumbnail shown above the input with a remove button.
struct PendingImageChip: View {
    let image: NSImage
    let onRemove: () -> Void

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.image))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.image)
                    .stroke(Theme.Colors.divider, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Icon.font(Theme.Icon.md))
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(Theme.Spacing.xxs)
                .help("Remove image")
                .accessibilityLabel("Remove image")
            }
    }
}
