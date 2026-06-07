import Foundation
import HermesVoiceKit

class HermesAPIClient {
    private let config = Config.shared

    func sendMessage(_ text: String, history: [(role: String, content: String)] = []) async throws -> AsyncStream<String> {
        let url = config.apiEndpoint
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.sessionId, forHTTPHeaderField: "X-Hermes-Session-Id")

        // Build messages array with conversation history
        var messages: [[String: String]] = []
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "messages": messages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw HermesAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        return AsyncStream<String> { continuation in
            Task {
                do {
                    for try await line in asyncBytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        switch SSEParser.parse(line: line) {
                        case .content(let chunk):
                            continuation.yield(chunk)
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

enum HermesAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Hermes API"
        case .httpError(let code):
            return "HTTP error \(code) from Hermes API"
        case .noAPIKey:
            return "No API key found in ~/.hermes/.env"
        }
    }
}
