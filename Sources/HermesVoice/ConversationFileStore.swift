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

    // MARK: - Deletion

    func deleteConversation(id: String) {
        try? fileManager.removeItem(at: transcriptURL(for: id))
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
