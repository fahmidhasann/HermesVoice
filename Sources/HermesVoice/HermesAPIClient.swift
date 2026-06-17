import Foundation
import HermesVoiceKit

/// One message in an outgoing request. When `imageDataURLs` is empty the content
/// is serialized as a plain string; otherwise it becomes an OpenAI-style
/// multimodal `content` array of text + `image_url` parts (the shape the Hermes
/// gateway accepts — verified against `_normalize_multimodal_content`).
struct OutgoingMessage {
    let role: String
    let text: String
    let imageDataURLs: [String]

    /// JSON value for the `content` field: a string for text-only messages, or an
    /// array of typed parts when images are attached.
    var contentJSON: Any {
        guard !imageDataURLs.isEmpty else { return text }
        var parts: [[String: Any]] = []
        if !text.isEmpty {
            parts.append(["type": "text", "text": text])
        }
        for url in imageDataURLs {
            parts.append(["type": "image_url", "image_url": ["url": url]])
        }
        return parts
    }
}

final class HermesAPIClient {
    private let config = Config.shared

    /// Endpoints are resolved per call from the live settings (host/port), so a
    /// change in the Connection tab takes effect on the next request without a
    /// restart. The stored URL is normalized first (scheme prepended, trailing
    /// path stripped) so a slightly-off entry still hits the right target;
    /// Settings/onboarding surface invalid entries at edit time. Falls back to
    /// the compiled-in default if no URL can be built at all.
    private func endpoint(_ path: String) -> URL {
        let settings = AppSettingsStore.loadCurrent()
        let base = AppSettings.normalizedGatewayURL(settings.gatewayURL) ?? settings.baseURLString
        return URL(string: base + path) ?? config.apiEndpoint
    }

