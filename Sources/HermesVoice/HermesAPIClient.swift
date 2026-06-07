import Foundation
import HermesVoiceKit

/// One element of a streamed Hermes response.
enum HermesStreamEvent {
    /// A content delta to append to the assistant message.
    case text(String)
    /// A tool-activity update interleaved in the stream.
    case tool(ToolActivity)
}

final class HermesAPIClient {
    private let config = Config.shared

    /// Stream a chat completion. The caller owns history, so the full `messages`
    /// array is sent as-is — we deliberately do NOT send `X-Hermes-Session-Id`
    /// (sending both history and the header double-counts context server-side).
    ///
    /// Connection/auth/HTTP failures throw synchronously (before the stream is
    /// returned); a mid-stream drop throws into the returned stream so the caller
    /// can keep whatever partial text already arrived.
    func streamCompletion(messages: [(role: String, content: String)]) async throws -> AsyncThrowingStream<HermesStreamEvent, Error> {
        var request = URLRequest(url: config.apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]
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

    /// Lightweight reachability probe against `/v1/health`. Never throws —
    /// returns `false` for any failure so callers can drive an offline indicator.
    func checkHealth() async -> Bool {
        var request = URLRequest(url: config.healthEndpoint)
        request.httpMethod = "GET"
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
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
        case .invalidResponse, .noAPIKey: return .unknown
        }
    }

    var isTransient: Bool { HermesErrorClassifier.isTransient(kind) }

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Can't reach Hermes. Is the gateway running on 127.0.0.1:8642?"
        case .auth:
            return "Authentication failed. Check API_SERVER_KEY in ~/.hermes/.env."
        case .http(let code):
            return "Hermes returned an error (HTTP \(code))."
        case .streamDropped:
            return "The connection dropped mid-response."
        case .timeout:
            return "Hermes timed out. It may be busy — try again."
        case .invalidResponse:
            return "Invalid response from Hermes."
        case .noAPIKey:
            return "No API key found in ~/.hermes/.env."
        }
    }
}
