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
    ]
}
