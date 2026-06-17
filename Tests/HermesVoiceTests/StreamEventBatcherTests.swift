import Foundation
import HermesVoiceKit

enum StreamEventBatcherTests {
    static let cases: [TestCase] = [
        TestCase(name: "first text chunk flushes immediately") {
            var batcher = StreamEventBatcher(flushInterval: 0.1)
            let t0 = Date(timeIntervalSince1970: 100)

            checkEqual(batcher.push(.text("Hel"), at: t0), [.text("Hel")])
        },
        TestCase(name: "rapid text chunks coalesce until finish") {
            var batcher = StreamEventBatcher(flushInterval: 0.1)
            let t0 = Date(timeIntervalSince1970: 100)

            checkEqual(batcher.push(.text("Hel"), at: t0), [.text("Hel")])
            checkEqual(batcher.push(.text("lo"), at: t0.addingTimeInterval(0.03)), [])
            checkEqual(batcher.push(.text("!"), at: t0.addingTimeInterval(0.06)), [])
            checkEqual(batcher.finish(), .text("lo!"))
        },
        TestCase(name: "text flushes once interval elapses") {
            var batcher = StreamEventBatcher(flushInterval: 0.1)
            let t0 = Date(timeIntervalSince1970: 100)

            checkEqual(batcher.push(.text("a"), at: t0), [.text("a")])
            checkEqual(batcher.push(.text("b"), at: t0.addingTimeInterval(0.05)), [])
            checkEqual(batcher.push(.text("c"), at: t0.addingTimeInterval(0.12)), [.text("bc")])
        },
        TestCase(name: "tool events preserve ordering after pending text") {
            var batcher = StreamEventBatcher(flushInterval: 0.1)
            let t0 = Date(timeIntervalSince1970: 100)
            let tool = ToolActivity(tool: "search", toolCallId: "c1", status: .running)

            checkEqual(batcher.push(.text("a"), at: t0), [.text("a")])
            checkEqual(batcher.push(.text("b"), at: t0.addingTimeInterval(0.03)), [])
            checkEqual(batcher.push(.tool(tool), at: t0.addingTimeInterval(0.04)),
                       [.text("b"), .tool(tool)])
        },
        TestCase(name: "approval events preserve ordering after pending text") {
            var batcher = StreamEventBatcher(flushInterval: 0.1)
            let t0 = Date(timeIntervalSince1970: 100)
            let approval = RunApprovalRequest(runId: "run_1",
                                              command: "python3 x.py",
                                              description: "script execution")

            checkEqual(batcher.push(.text("a"), at: t0), [.text("a")])
            checkEqual(batcher.push(.text("b"), at: t0.addingTimeInterval(0.03)), [])
            checkEqual(batcher.push(.approval(approval), at: t0.addingTimeInterval(0.04)),
                       [.text("b"), .approval(approval)])
        },
    ]
}
