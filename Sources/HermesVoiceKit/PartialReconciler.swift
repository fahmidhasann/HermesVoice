import Foundation

/// Decides what to do with a leftover `transcripts/<id>.partial` side-file
/// found at load time, deterministically and without any ids or schema change.
///
/// Background: while a reply streams, the in-flight assistant text is debounced
/// to a `.partial` side-file. On normal completion `finishAssistant` appends the
/// final assistant record to the `.jsonl` **then** deletes the `.partial`. A
/// crash (e.g. ⌘Q mid-stream) can leave a `.partial` behind, sometimes
/// alongside a committed final record. This type encodes the recovery rule
/// (plan §4.7) so it can be unit-tested in isolation from the AppKit layer.
public enum PartialReconciler {
    /// The action the load path should take for a discovered `.partial`.
    public enum Outcome: Equatable, Sendable {
        /// Append the partial as an incomplete, retryable trailing assistant
        /// message, then delete the `.partial` file.
        case fold
        /// Don't add anything to the transcript; just delete the stale
        /// `.partial` file (it was superseded or can't be safely anchored).
        case deleteOnly
        /// Nothing recoverable; leave the transcript untouched.
        case ignore
    }

    /// - Parameters:
    ///   - lastJSONLRole: role of the final committed record in the `.jsonl`
    ///     (`"user"`, `"assistant"`, …), or `nil` if the transcript is empty.
    ///   - partialContent: the text recovered from the `.partial` file.
    ///   - trailingAssistantContent: the content of the final record when it is
    ///     an assistant turn (used to detect a superseded partial), else `nil`.
    public static func decide(lastJSONLRole: String?,
                              partialContent: String,
                              trailingAssistantContent: String?) -> Outcome {
        // An empty/whitespace partial carries nothing worth recovering.
        if partialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .ignore
        }

        // Only fold when the last committed record is a USER turn — i.e. the
        // assistant never got to commit an answer, so the partial is the
        // genuine incomplete trailing reply and the user turn anchors a retry.
        if lastJSONLRole == "user" {
            return .fold
        }

        // Last record is an assistant turn that already begins with the partial
        // text → the partial was superseded by the committed answer. Drop it.
        if lastJSONLRole == "assistant",
           let committed = trailingAssistantContent,
           committed.hasPrefix(partialContent) {
            return .deleteOnly
        }

        // Any other shape (assistant turn that doesn't match, or an orphan
        // partial with no anchoring user turn) is not safe to fold into the
        // history; remove the stale file rather than corrupt turn order.
        return .deleteOnly
    }
}
