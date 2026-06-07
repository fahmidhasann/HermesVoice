import HermesVoiceKit

enum PartialReconcilerTests {
    typealias Outcome = PartialReconciler.Outcome

    static let cases: [TestCase] = [
        TestCase(name: "user turn + partial → fold (incomplete reply, retryable)") {
            let o = PartialReconciler.decide(lastJSONLRole: "user",
                                             partialContent: "The answer is",
                                             trailingAssistantContent: nil)
            checkEqual(o, Outcome.fold)
        },
        TestCase(name: "superseded: assistant turn starts with partial → deleteOnly") {
            let o = PartialReconciler.decide(lastJSONLRole: "assistant",
                                             partialContent: "Hello",
                                             trailingAssistantContent: "Hello, world!")
            checkEqual(o, Outcome.deleteOnly)
        },
        TestCase(name: "assistant turn equal to partial → deleteOnly") {
            let o = PartialReconciler.decide(lastJSONLRole: "assistant",
                                             partialContent: "Done.",
                                             trailingAssistantContent: "Done.")
            checkEqual(o, Outcome.deleteOnly)
        },
        TestCase(name: "assistant turn not matching partial → deleteOnly (no corruption)") {
            let o = PartialReconciler.decide(lastJSONLRole: "assistant",
                                             partialContent: "stale draft",
                                             trailingAssistantContent: "a different committed answer")
            checkEqual(o, Outcome.deleteOnly)
        },
        TestCase(name: "orphan: empty transcript (nil role) + partial → deleteOnly") {
            let o = PartialReconciler.decide(lastJSONLRole: nil,
                                             partialContent: "orphaned text",
                                             trailingAssistantContent: nil)
            checkEqual(o, Outcome.deleteOnly)
        },
        TestCase(name: "empty partial content → ignore") {
            let o = PartialReconciler.decide(lastJSONLRole: "user",
                                             partialContent: "",
                                             trailingAssistantContent: nil)
            checkEqual(o, Outcome.ignore)
        },
        TestCase(name: "whitespace-only partial content → ignore") {
            let o = PartialReconciler.decide(lastJSONLRole: "user",
                                             partialContent: "   \n\t ",
                                             trailingAssistantContent: nil)
            checkEqual(o, Outcome.ignore)
        },
    ]
}
