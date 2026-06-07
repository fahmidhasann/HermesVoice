import Foundation

/// One decoded outcome from a Server-Sent-Events line in the chat stream.
public enum SSEEvent: Equatable, Sendable {
    /// A content delta to append to the assistant message.
    case content(String)
    /// The terminal `data: [DONE]` marker — stop reading.
    case done
    /// Line carried nothing usable (blank, non-`data:`, or malformed) — skip.
    case ignore
}

/// Pure parser for the OpenAI-compatible SSE chunks Hermes emits.
public enum SSEParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]?
    }

    /// Parse a single raw line from the byte stream into an `SSEEvent`.
    public static func parse(line: String) -> SSEEvent {
        guard !line.isEmpty else { return .ignore }
        guard line.hasPrefix("data: ") else { return .ignore }

        let data = String(line.dropFirst(6))
        if data == "[DONE]" { return .done }

        guard let jsonData = data.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: jsonData),
              let content = chunk.choices?.first?.delta?.content,
              !content.isEmpty
        else { return .ignore }

        return .content(content)
    }
}