    /// Attach the bearer token from the Keychain, read **per request** so a key
    /// entered in onboarding/Settings takes effect on the next call without a
    /// restart. Omitted entirely when no key is set, so no-auth local gateways
    /// aren't sent an empty `Bearer`.
    private func authorize(_ request: inout URLRequest) {
        if let apiKey = CredentialsStore.current() {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Stream an agent run. The app uses Hermes' structured run protocol so
    /// approval requests can come back as actionable events. The legacy
    /// Chat Completions stream remains as a compatibility fallback.
    ///
    /// Connection/auth/HTTP failures throw synchronously (before the stream is
    /// returned); a mid-stream drop throws into the returned stream so the caller
    /// can keep whatever partial text already arrived.
    func streamCompletion(messages: [OutgoingMessage],
                          sessionId: String,
                          onRunStarted: @escaping (String) -> Void = { _ in }) async throws -> AsyncThrowingStream<HermesStreamEvent, Error> {
        // The run endpoint currently handles text history. Keep multimodal
        // turns on the OpenAI-compatible path that already normalizes images.
        guard messages.allSatisfy({ $0.imageDataURLs.isEmpty }) else {
            return try await streamChatCompletion(messages: messages)
        }

        do {
            return try await streamRunCompletion(messages: messages,
                                                sessionId: sessionId,
                                                onRunStarted: onRunStarted)
        } catch HermesAPIError.http(let code) where code == 404 || code == 405 {
            return try await streamChatCompletion(messages: messages)
        }
    }

    private func streamChatCompletion(messages: [OutgoingMessage]) async throws -> AsyncThrowingStream<HermesStreamEvent, Error> {
        var request = URLRequest(url: endpoint("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        // The default 60s *idle* timeout would cut agent turns that stay
        // byte-silent during long tool execution; give streams a wide window.
        request.timeoutInterval = 300

        var payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.contentJSON] },
            "stream": true
        ]
        // Honor the user's model choice (Settings ▸ Connection). Omitted when
        // unset so the server applies its own default.
        if let model = AppSettingsStore.loadCurrent().normalizedModel {
            payload["model"] = model
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let urlError as URLError {
            throw HermesAPIError.from(urlError, midStream: false)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HermesAPIError.from(statusCode: httpResponse.statusCode)
        }

        return AsyncThrowingStream<HermesStreamEvent, Error> { continuation in
            let task = Task {
                var parser = SSEStreamParser()
                do {
                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { continuation.finish(); return }
                        switch parser.parse(line: line) {
                        case .content(let chunk):
                            continuation.yield(.text(chunk))
                        case .toolActivity(let activity):
                            continuation.yield(.tool(activity))
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            continue
                        }
                    }
                    continuation.finish()
                } catch let urlError as URLError {
                    continuation.finish(throwing: HermesAPIError.from(urlError, midStream: true))
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: HermesAPIError.streamDropped)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamRunCompletion(messages: [OutgoingMessage],
                                     sessionId: String,
                                     onRunStarted: @escaping (String) -> Void) async throws -> AsyncThrowingStream<HermesStreamEvent, Error> {
        guard let last = messages.last, last.role == "user" else {
            throw HermesAPIError.invalidResponse
        }

        var request = URLRequest(url: endpoint("/v1/runs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let history = messages.dropLast().map {
            ["role": $0.role, "content": $0.text]
        }
        var payload: [String: Any] = [
            "input": last.text,
            "conversation_history": Array(history),
            "session_id": sessionId
        ]
        if let model = AppSettingsStore.loadCurrent().normalizedModel {
            payload["model"] = model
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw HermesAPIError.from(urlError, midStream: false)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HermesAPIError.from(statusCode: httpResponse.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runId = json["run_id"] as? String,
              !runId.isEmpty else {
            throw HermesAPIError.invalidResponse
        }
        onRunStarted(runId)

        return streamRunEvents(runId: runId)
    }

    private func streamRunEvents(runId: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        AsyncThrowingStream<HermesStreamEvent, Error> { continuation in
            let task = Task {
                var terminal = false
                do {
                    var request = URLRequest(url: endpoint("/v1/runs/\(runId)/events"))
                    request.httpMethod = "GET"
                    authorize(&request)
                    request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
                    request.timeoutInterval = 300

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw HermesAPIError.invalidResponse
                    }
                    guard httpResponse.statusCode == 200 else {
                        throw HermesAPIError.from(statusCode: httpResponse.statusCode)
                    }

                    var parser = HermesRunEventParser()
                    for try await line in asyncBytes.lines {
                        if Task.isCancelled {
                            await stopRun(runId: runId)
                            continuation.finish()
                            return
                        }
                        guard let event = parser.parse(line: line) else { continue }
                        switch event {
                        case .completed:
                            terminal = true
                            continuation.yield(event)
                            continuation.finish()
                            return
                        case .failure(let message):
                            terminal = true
                            continuation.finish(throwing: HermesAPIError.agent(message))
                            return
                        default:
                            continuation.yield(event)
                        }
                    }
                    terminal = true
                    continuation.finish()
                } catch let urlError as URLError {
                    if !terminal { await stopRun(runId: runId) }
                    continuation.finish(throwing: HermesAPIError.from(urlError, midStream: true))
                } catch {
                    if !terminal { await stopRun(runId: runId) }
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func submitApproval(runId: String, choice: String) async throws {
        var request = URLRequest(url: endpoint("/v1/runs/\(runId)/approval"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: ["choice": choice])

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw HermesAPIError.from(urlError, midStream: false)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HermesAPIError.from(statusCode: httpResponse.statusCode)
        }
    }

    func stopRun(runId: String) async {
        var request = URLRequest(url: endpoint("/v1/runs/\(runId)/stop"))
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Lightweight reachability probe against `/v1/health`. Never throws —
    /// returns `false` for any failure so callers can drive an offline indicator.
    func checkHealth() async -> Bool {
        var request = URLRequest(url: endpoint("/v1/health"))
        request.httpMethod = "GET"
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    /// Fetch available model ids from `/v1/models` for the Settings model picker.
    /// Returns an empty list on any failure (offline, auth, malformed) so the UI
    /// can degrade to a free-text fallback.
    func fetchModels() async -> [String] {
        var request = URLRequest(url: endpoint("/v1/models"))
        request.httpMethod = "GET"
        authorize(&request)
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { $0["id"] as? String }
    }
}

enum HermesAPIError: LocalizedError, Equatable {
    case offline
    case auth
    case http(Int)
    case streamDropped
    case timeout
    case invalidResponse
    case noAPIKey
    case agent(String)

    static func from(_ urlError: URLError, midStream: Bool) -> HermesAPIError {
        switch HermesErrorClassifier.classify(urlErrorCode: urlError.errorCode, midStream: midStream) {
        case .offline:       return .offline
        case .streamDropped: return .streamDropped
        case .timeout:       return .timeout
        case .auth:          return .auth
        case .http(let code): return .http(code)
        case .unknown:       return midStream ? .streamDropped : .invalidResponse
        }
    }

    static func from(statusCode: Int) -> HermesAPIError {
        switch HermesErrorClassifier.classify(statusCode: statusCode) {
        case .auth:           return .auth
        case .http(let code): return .http(code)
        default:              return .http(statusCode)
        }
    }

    var kind: HermesErrorKind {
        switch self {
        case .offline:        return .offline
        case .auth:           return .auth
        case .http(let code): return .http(code)
        case .streamDropped:  return .streamDropped
        case .timeout:        return .timeout
        case .invalidResponse, .noAPIKey, .agent: return .unknown
        }
    }

    var isTransient: Bool { HermesErrorClassifier.isTransient(kind) }

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Can't reach the gateway. Check the URL in Settings ▸ Connection."
        case .auth:
            return "Authentication failed. Check your API key in Settings ▸ Connection."
        case .http(let code):
            return "The gateway returned an error (HTTP \(code))."
        case .streamDropped:
            return "The connection dropped mid-response."
        case .timeout:
            return "The gateway timed out. It may be busy — try again."
        case .invalidResponse:
            return "Invalid response from the gateway."
        case .noAPIKey:
            return "No API key set. Add one in Settings ▸ Connection."
        case .agent(let message):
            return message
        }
    }
}
