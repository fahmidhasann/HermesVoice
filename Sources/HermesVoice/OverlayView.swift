import SwiftUI
import UniformTypeIdentifiers
import HermesVoiceKit

/// Carries the overlay content's measured natural height up to the panel so
/// the NSPanel can size itself to fit (preventing the input row from clipping).
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var streamingContentLength: Int = 0
    @State private var isDropTargeted = false
    @FocusState private var inputFocused: Bool
    weak var panelRef: OverlayPanel?

    init(viewModel: OverlayViewModel, panelRef: OverlayPanel? = nil) {
        self.viewModel = viewModel
        self.panelRef = panelRef
    }

    var body: some View {
        Group {
            if viewModel.showingHistory {
                HistoryView(viewModel: viewModel)
            } else {
                chatContent
            }
        }
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
    }

    // MARK: - Chat content

    /// The normal conversation surface (header, thread, input). Swapped out for
    /// the history list when `viewModel.showingHistory` is true.
    private var chatContent: some View {
        VStack(spacing: 0) {
            // Recording accent line
            if viewModel.isRecording {
                Rectangle()
                    .fill(Theme.Colors.recordingRed)
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
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("New chat (⌘N)")
                .accessibilityLabel("New chat")

                Button(action: { viewModel.openHistory() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("History (⌘F)")
                .accessibilityLabel("Conversation history")

                Button(action: {
                    NotificationCenter.default.post(name: .hermesAutoHide, object: nil)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(IconButtonStyle())
                .help("Close (Esc)")
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)

            Rectangle()
                .fill(Theme.Colors.divider)
                .frame(height: 1)
        }
    }

    // MARK: - Status (dot badge style)

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: Theme.Spacing.sm) {
            statusDot
            statusLabel
        }
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
                            ? Theme.Motion.ifMotion(.easeInOut(duration: 1.2).repeatForever(autoreverses: true))
                            : .default,
                        value: viewModel.state
                    )
            )
            .animation(Theme.Motion.ifMotion(.easeInOut(duration: 0.25)), value: viewModel.state)
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
            .animation(Theme.Motion.ifMotion(.easeInOut(duration: 0.25)), value: viewModel.state)
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
        .frame(maxHeight: Theme.Layout.panelMaxHeight - 160)
    }

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.08))
                    .frame(width: 48, height: 48)

                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .ultraLight))
                    .foregroundColor(Theme.Colors.accent.opacity(0.5))
            }

            Text("Click the mic or type to begin")
                .font(Theme.Font.message(size: 13.5))
                .foregroundColor(Theme.Colors.textSecondary)

            Text("⌃⇧H to toggle  ·  Enter to send")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Theme.Colors.textSecondary.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.Colors.textPrimary.opacity(0.04))
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl + Theme.Spacing.sm)
    }

    private var chatThreadView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.chatMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    // Live tool-activity rows ("Hermes is using…") shown while a
                    // response streams; they resolve/collapse as steps complete.
                    toolActivityRows

                    // Live transcription preview while listening
                    if viewModel.isRecording && !viewModel.transcribedText.isEmpty {
                        transcriptionPreview
                    }
                }
                .animation(Theme.Motion.ifMotion(.easeOut(duration: 0.2)), value: viewModel.activeTools)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            // Scroll to new messages
            .onChange(of: viewModel.chatMessages.count) { _, _ in
                if let last = viewModel.chatMessages.last {
                    withAnimation(Theme.Motion.ifMotion(.easeOut(duration: 0.2))) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            // Scroll during streaming by tracking content length
            .onChange(of: viewModel.chatMessages.last?.content.count ?? 0) { _, newCount in
                guard let last = viewModel.chatMessages.last, last.isStreaming else { return }
                if newCount > streamingContentLength {
                    streamingContentLength = newCount
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var toolActivityRows: some View {
        ForEach(Array(viewModel.activeTools.enumerated()), id: \.offset) { _, tool in
            ToolActivityRow(tool: tool)
                .transition(.opacity.combined(with: .move(edge: .leading)))
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
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(Theme.Colors.recordingRed.opacity(0.06))
            .cornerRadius(12)
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
        .animation(Theme.Motion.ifMotion(.easeInOut(duration: 0.18)), value: viewModel.pendingImages)
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
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nothing to send when there's neither text nor a staged image.
    private var sendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
            && viewModel.pendingImages.isEmpty
    }

    private var inputRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Mic button
            Button(action: viewModel.toggleRecording) {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(viewModel.isRecording ? .white : Theme.Colors.textPrimary)
            }
            .buttonStyle(CircleButtonStyle(isActive: viewModel.isRecording))
            .disabled(viewModel.state == .sending || viewModel.state == .responding)
            .help(viewModel.isRecording ? "Stop recording" : "Start recording")
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")

            // Input area
            if viewModel.isRecording {
                WaveformView(viewModel: viewModel)
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
                        .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(SendButtonStyle(isDisabled: false))
                .help("Stop response")
                .accessibilityLabel("Stop response")
                .transition(.opacity)
            } else {
                Button(action: viewModel.sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(SendButtonStyle(isDisabled: sendDisabled))
                .disabled(sendDisabled)
                .help("Send (Return)")
                .accessibilityLabel("Send message")
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.ifMotion(.easeInOut(duration: 0.18)), value: viewModel.state)
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
            .padding(.horizontal, Theme.Spacing.md + 4)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .focused($inputFocused)
            // Return sends; Shift/Option+Return falls through to insert a newline.
            // (`.onSubmit` is unreliable for an axis: .vertical field on macOS.)
            .onKeyPress(.return) {
                if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.option) {
                    return .ignored
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
            .background(Theme.Colors.textPrimary.opacity(0.04))
            .cornerRadius(10)
            .accessibilityLabel("Message input")
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var appeared = false
    @State private var isHovered = false
    @State private var showCopied = false

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
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(Theme.Motion.ifMotion(.easeOut(duration: 0.25))) {
                appeared = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
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
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        messageText
                            .textSelection(.enabled)

                        if message.isStreaming {
                            ProgressView()
                                .scaleEffect(0.45)
                                .frame(width: 12, height: 12)
                        }

                        // Copy is always present (discoverable) on both user and
                        // assistant bubbles — subtle at rest, full-strength on hover,
                        // with a "Copied" checkmark confirmation.
                        if !message.isStreaming && !message.content.isEmpty {
                            Button(action: copyMessage) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10.5, weight: .medium))
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
            .padding(.horizontal, Theme.Spacing.md + 2)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(backgroundColor)
            .cornerRadius(12)

            Text(formatTimestamp(message.timestamp))
                .font(.system(size: 9.5))
                .foregroundColor(Theme.Colors.textSecondary.opacity(0.45))
                .padding(.horizontal, 4)
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Theme.Colors.userBubble
        case .assistant:
            return Theme.Colors.assistantBubble
        case .error:
            return Theme.Colors.error.opacity(0.08)
        }
    }
}

// MARK: - Tool Activity Row

/// Ephemeral "Hermes is using …" row rendered while a tool step is running.
/// These are not persisted in the transcript — they vanish when the step
/// completes (the view model removes completed activities).
struct ToolActivityRow: View {
    let tool: ToolActivity

    private var label: String {
        if let label = tool.label, !label.isEmpty { return label }
        return tool.tool
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(tool.emoji ?? "🔧")
                .font(.system(size: 12))

            (Text("Hermes is using ").foregroundColor(Theme.Colors.textSecondary)
             + Text(label).foregroundColor(Theme.Colors.textPrimary)
             + Text("…").foregroundColor(Theme.Colors.textSecondary))
                .font(Theme.Font.message(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 12, height: 12)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(Theme.Colors.accent.opacity(0.07))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermes is using \(label)")
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.Colors.divider, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(2)
                .help("Remove image")
                .accessibilityLabel("Remove image")
            }
    }
}
