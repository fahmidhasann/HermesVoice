import Foundation
import HermesVoiceKit

enum ConversationStoreTests {
    static let cases: [TestCase] = [
        TestCase(name: "deriveTitle trims and collapses whitespace") {
            checkEqual(ConversationStore.deriveTitle(from: "  hello   world  "), "hello world")
            checkEqual(ConversationStore.deriveTitle(from: "line one\nline two"), "line one line two")
        },
        TestCase(name: "deriveTitle empty falls back") {
            checkEqual(ConversationStore.deriveTitle(from: "   \n  "), "New Conversation")
        },
        TestCase(name: "deriveTitle truncates long input") {
            let long = String(repeating: "a", count: 200)
            let title = ConversationStore.deriveTitle(from: long)
            check(title.hasSuffix("…"), "expected ellipsis suffix, got \(title)")
            check(title.count <= ConversationStore.titleMaxLength + 1,
                  "title too long: \(title.count)")
        },

        TestCase(name: "index round-trips") {
            let sessions = [
                SessionMeta(id: "a", title: "First", startedAt: 100, lastActiveAt: 150,
                            messageCount: 2, model: "gpt"),
                SessionMeta(id: "b", title: "Second", startedAt: 200, lastActiveAt: 250)
            ]
            guard let data = try? ConversationStore.encodeIndex(sessions) else {
                check(false, "encodeIndex threw"); return
            }
            let decoded = ConversationStore.decodeIndex(data)
            checkEqual(decoded, sessions)
        },
        TestCase(name: "index nil model round-trips") {
            let sessions = [SessionMeta(id: "a", title: "x", startedAt: 1, lastActiveAt: 2)]
            let data = try! ConversationStore.encodeIndex(sessions)
            let decoded = ConversationStore.decodeIndex(data)
            check(decoded.first?.model == nil, "model should stay nil")
        },
        TestCase(name: "decodeIndex tolerates garbage") {
            checkEqual(ConversationStore.decodeIndex(Data("not json".utf8)), [])
            checkEqual(ConversationStore.decodeIndex(Data()), [])
        },

        TestCase(name: "upsert replaces and sorts most-recent-first") {
            var sessions = [
                SessionMeta(id: "a", title: "A", startedAt: 0, lastActiveAt: 10),
                SessionMeta(id: "b", title: "B", startedAt: 0, lastActiveAt: 20)
            ]
            let updated = SessionMeta(id: "a", title: "A2", startedAt: 0, lastActiveAt: 30)
            sessions = ConversationStore.upsert(updated, into: sessions)
            checkEqual(sessions.count, 2)
            checkEqual(sessions.first?.id, "a")
            checkEqual(sessions.first?.title, "A2")
        },
        TestCase(name: "mostRecent picks latest lastActiveAt") {
            let sessions = [
                SessionMeta(id: "a", title: "A", startedAt: 0, lastActiveAt: 10),
                SessionMeta(id: "b", title: "B", startedAt: 0, lastActiveAt: 99),
                SessionMeta(id: "c", title: "C", startedAt: 0, lastActiveAt: 50)
            ]
            checkEqual(ConversationStore.mostRecent(in: sessions)?.id, "b")
            check(ConversationStore.mostRecent(in: []) == nil, "empty should yield nil")
        },

        TestCase(name: "transcript round-trips") {
            let records = [
                TranscriptRecord(role: "user", content: "hi", ts: 1.0),
                TranscriptRecord(role: "assistant", content: "hello\nthere", ts: 2.0)
            ]
            let text = try! ConversationStore.encodeTranscript(records)
            checkEqual(ConversationStore.decodeTranscript(text), records)
        },
        TestCase(name: "transcript skips blank and malformed lines") {
            let text = """
            {"role":"user","content":"hi","ts":1}

            {garbage}
            {"role":"assistant","content":"yo","ts":2}
            """
            let decoded = ConversationStore.decodeTranscript(text)
            checkEqual(decoded.count, 2)
            checkEqual(decoded.first?.content, "hi")
            checkEqual(decoded.last?.content, "yo")
        },
        TestCase(name: "empty transcript encodes to empty string") {
            checkEqual(try! ConversationStore.encodeTranscript([]), "")
            checkEqual(ConversationStore.decodeTranscript(""), [])
        },
    ]
}
