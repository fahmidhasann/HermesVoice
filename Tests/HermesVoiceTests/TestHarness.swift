import Foundation

/// Minimal test harness used in place of XCTest (unavailable under the
/// Command Line Tools toolchain). Tests register checks; `runAllTests`
/// reports results and the process exits non-zero on any failure.

private(set) var totalChecks = 0
private(set) var failures: [String] = []

func check(_ condition: Bool, _ message: @autoclosure () -> String,
           file: StaticString = #fileID, line: UInt = #line) {
    totalChecks += 1
    if !condition {
        failures.append("✘ [\(file):\(line)] \(message())")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                              file: StaticString = #fileID, line: UInt = #line) {
    let prefix = label.isEmpty ? "" : "\(label): "
    check(actual == expected, "\(prefix)expected \(expected), got \(actual)",
          file: file, line: line)
}

/// A named test case.
struct TestCase {
    let name: String
    let run: () -> Void
}

func runAllTests(_ cases: [TestCase]) -> Never {
    print("Running \(cases.count) test cases…\n")
    for c in cases {
        let before = failures.count
        c.run()
        let caseFailures = failures.count - before
        let mark = caseFailures == 0 ? "✓" : "✘"
        print("  \(mark) \(c.name)")
    }

    print("\n\(totalChecks) checks, \(failures.count) failures")
    if !failures.isEmpty {
        print("\nFailures:")
        for f in failures { print("  \(f)") }
        exit(1)
    }
    print("ALL TESTS PASSED")
    exit(0)
}
