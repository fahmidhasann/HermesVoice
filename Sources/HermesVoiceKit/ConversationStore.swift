import Foundation

/// Metadata for one stored conversation — the shape persisted in `sessions.json`.
/// Timestamps are epoch seconds so the on-disk JSON stays language-agnostic and
/// trivially diffable.
public struct SessionMeta: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startedAt: Double
    public var lastActiveAt: Double
    public var source: String
    public var messageCount: Int
    public var model: String?

    public init(id: String,
                title: String,
                startedAt: Double,
                lastActiveAt: Double,
                source: String = ConversationStore.source,
                messageCount: Int = 0,
                model: String? = nil) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.source = source
        self.messageCount = messageCount
        self.model = model
    }
}

/// One line of a per-conversation transcript (`transcripts/<id>.jsonl`).
public struct TranscriptRecord: Codable, Equatable, Sendable {
    public var role: String
    public var content: String
    public var ts: Double

    public init(role: String, content: String, ts: Double) {
        self.role = role
        self.content = content
        self.ts = ts
    }
}

/// Pure (de)serialization + index manipulation for the local conversation store.
/// All disk IO lives in the app layer (`ConversationFileStore`); everything here
/// is hardware-free and unit-tested.
public enum ConversationStore {
    /// Tag written to every locally-owned session so the agent can identify our
    /// records when reading `~/.hermes/hermes_voice/`.
    public static let source = "hermes_voice"

    /// Titles are derived from the first user message, truncated to keep the
    /// history list compact.
    public static let titleMaxLength = 60

    /// Previews (last-message snippet shown in the history list) are truncated
    /// so each row stays a single compact line.
    public static let previewMaxLength = 80

    /// On-disk envelope for the index file. Wrapping the array in an object keeps
    /// room for future top-level fields (schema version, etc.).
    private struct IndexFile: Codable {
        var sessions: [SessionMeta]
    }

    // MARK: - Title

    /// Derive a compact, single-line title from the first user message.
    public static func deriveTitle(from firstUserMessage: String) -> String {
        let trimmed = firstUserMessage
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !trimmed.isEmpty else { return "New Conversation" }
        if trimmed.count <= titleMaxLength { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: titleMaxLength)
        return String(trimmed[..<cutoff]).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Collapse a message into a single compact line for the history preview.
    public static func previewText(from content: String) -> String {
        let collapsed = content
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= previewMaxLength { return collapsed }
        let cutoff = collapsed.index(collapsed.startIndex, offsetBy: previewMaxLength)
        return String(collapsed[..<cutoff]).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Search

    /// Case-insensitive match of a query against a conversation's title or
    /// preview, used to filter the in-panel history list as the user types. An
    /// empty query matches everything.
    public static func matchesQuery(title: String, preview: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return title.lowercased().contains(q) || preview.lowercased().contains(q)
    }

    // MARK: - Relative time

    /// Compact relative-time label for the history list ("just now", "5m ago",
    /// "3h ago", "2d ago", "2w ago"), falling back to a short "MMM d" date for
    /// anything older than a few weeks. `now` is injectable for tests.
    public static func relativeTime(from epoch: Double,
                                    now: Double = Date().timeIntervalSince1970) -> String {
        let delta = now - epoch
        if delta < 60 { return "just now" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(delta / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(delta / 86400)
        if days < 7 { return "\(days)d ago" }
        let weeks = Int(delta / 604_800)
        if weeks < 5 { return "\(weeks)w ago" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }

    // MARK: - Index

    public static func encodeIndex(_ sessions: [SessionMeta]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(IndexFile(sessions: sessions))
    }

    /// Tolerant decode — a missing or corrupt index reads as empty rather than
    /// throwing, so a bad file never blocks launch.
    public static func decodeIndex(_ data: Data) -> [SessionMeta] {
        guard !data.isEmpty,
              let file = try? JSONDecoder().decode(IndexFile.self, from: data)
        else { return [] }
        return file.sessions
    }

    /// Insert or replace a session, returning the list sorted most-recent-first.
    public static func upsert(_ meta: SessionMeta, into sessions: [SessionMeta]) -> [SessionMeta] {
        var result = sessions.filter { $0.id != meta.id }
        result.append(meta)
        result.sort { $0.lastActiveAt > $1.lastActiveAt }
        return result
    }

    public static func mostRecent(in sessions: [SessionMeta]) -> SessionMeta? {
        sessions.max(by: { $0.lastActiveAt < $1.lastActiveAt })
    }

    // MARK: - Transcript

    /// Encode one record as a single JSONL line (no trailing newline).
    public static func encodeRecordLine(_ record: TranscriptRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(record), as: UTF8.self)
    }

    /// Encode a whole transcript as newline-terminated JSONL.
    public static func encodeTranscript(_ records: [TranscriptRecord]) throws -> String {
        try records.map(encodeRecordLine).joined(separator: "\n") + (records.isEmpty ? "" : "\n")
    }

    /// Parse JSONL transcript text, skipping any blank or malformed lines.
    public static func decodeTranscript(_ text: String) -> [TranscriptRecord] {
        var records: [TranscriptRecord] = []
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(TranscriptRecord.self, from: data)
            else { continue }
            records.append(record)
        }
        return records
    }
}
