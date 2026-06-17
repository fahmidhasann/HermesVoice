import Foundation

/// One element of a streamed Hermes response after SSE parsing.
public enum HermesStreamEvent: Equatable, Sendable {
    /// A content delta to append to the assistant message.
    case text(String)
    /// A tool-activity update interleaved in the stream.
    case tool(ToolActivity)
    /// A blocking approval request that needs an explicit user decision.
    case approval(RunApprovalRequest)
    /// The server acknowledged an approval decision.
    case approvalResponded(runId: String, choice: String?)
    /// The run finished. `output` duplicates streamed text when deltas were sent.
    case completed(output: String?)
    /// The run failed or was cancelled.
    case failure(String)
}

/// Synchronous batching state for stream events.
///
/// Text can arrive token-by-token, far faster than SwiftUI can re-render a
/// growing markdown message. This batches adjacent text while preserving tool
/// event ordering by flushing pending text before every tool update.
public struct StreamEventBatcher {
    private var pendingText = ""
    private var flushGate: Debouncer

    public init(flushInterval: TimeInterval) {
        flushGate = Debouncer(interval: flushInterval)
    }

    public mutating func push(_ event: HermesStreamEvent, at now: Date = Date()) -> [HermesStreamEvent] {
        switch event {
        case .text(let chunk):
            guard !chunk.isEmpty else { return [] }
            pendingText += chunk
            guard flushGate.shouldFire(at: now), let flushed = flushText() else { return [] }
            return [flushed]

        case .tool(let activity):
            var output: [HermesStreamEvent] = []
            if let flushed = flushText() { output.append(flushed) }
            output.append(.tool(activity))
            return output

        case .approval, .approvalResponded, .completed, .failure:
            var output: [HermesStreamEvent] = []
            if let flushed = flushText() { output.append(flushed) }
            output.append(event)
            return output
        }
    }

    public mutating func finish() -> HermesStreamEvent? {
        flushText()
    }

    private mutating func flushText() -> HermesStreamEvent? {
        guard !pendingText.isEmpty else { return nil }
        defer { pendingText = "" }
        return .text(pendingText)
    }
}

public enum StreamEventCoalescer {
    /// Drain a high-frequency event stream away from the main actor and emit
    /// bounded text batches to the UI consumer.
    public static func coalesce(
        _ source: AsyncThrowingStream<HermesStreamEvent, Error>,
        flushInterval: TimeInterval
    ) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            // This type is non-actor-isolated, so the task does not inherit
            // ChatSession's @MainActor isolation when called from the UI path.
            let task = Task {
                var batcher = StreamEventBatcher(flushInterval: flushInterval)
                do {
                    for try await event in source {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        for output in batcher.push(event) {
                            continuation.yield(output)
                        }
                    }
                    if let output = batcher.finish() {
                        continuation.yield(output)
                    }
                    continuation.finish()
                } catch {
                    if let output = batcher.finish() {
                        continuation.yield(output)
                    }
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
