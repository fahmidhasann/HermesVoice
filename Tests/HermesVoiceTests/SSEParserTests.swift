import Foundation
import HermesVoiceKit

enum SSEParserTests {
    static let cases: [TestCase] = [
        TestCase(name: "content delta") {
            let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
            checkEqual(SSEParser.parse(line: line), .content("Hello"))
        },
        TestCase(name: "done marker") {
            checkEqual(SSEParser.parse(line: "data: [DONE]"), .done)
        },
        TestCase(name: "blank line ignored") {
            checkEqual(SSEParser.parse(line: ""), .ignore)
        },
        TestCase(name: "non-data lines ignored") {
            checkEqual(SSEParser.parse(line: ": keep-alive"), .ignore)
            checkEqual(SSEParser.parse(line: "event: message"), .ignore)
        },
        TestCase(name: "malformed JSON ignored") {
            checkEqual(SSEParser.parse(line: "data: {not json"), .ignore)
        },
        TestCase(name: "empty delta ignored") {
            let line = #"data: {"choices":[{"delta":{}}]}"#
            checkEqual(SSEParser.parse(line: line), .ignore)
        },
        TestCase(name: "empty content string ignored") {
            let line = #"data: {"choices":[{"delta":{"content":""}}]}"#
            checkEqual(SSEParser.parse(line: line), .ignore)
        },
        TestCase(name: "leading-whitespace content preserved") {
            let line = #"data: {"choices":[{"delta":{"content":" world"}}]}"#
            checkEqual(SSEParser.parse(line: line), .content(" world"))
        },

        // MARK: - Stateful stream parser (named events + content)

        TestCase(name: "stream parser handles content") {
            var parser = SSEStreamParser()
            let line = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
            checkEqual(parser.parse(line: line), .content("Hi"))
        },
        TestCase(name: "stream parser handles done") {
            var parser = SSEStreamParser()
            checkEqual(parser.parse(line: "data: [DONE]"), .done)
        },
        TestCase(name: "tool progress running event paired") {
            var parser = SSEStreamParser()
            checkEqual(parser.parse(line: "event: hermes.tool.progress"), .ignore)
            let data = #"data: {"tool":"search","emoji":"🔍","label":"Searching","toolCallId":"c1","status":"running"}"#
            let expected = ToolActivity(tool: "search", emoji: "🔍", label: "Searching",
                                        toolCallId: "c1", status: .running)
            checkEqual(parser.parse(line: data), .toolActivity(expected))
        },
        TestCase(name: "tool progress completed event paired") {
            var parser = SSEStreamParser()
            _ = parser.parse(line: "event: hermes.tool.progress")
            let data = #"data: {"tool":"search","toolCallId":"c1","status":"completed"}"#
            let expected = ToolActivity(tool: "search", toolCallId: "c1", status: .completed)
            checkEqual(parser.parse(line: data), .toolActivity(expected))
        },
        TestCase(name: "event does not bleed into next data line") {
            var parser = SSEStreamParser()
            _ = parser.parse(line: "event: hermes.tool.progress")
            let toolData = #"data: {"tool":"search","toolCallId":"c1","status":"running"}"#
            _ = parser.parse(line: toolData)
            // The following content line must be treated as content, not a tool event.
            let contentLine = #"data: {"choices":[{"delta":{"content":"hi"}}]}"#
            checkEqual(parser.parse(line: contentLine), .content("hi"))
        },
        TestCase(name: "blank line clears pending event") {
            var parser = SSEStreamParser()
            _ = parser.parse(line: "event: hermes.tool.progress")
            checkEqual(parser.parse(line: ""), .ignore)
            // After the blank line the event is cleared, so this parses as content.
            let contentLine = #"data: {"choices":[{"delta":{"content":"x"}}]}"#
            checkEqual(parser.parse(line: contentLine), .content("x"))
        },
        TestCase(name: "malformed tool progress ignored") {
            var parser = SSEStreamParser()
            _ = parser.parse(line: "event: hermes.tool.progress")
            checkEqual(parser.parse(line: "data: {not json"), .ignore)
        },
        TestCase(name: "stream parser handles data with no leading space") {
            // SSE allows `data:x` (no space). The stateful parser strips an
            // optional single space, so both forms must decode identically.
            var parser = SSEStreamParser()
            checkEqual(parser.parse(line: "data:[DONE]"), .done)
            let line = #"data:{"choices":[{"delta":{"content":"Hi"}}]}"#
            checkEqual(parser.parse(line: line), .content("Hi"))
        },
        TestCase(name: "tool progress data without preceding event is treated as content path") {
            // A `data:` line carrying a tool payload but no `event:` qualifier
            // is not a named event — it has no content delta, so it's ignored.
            var parser = SSEStreamParser()
            let data = #"data: {"tool":"search","toolCallId":"c1","status":"running"}"#
            checkEqual(parser.parse(line: data), .ignore)
        },
        TestCase(name: "unknown named event clears and ignores its data line") {
            var parser = SSEStreamParser()
            _ = parser.parse(line: "event: hermes.something.else")
            // Unknown event → its data line falls through the content path → ignore.
            checkEqual(parser.parse(line: "data: {}"), .ignore)
            // And the pending event is cleared, so subsequent content parses.
            let line = #"data: {"choices":[{"delta":{"content":"ok"}}]}"#
            checkEqual(parser.parse(line: line), .content("ok"))
        },
        TestCase(name: "comment/keep-alive line ignored by stream parser") {
            var parser = SSEStreamParser()
            checkEqual(parser.parse(line: ": keep-alive"), .ignore)
        },

        // MARK: - ToolActivity Codable round-trip

        TestCase(name: "ToolActivity round-trips through JSON") {
            let activity = ToolActivity(tool: "search", emoji: "🔍", label: "Searching",
                                        toolCallId: "c1", status: .running)
            let data = try! JSONEncoder().encode(activity)
            let decoded = try! JSONDecoder().decode(ToolActivity.self, from: data)
            checkEqual(decoded, activity)
        },
        TestCase(name: "ToolActivity decodes completed with only required fields") {
            let json = #"{"tool":"search","toolCallId":"c1","status":"completed"}"#
            let decoded = try! JSONDecoder().decode(ToolActivity.self, from: Data(json.utf8))
            checkEqual(decoded.status, .completed)
            check(decoded.emoji == nil && decoded.label == nil,
                  "optional fields absent should decode as nil")
        },
        TestCase(name: "ToolActivity with unknown status fails to decode (ignored upstream)") {
            let json = #"{"tool":"x","status":"pending"}"#
            let decoded = try? JSONDecoder().decode(ToolActivity.self, from: Data(json.utf8))
            check(decoded == nil, "unknown status is not a valid case")
        },
    ]
}
