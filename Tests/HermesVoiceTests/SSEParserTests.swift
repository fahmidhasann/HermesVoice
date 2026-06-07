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
    ]
}
