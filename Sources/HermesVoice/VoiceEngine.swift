import Foundation
import Speech
import AVFoundation
import HermesVoiceKit

class VoiceEngine: ObservableObject {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((CGFloat) -> Void)?

    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private var lastResultTime: Date = Date()
    /// Silence-before-stop window; refreshed from Settings ▸ Voice on each start.
    private var silenceThreshold: TimeInterval = 1.5
    /// Recognition locale identifier currently backing `speechRecognizer` ("" =
    /// system locale). Tracked so we only rebuild the recognizer when it changes.
    private var currentLanguage: String = ""

    private var isRecording = false
    private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var isAvailable: Bool {
        return speechRecognizer?.isAvailable ?? false
    }

    /// Apply the latest Voice settings (silence timeout + recognition locale).
    /// Rebuilding the recognizer is cheap and only happens when the locale id
    /// actually changes.
    private func applyVoiceSettings() {
        let settings = AppSettingsStore.loadCurrent()
        silenceThreshold = max(0.3, settings.silenceTimeout)
        let language = settings.recognitionLanguage
        guard language != currentLanguage else { return }
        currentLanguage = language
        if language.isEmpty {
            speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
                ?? SFSpeechRecognizer(locale: Locale.current)
        }
    }

    init() {
        requestAuthorization()
    }

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            self?.authorizationStatus = status
            if status != .authorized {
                DispatchQueue.main.async {
                    self?.onError?("Speech recognition not authorized. Status: \(status.rawValue)")
                }
            }
        }

        // Request microphone access
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if !granted {
                DispatchQueue.main.async {
                    self?.onError?("Microphone access denied.")
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard authorizationStatus == .authorized else {
            onError?("Speech recognition not authorized.")
            return
        }

        // Pick up the latest silence timeout / recognition language.
        applyVoiceSettings()

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            onError?("Failed to create audio engine.")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            onError?("Failed to create recognition request.")
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Audio metering
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            
            var sum: Float = 0
            for i in 0..<frames {
                sum += channelData[i] * channelData[i]
            }
            
            let rms = sqrt(sum / Float(frames))
            let db = 20 * log10(max(rms, 0.0001))
            
            // Normalize to 0-1 range (assuming -50dB to 0dB range)
            let normalizedLevel = max(0, min(1, (db + 50) / 50))
            
            DispatchQueue.main.async {
                self?.onAudioLevel?(CGFloat(normalizedLevel))
            }
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isRecording = true
            lastResultTime = Date()
            startSilenceDetection()
        } catch {
            onError?("Audio engine failed to start: \(error.localizedDescription)")
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.lastResultTime = Date()

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onFinalResult?(text)
                    }
                    self.stopRecording()
                } else {
                    DispatchQueue.main.async {
                        self.onPartialResult?(text)
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Ignore cancellation errors (code 216 = cancelled, code 1 = no speech detected)
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 1) {
                    return
                }
                DispatchQueue.main.async {
                    self.onError?("Recognition error: \(error.localizedDescription)")
                }
                self.stopRecording()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine = nil
    }

    private func startSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else {
                self?.silenceTimer?.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(self.lastResultTime)
            if elapsed >= self.silenceThreshold {
                // Silence detected — stop recording but don't auto-send
                DispatchQueue.main.async {
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = nil
                    self.recognitionRequest?.endAudio()
                }
            }
        }
    }
}
