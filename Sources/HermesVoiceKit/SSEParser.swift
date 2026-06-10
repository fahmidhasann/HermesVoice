import Foundation

/// A tool-activity event emitted by Hermes as a named SSE event
/// (`event: hermes.tool.progress` followed by its `data:` line).
public struct ToolActivity: Hashable, Sendable, Codable {
    public enum Status: String, Hashable, Sendable, Codable {
        case running
        case completed
    }

    public let tool: String
    public let emoji: String?
    public let label: String?
    public let toolCallId: String?
    public let status: Status

    public init(tool: String,
                emoji: String? = nil,
                label: String? = nil,
                toolCallId: String? = nil,
                status: Status) {
        self.tool = tool
        self.emoji = emoji
        self.label = label
        self.toolCallId = toolCallId
        self.status = status
    }
}

/// One decoded outcome from a Server-Sent-Events line in the chat stream.
public enum SSEEvent: Equatable, Sendable {
    /// A content delta to append to the assistant message.
    case content(String)
    /// A tool-activity update (from a `hermes.tool.progress` named event).
    case toolActivity(ToolActivity)
    /// The terminal `data: [DONE]` marker — stop reading.
    case done
    /// Line carried nothing usable (blank, non-`data:`, or malformed) — skip.
    case ignore
}

/// Stateless parser for the OpenAI-compatible content chunks Hermes emits.
/// Kept for the simple per-line content path (and its existing tests); the
/// streaming client uses `SSEStreamParser`, which also understands named events.
public enum SSEParser {
    struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]?
    }

    /// Parse a single raw line into an `SSEEvent`. Only content/`[DONE]` are
    /// recognized here — `event:`-named lines read as `.ignore`.
    public static func parse(line: String) -> SSEEvent {
        guard !line.isEmpty else { return .ignore }
        guard line.hasPrefix("data: ") else { return .ignore }

        let data = String(line.dropFirst(6))
        if data == "[DONE]" { return .done }
        return parseContent(payload: data)
    }

    /// Decode the JSON payload of a content chunk (the text after `data: `).
    static func parseContent(payload: String) -> SSEEvent {
        guard let jsonData = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: jsonData),
              let content = chunk.choices?.first?.delta?.content,
              !content.isEmpty
        else { return .ignore }

        return .content(content)
    }
}

/// Stateful line parser for the full Hermes SSE stream. Unlike `SSEParser`, it
/// remembers an `event:` line so the following `data:` line can be interpreted
/// in context — which is how named events like `hermes.tool.progress` arrive.
public struct SSEStreamParser {
    /// The name from the most recent `event:` line, applied to the next `data:`.
    private var pendingEvent: String?

    public init() {}

    public mutating func parse(line: String) -> SSEEvent {
        // Named-event line: remember it; it qualifies the next data line.
        if line.hasPrefix("event:") {
            pendingEvent = String(line.dropFirst("event:".count))
                .trimmingCharacters(in: .whitespaces)
            return .ignore
        }

        // A blank line dispatches/closes the current event group.
        if line.isEmpty {
            pendingEvent = nil
            return .ignore
        }

        guard line.hasPrefix("data:") else { return .ignore }

        let event = pendingEvent
        pendingEvent = nil

        // Strip "data:" plus an optional single leading space.
        var payload = String(line.dropFirst("data:".count))
        if payload.hasPrefix(" ") { payload.removeFirst() }

        if event == "hermes.tool.progress" {
            guard let data = payload.data(using: .utf8),
                  let activity = try? JSONDecoder().decode(ToolActivity.self, from: data)
            else { return .ignore }
            return .toolActivity(activity)
        }

        if payload == "[DONE]" { return .done }
        return SSEParser.parseContent(payload: payload)
    }
}
