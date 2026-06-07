import HermesVoiceKit

enum ActivityRefCounterTests {
    static let cases: [TestCase] = [
        TestCase(name: "starts at zero") {
            let c = ActivityRefCounter()
            checkEqual(c.count, 0)
        },
        TestCase(name: "first begin acquires the token (0→1 returns true)") {
            var c = ActivityRefCounter()
            check(c.begin(), "first begin must return true (acquire)")
            checkEqual(c.count, 1)
        },
        TestCase(name: "overlapping begins do not re-acquire") {
            var c = ActivityRefCounter()
            check(c.begin(), "first begin acquires")
            check(!c.begin(), "second begin must not re-acquire")
            check(!c.begin(), "third begin must not re-acquire")
            checkEqual(c.count, 3)
        },
        TestCase(name: "last end releases the token (1→0 returns true)") {
            var c = ActivityRefCounter()
            c.begin()
            check(c.end(), "end from 1 must return true (release)")
            checkEqual(c.count, 0)
        },
        TestCase(name: "non-final end does not release") {
            var c = ActivityRefCounter()
            c.begin(); c.begin()
            check(!c.end(), "end from 2 must not release")
            checkEqual(c.count, 1)
            check(c.end(), "end from 1 must release")
            checkEqual(c.count, 0)
        },
        TestCase(name: "end clamps at zero (unbalanced end is a no-op)") {
            var c = ActivityRefCounter()
            check(!c.end(), "end at 0 must return false")
            checkEqual(c.count, 0)
            // A leaked release must not push the count negative and thereby
            // swallow the next legitimate acquire.
            check(c.begin(), "begin after clamped end must still acquire")
            checkEqual(c.count, 1)
        },
        TestCase(name: "balanced acquire/release round-trip") {
            var c = ActivityRefCounter()
            check(c.begin(), "A acquires")
            check(!c.begin(), "B overlaps, no acquire")
            check(!c.end(), "A ends, B still streaming")
            check(c.end(), "B ends, release")
            checkEqual(c.count, 0)
        },
        TestCase(name: "init clamps a negative seed to zero") {
            let c = ActivityRefCounter(count: -5)
            checkEqual(c.count, 0)
        },
    ]
}
