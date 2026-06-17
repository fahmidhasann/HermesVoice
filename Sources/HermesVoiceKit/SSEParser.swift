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

/// A dangerous-command/script approval request emitted by the Hermes run-event
/// API. The app answers it with `POST /v1/runs/{runId}/approval`.
public struct RunApprovalRequest: Hashable, Sendable {
    public let runId: String
    public let command: String
    public let description: String
    public let choices: [String]
    public let allowPermanent: Bool

    public init(runId: String,
                command: String,
                description: String,
                choices: [String] = ["once", "session", "always", "deny"],
                allowPermanent: Bool = true) {
        self.runId = runId
        self.command = command
        self.description = description
        self.choices = choices
        self.allowPermanent = allowPermanent
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

/// Parser for the structured `/v1/runs/{run_id}/events` SSE endpoint.
/// The endpoint emits JSON payloads on plain `data:` lines whose `event` field
/// carries the semantic type.
public struct HermesRunEventParser {
    public init() {}

    public mutating func parse(line: String) -> HermesStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        var payload = String(line.dropFirst("data:".count))
        if payload.hasPrefix(" ") { payload.removeFirst() }
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String
        else { return nil }

        switch event {
        case "message.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return nil }
            return .text(delta)

        case "tool.started":
            let tool = (json["tool"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "tool"
            let preview = (json["preview"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .tool(ToolActivity(tool: tool,
                                      emoji: nil,
                                      label: preview ?? tool,
                                      toolCallId: nil,
                                      status: .running))

        case "tool.completed":
            let tool = (json["tool"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "tool"
            return .tool(ToolActivity(tool: tool, status: .completed))

        case "approval.request":
            guard let runId = json["run_id"] as? String, !runId.isEmpty else { return nil }
            let command = json["command"] as? String ?? ""
            let description = json["description"] as? String ?? "Approval required"
            let choices = (json["choices"] as? [String]) ?? ["once", "session", "always", "deny"]
            let allowPermanent = json["allow_permanent"] as? Bool ?? choices.contains("always")
            return .approval(RunApprovalRequest(runId: runId,
                                                command: command,
                                                description: description,
                                                choices: choices,
                                                allowPermanent: allowPermanent))

        case "approval.responded":
            guard let runId = json["run_id"] as? String, !runId.isEmpty else { return nil }
            return .approvalResponded(runId: runId, choice: json["choice"] as? String)

        case "run.completed":
            return .completed(output: json["output"] as? String)

        case "run.failed":
            return .failure(json["error"] as? String ?? "Agent run failed.")

        case "run.cancelled":
            return .failure("Agent run cancelled.")

        default:
            return nil
        }
    }
}
