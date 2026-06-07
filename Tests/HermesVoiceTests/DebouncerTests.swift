import Foundation
import HermesVoiceKit

enum DebouncerTests {
    static let cases: [TestCase] = [
        TestCase(name: "first call fires") {
            var d = Debouncer(interval: 0.2)
            check(d.shouldFire(at: Date(timeIntervalSince1970: 100)), "first call should fire")
        },
        TestCase(name: "rapid calls within interval coalesce to one") {
            var d = Debouncer(interval: 0.2)
            let t0 = Date(timeIntervalSince1970: 100)
            check(d.shouldFire(at: t0), "initial fire")
            check(!d.shouldFire(at: t0.addingTimeInterval(0.05)), "+50ms suppressed")
            check(!d.shouldFire(at: t0.addingTimeInterval(0.10)), "+100ms suppressed")
        },
        TestCase(name: "call after interval fires again") {
            var d = Debouncer(interval: 0.2)
            let t0 = Date(timeIntervalSince1970: 100)
            check(d.shouldFire(at: t0), "initial fire")
            check(!d.shouldFire(at: t0.addingTimeInterval(0.1)), "+100ms suppressed")
            check(d.shouldFire(at: t0.addingTimeInterval(0.3)), "+300ms fires again")
        },
        TestCase(name: "boundary at exactly interval fires") {
            var d = Debouncer(interval: 0.2)
            let t0 = Date(timeIntervalSince1970: 100)
            check(d.shouldFire(at: t0), "initial fire")
            check(d.shouldFire(at: t0.addingTimeInterval(0.2)), "elapsed == interval fires")
        },
    ]
}
