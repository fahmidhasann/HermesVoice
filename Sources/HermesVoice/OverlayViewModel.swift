import Foundation
import Combine

enum OverlayState: Equatable {
    case idle
    case listening
    case transcribing
    case sending
    case responding
    case done
    case error
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var content: String
    var isStreaming: Bool = false
    let timestamp = Date()

    enum Role: String {
        case user
        case assistant
        case error
    }
}

@MainActor
class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .idle
    @Published var chatMessages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var errorMessage: String = ""
    @Published var isRecording: Bool = false
    @Published var transcribedText: String = ""
    @Published var panelShouldFocus: Bool = false
    @Published var audioLevel: CGFloat = 0.1
    
    private var voiceEngine: VoiceEngine?
    private let apiClient = HermesAPIClient()
    private var streamTask: Task<Void, Never>?
    
    init() {
        voiceEngine = VoiceEngine()
        voiceEngine?.onPartialResult = { [weak self] text in
            Task { @MainActor in self?.transcribedText = text }
        }
        voiceEngine?.onFinalResult = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.transcribedText = text
                self.isRecording = false
                self.state = .transcribing
                self.voiceEngine?.stopRecording()
                // Auto-send on silence
                self.sendToHermes(text: text)
            }
        }
        voiceEngine?.onError = { [weak self] error in
            Task { @MainActor in
                self?.state = .error
                self?.errorMessage = error
                self?.isRecording = false
            }
        }
        voiceEngine?.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
    }

    // MARK: - Voice

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let engine = voiceEngine, engine.isAvailable else {
            state = .error
            errorMessage = "Speech recognition unavailable"
            return
        }
        transcribedText = ""
        errorMessage = ""
        isRecording = true
        state = .listening
        engine.startRecording()
    }

    private func stopRecording() {
        isRecording = false
        voiceEngine?.stopRecording()
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            sendToHermes(text: text)
        } else if state == .listening {
            state = .idle
        }
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sendToHermes(text: text)
    }

    private func sendToHermes(text: String) {
        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        guard state != .sending, state != .responding else { return }

        if isRecording {
            isRecording = false
            voiceEngine?.stopRecording()
        }
        transcribedText = ""
        errorMessage = ""

        chatMessages.append(ChatMessage(role: .user, content: messageText))
        chatMessages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))
        let assistantIndex = chatMessages.count - 1

        let history = chatMessages.dropLast(2).map { msg in
            (role: msg.role.rawValue, content: msg.content)
        }

        state = .sending
        streamTask?.cancel()

        streamTask = Task {
            do {
                state = .responding
                let stream = try await apiClient.sendMessage(messageText, history: history)
                for await chunk in stream {
                    if Task.isCancelled { return }
                    chatMessages[assistantIndex].content += chunk
                }
                chatMessages[assistantIndex].isStreaming = false
                // Brief "done" state then return to idle for next message
                state = .done
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                if state == .done { state = .idle }
            } catch {
                if !Task.isCancelled {
                    chatMessages.remove(at: assistantIndex)
                    state = .error
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Cancels an in-flight streamed response, keeping whatever text has
    /// already arrived, and returns to idle.
    func cancelStreaming() {
        guard state == .sending || state == .responding else { return }
        streamTask?.cancel()
        streamTask = nil
        if let lastIndex = chatMessages.indices.last,
           chatMessages[lastIndex].isStreaming {
            chatMessages[lastIndex].isStreaming = false
            // Drop an empty assistant placeholder so the thread isn't left blank.
            if chatMessages[lastIndex].content.isEmpty {
                chatMessages.remove(at: lastIndex)
            }
        }
        state = .idle
    }

    // MARK: - Lifecycle

    func reset() {
        // Called when panel is shown — keep conversation but stop any recording
        voiceEngine?.stopRecording()
        isRecording = false
        transcribedText = ""
        if state == .done || state == .error {
            state = .idle
        }
        // Trigger focus on next render
        panelShouldFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.panelShouldFocus = false
        }
    }

    func clearConversation() {
        streamTask?.cancel()
        voiceEngine?.stopRecording()
        chatMessages.removeAll()
        inputText = ""
        transcribedText = ""
        errorMessage = ""
        isRecording = false
        state = .idle
    }

    func cleanup() {
        streamTask?.cancel()
        voiceEngine?.stopRecording()
        isRecording = false
    }
}
