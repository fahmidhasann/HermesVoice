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
        TestCase(name: "transcript round-trips image attachments") {
            let records = [
                TranscriptRecord(role: "user", content: "look",
                                 ts: 1.0, images: ["data:image/png;base64,AAAA"]),
                TranscriptRecord(role: "assistant", content: "ok", ts: 2.0)
            ]
            let text = try! ConversationStore.encodeTranscript(records)
            let decoded = ConversationStore.decodeTranscript(text)
            checkEqual(decoded, records)
            checkEqual(decoded.first?.images ?? [], ["data:image/png;base64,AAAA"])
            check(decoded.last?.images == nil, "text-only record should omit images")
        },
        TestCase(name: "transcript without images field decodes (backward compat)") {
            // Pre-image transcripts had no `images` key; it must decode to nil.
            let text = #"{"content":"hi","role":"user","ts":1}"#
            let decoded = ConversationStore.decodeTranscript(text)
            checkEqual(decoded.count, 1)
            check(decoded.first?.images == nil, "missing images key should decode as nil")
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

        // MARK: - Preview

        TestCase(name: "previewText collapses whitespace") {
            checkEqual(ConversationStore.previewText(from: "  hello\n\n  world  "), "hello world")
            checkEqual(ConversationStore.previewText(from: "   \n  "), "")
        },
        TestCase(name: "previewText truncates long content") {
            let long = String(repeating: "b", count: 200)
            let preview = ConversationStore.previewText(from: long)
            check(preview.hasSuffix("…"), "expected ellipsis, got \(preview)")
            check(preview.count <= ConversationStore.previewMaxLength + 1,
                  "preview too long: \(preview.count)")
        },

        // MARK: - Search

        TestCase(name: "matchesQuery is case-insensitive over title and preview") {
            check(ConversationStore.matchesQuery(title: "Hello World", preview: "x", query: "world"),
                  "title should match")
            check(ConversationStore.matchesQuery(title: "x", preview: "Swift Code", query: "swift"),
                  "preview should match")
            check(!ConversationStore.matchesQuery(title: "abc", preview: "def", query: "zzz"),
                  "no match expected")
        },
        TestCase(name: "matchesQuery empty query matches everything") {
            check(ConversationStore.matchesQuery(title: "a", preview: "b", query: ""),
                  "empty query should match")
            check(ConversationStore.matchesQuery(title: "a", preview: "b", query: "   "),
                  "whitespace query should match")
        },

        // MARK: - Relative time

        TestCase(name: "relativeTime buckets") {
            let now = 1_000_000.0
            checkEqual(ConversationStore.relativeTime(from: now - 10, now: now), "just now")
            checkEqual(ConversationStore.relativeTime(from: now - 120, now: now), "2m ago")
            checkEqual(ConversationStore.relativeTime(from: now - 3 * 3600, now: now), "3h ago")
            checkEqual(ConversationStore.relativeTime(from: now - 2 * 86400, now: now), "2d ago")
            checkEqual(ConversationStore.relativeTime(from: now - 2 * 604_800, now: now), "2w ago")
        },
        TestCase(name: "relativeTime falls back to a date for old entries") {
            let now = 2_000_000.0
            let label = ConversationStore.relativeTime(from: now - 60 * 86400, now: now)
            check(!label.hasSuffix("ago"), "old entry should be a date, got \(label)")
            check(!label.isEmpty, "date label should be non-empty")
        },
        TestCase(name: "relativeTime bucket boundaries") {
            let now = 1_000_000.0
            // Exactly 60s is the first minute boundary (no longer "just now").
            checkEqual(ConversationStore.relativeTime(from: now - 60, now: now), "1m ago")
            // 59m59s is still minutes, 60m flips to hours.
            checkEqual(ConversationStore.relativeTime(from: now - 59 * 60, now: now), "59m ago")
            checkEqual(ConversationStore.relativeTime(from: now - 3600, now: now), "1h ago")
            checkEqual(ConversationStore.relativeTime(from: now - 86400, now: now), "1d ago")
            checkEqual(ConversationStore.relativeTime(from: now - 6 * 86400, now: now), "6d ago")
            checkEqual(ConversationStore.relativeTime(from: now - 604_800, now: now), "1w ago")
        },

        // MARK: - SessionMeta defaults

        TestCase(name: "SessionMeta defaults source to hermes_voice") {
            let meta = SessionMeta(id: "a", title: "t", startedAt: 1, lastActiveAt: 2)
            checkEqual(meta.source, ConversationStore.source)
            checkEqual(meta.source, "hermes_voice")
            checkEqual(meta.messageCount, 0)
        },
        TestCase(name: "index preserves a custom source round-trip") {
            let sessions = [SessionMeta(id: "a", title: "t", startedAt: 1, lastActiveAt: 2,
                                        source: "other", messageCount: 5, model: "m")]
            let data = try! ConversationStore.encodeIndex(sessions)
            checkEqual(ConversationStore.decodeIndex(data), sessions)
        },

        // MARK: - upsert / record line

        TestCase(name: "upsert appends a brand-new session") {
            let existing = [SessionMeta(id: "a", title: "A", startedAt: 0, lastActiveAt: 10)]
            let added = SessionMeta(id: "b", title: "B", startedAt: 0, lastActiveAt: 5)
            let result = ConversationStore.upsert(added, into: existing)
            checkEqual(result.count, 2)
            // Sorted most-recent-first: "a" (10) before "b" (5).
            checkEqual(result.first?.id, "a")
            checkEqual(result.last?.id, "b")
        },
        TestCase(name: "encodeRecordLine is a single JSON line with sorted keys") {
            let line = try! ConversationStore.encodeRecordLine(
                TranscriptRecord(role: "user", content: "hi", ts: 1.0))
            check(!line.contains("\n"), "a record line must not contain a newline")
            // Sorted keys → content before role before ts.
            check(line.contains(#""content":"hi""#), "content present")
            check(line.contains(#""role":"user""#), "role present")
            let decoded = ConversationStore.decodeTranscript(line)
            checkEqual(decoded.count, 1)
            checkEqual(decoded.first?.content, "hi")
        },
        TestCase(name: "transcript preserves order and trailing newline framing") {
            let records = (0..<3).map {
                TranscriptRecord(role: "user", content: "m\($0)", ts: Double($0))
            }
            let text = try! ConversationStore.encodeTranscript(records)
            check(text.hasSuffix("\n"), "non-empty transcript ends with a newline")
            checkEqual(ConversationStore.decodeTranscript(text), records)
        },
    ]
}
