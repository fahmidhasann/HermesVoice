import Foundation
import HermesVoiceKit

/// Disk IO for the local conversation store under `~/.hermes/hermes_voice/`.
/// All (de)serialization is delegated to `HermesVoiceKit.ConversationStore`;
/// this layer only touches the filesystem. Writes are atomic (temp + rename).
///
/// Layout:
///   ~/.hermes/hermes_voice/sessions.json          — index of all conversations
///   ~/.hermes/hermes_voice/transcripts/<id>.jsonl — one transcript per conversation
final class ConversationFileStore {
    private let rootURL: URL
    private let transcriptsURL: URL
    private let indexURL: URL
    private let fileManager = FileManager.default

    /// `root` is injectable for tests; defaults to `~/.hermes/hermes_voice`.
    init(root: URL? = nil) {
        let base = root ?? URL(fileURLWithPath: NSString("~/.hermes/hermes_voice").expandingTildeInPath)
        rootURL = base
        transcriptsURL = base.appendingPathComponent("transcripts", isDirectory: true)
        indexURL = base.appendingPathComponent("sessions.json")
        try? fileManager.createDirectory(at: transcriptsURL, withIntermediateDirectories: true)
    }

    // MARK: - Index

    func loadIndex() -> [SessionMeta] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return ConversationStore.decodeIndex(data)
    }

    func saveIndex(_ sessions: [SessionMeta]) {
        guard let data = try? ConversationStore.encodeIndex(sessions) else { return }
        atomicWrite(data, to: indexURL)
    }

    // MARK: - Transcripts

    private func transcriptURL(for id: String) -> URL {
        transcriptsURL.appendingPathComponent("\(id).jsonl")
    }

    func loadTranscript(id: String) -> [TranscriptRecord] {
        guard let text = try? String(contentsOf: transcriptURL(for: id), encoding: .utf8) else { return [] }
        return ConversationStore.decodeTranscript(text)
    }

    /// A single-line snippet of the conversation's most recent message, used for
    /// the history list. Returns an empty string when there's nothing to show.
    /// Only the **last** JSONL line is decoded: this runs for every row on each
    /// history open, and full transcripts can carry megabytes of base64 image
    /// data per line that a preview never needs.
    func loadPreview(id: String) -> String {
        guard let text = try? String(contentsOf: transcriptURL(for: id), encoding: .utf8),
              let lastLine = text.split(separator: "\n", omittingEmptySubsequences: true).last,
              let last = ConversationStore.decodeTranscript(String(lastLine)).last
        else { return "" }
        return ConversationStore.previewText(from: last.content)
    }

    /// Append one record to the conversation's transcript, creating it if needed.
    func appendRecord(_ record: TranscriptRecord, to id: String) {
        guard let line = try? ConversationStore.encodeRecordLine(record) else { return }
        let data = Data((line + "\n").utf8)
        let url = transcriptURL(for: id)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Replace a transcript wholesale (used when dropping a retried partial).
    func rewriteTranscript(id: String, records: [TranscriptRecord]) {
        guard let text = try? ConversationStore.encodeTranscript(records) else { return }
        atomicWrite(Data(text.utf8), to: transcriptURL(for: id))
    }

    // MARK: - Partial (crash-recovery side-file)

    private func partialURL(for id: String) -> URL {
        transcriptsURL.appendingPathComponent("\(id).partial")
    }

    /// Write the in-flight assistant text to a `.partial` side-file so a crash
    /// (⌘Q) mid-stream can be recovered on relaunch. Atomic so a crash during
    /// the write itself never leaves a torn file.
    func writePartial(id: String, content: String, ts: Double) {
        let record = PartialRecord(content: content, ts: ts)
        guard let data = try? ConversationStore.encodePartial(record) else { return }
        atomicWrite(data, to: partialURL(for: id))
    }

    /// Read a leftover `.partial`, or `nil` if none exists / it's unreadable.
    func readPartial(id: String) -> PartialRecord? {
        guard let data = try? Data(contentsOf: partialURL(for: id)) else { return nil }
        return ConversationStore.decodePartial(data)
    }

    /// Remove the `.partial` side-file (a no-op if it's already gone).
    func clearPartial(id: String) {
        try? fileManager.removeItem(at: partialURL(for: id))
    }

    // MARK: - Deletion

    func deleteConversation(id: String) {
        try? fileManager.removeItem(at: transcriptURL(for: id))
        try? fileManager.removeItem(at: partialURL(for: id))
        var sessions = loadIndex()
        sessions.removeAll { $0.id == id }
        saveIndex(sessions)
    }

    // MARK: - Atomic write

    private func atomicWrite(_ data: Data, to url: URL) {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
        }
    }
}
