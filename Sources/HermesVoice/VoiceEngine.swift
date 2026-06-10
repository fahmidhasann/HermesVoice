import Foundation
import Speech
import AVFoundation
import HermesVoiceKit

/// All mutable state in this class is **main-thread confined**: the facade
/// calls in on the main thread, the speech-recognizer callback hops to main
/// before touching anything, `finish()` re-dispatches itself to main, and the
/// audio tap only forwards (it captures the recognition request directly and
/// publishes levels via `DispatchQueue.main.async`). Keep it that way — the
/// previous unsynchronized cross-thread mutation could double-deliver or drop
/// transcripts and race `teardown()` against the tap.
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

    /// When false, the silence timer never auto-stops (push-to-talk holds the
    /// mic open until the caller releases it).
    private var autoStopOnSilence = true
    /// Best transcript seen so far this session, delivered verbatim on `finish()`
    /// so we never depend on the flaky on-device `isFinal` signal (bug #9).
    private var latestTranscript = ""
    /// Armed once we've heard any speech, so a pre-speech silence window can't
    /// auto-stop the recording before the user has said anything.
    private var hasReceivedSpeech = false
    /// Ensures the transcript is delivered exactly once per session.
    private var didFinish = false

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

    /// Begin capture. `autoStopOnSilence` is false for push-to-talk, where the
    /// caller holds the mic open and `finish()` is invoked on release.
    func startRecording(autoStopOnSilence: Bool = true) {
        guard !isRecording else { return }
        guard authorizationStatus == .authorized else {
            onError?("Speech recognition not authorized.")
            return
        }

        // Pick up the latest silence timeout / recognition language.
        applyVoiceSettings()

        self.autoStopOnSilence = autoStopOnSilence
        latestTranscript = ""
        hasReceivedSpeech = false
        didFinish = false

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

        // No usable input device (mic revoked in System Settings, or none
        // attached) yields a 0 Hz/0-channel format, and `installTap` with that
        // format raises an Objective-C exception — surface an error instead.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            self.audioEngine = nil
            self.recognitionRequest = nil
            onError?("No audio input device available. Check your microphone.")
            return
        }

        // Capture the request directly (not via `self`) so the render thread
        // never reads a property that `teardown()` mutates on the main thread.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [recognitionRequest, weak self] buffer, _ in
            recognitionRequest.append(buffer)

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
            // The recognizer delivers on its own queue; hop to main before
            // touching any engine state so it stays main-thread confined.
            DispatchQueue.main.async {
                guard let self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.lastResultTime = Date()
                    if !text.isEmpty {
                        self.latestTranscript = text
                        self.hasReceivedSpeech = true
                    }

                    if result.isFinal {
                        self.finish()
                    } else {
                        self.onPartialResult?(text)
                    }
                }

                if let error = error {
                    if self.didFinish { return }
                    let nsError = error as NSError
                    // Cancellation (216) and no-speech (1) are expected when we stop
                    // capture ourselves — deliver whatever transcript we have.
                    if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 1) {
                        self.finish()
                        return
                    }
                    self.onError?("Recognition error: \(error.localizedDescription)")
                    self.teardown()
                }
            }
        }
    }

    /// Stop capture and deliver the accumulated transcript exactly once. Used by
    /// the silence timer, an `isFinal` result, and the caller (manual stop /
    /// push-to-talk release).
    func finish() {
        // Funnel onto the main thread: every caller path (silence timer,
        // recognizer callback, facade) ends up here, and the once-only guard
        // below is only race-free when it always runs on one thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.finish() }
            return
        }
        guard isRecording, !didFinish else { return }
        didFinish = true
        let text = latestTranscript
        teardown()
        onFinalResult?(text)
    }

    /// Stop capture WITHOUT delivering a transcript (cancel / cleanup).
    func stopRecording() {
        teardown()
    }

    /// Tear down the audio engine and recognition task. Idempotent.
    private func teardown() {
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
            // Push-to-talk holds the mic open until release.
            guard self.autoStopOnSilence else { return }
            // Don't auto-stop until the user has actually said something.
            guard self.hasReceivedSpeech else { return }

            let elapsed = Date().timeIntervalSince(self.lastResultTime)
            if elapsed >= self.silenceThreshold {
                // Silence detected — finalize with the transcript we've gathered
                // from partial results (don't wait on the flaky on-device final).
                DispatchQueue.main.async {
                    self.finish()
                }
            }
        }
    }
}
