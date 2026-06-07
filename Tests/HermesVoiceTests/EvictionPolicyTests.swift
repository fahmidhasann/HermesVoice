import HermesVoiceKit

enum EvictionPolicyTests {
    static let cases: [TestCase] = [
        TestCase(name: "idle, at rest → evictable") {
            check(EvictionPolicy.isEvictable(state: .idle, isStreaming: false, hasPendingPartial: false),
                  "idle session at rest should be evictable")
        },
        TestCase(name: "done, at rest → evictable") {
            check(EvictionPolicy.isEvictable(state: .done, isStreaming: false, hasPendingPartial: false),
                  "done session at rest should be evictable")
        },
        TestCase(name: "error, at rest → evictable") {
            check(EvictionPolicy.isEvictable(state: .error, isStreaming: false, hasPendingPartial: false),
                  "errored session at rest should be evictable")
        },
        TestCase(name: "streaming session is never evictable") {
            check(!EvictionPolicy.isEvictable(state: .responding, isStreaming: true, hasPendingPartial: false),
                  "responding while streaming must not be evictable")
            // Even a terminal state must not be evicted while a stream is in flight.
            check(!EvictionPolicy.isEvictable(state: .idle, isStreaming: true, hasPendingPartial: false),
                  "isStreaming guards regardless of state")
        },
        TestCase(name: "pending partial flush blocks eviction") {
            check(!EvictionPolicy.isEvictable(state: .done, isStreaming: false, hasPendingPartial: true),
                  "a queued partial write must block eviction")
        },
        TestCase(name: "active (non-terminal) states are not evictable") {
            for s in [SessionLifecycleState.listening, .transcribing, .sending, .responding] {
                check(!EvictionPolicy.isEvictable(state: s, isStreaming: false, hasPendingPartial: false),
                      "non-terminal state \(s) should not be evictable")
            }
        },
    ]
}
