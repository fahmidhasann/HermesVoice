import Foundation
import HermesVoiceKit

enum HermesErrorTests {
    static let cases: [TestCase] = [
        TestCase(name: "auth status codes classify as auth") {
            checkEqual(HermesErrorClassifier.classify(statusCode: 401), .auth)
            checkEqual(HermesErrorClassifier.classify(statusCode: 403), .auth)
        },
        TestCase(name: "other status codes classify as http") {
            checkEqual(HermesErrorClassifier.classify(statusCode: 500), .http(500))
            checkEqual(HermesErrorClassifier.classify(statusCode: 404), .http(404))
        },
        TestCase(name: "connection-refused classifies as offline") {
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorCannotConnectToHost, midStream: false),
                .offline)
        },
        TestCase(name: "connection lost mid-stream is a drop") {
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorNetworkConnectionLost, midStream: true),
                .streamDropped)
        },
        TestCase(name: "connection lost before stream is offline") {
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorNetworkConnectionLost, midStream: false),
                .offline)
        },
        TestCase(name: "timeout classifies as timeout") {
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorTimedOut, midStream: false),
                .timeout)
        },
        TestCase(name: "isTransient is true for offline/drop/timeout") {
            check(HermesErrorClassifier.isTransient(.offline), "offline should be transient")
            check(HermesErrorClassifier.isTransient(.streamDropped), "drop should be transient")
            check(HermesErrorClassifier.isTransient(.timeout), "timeout should be transient")
        },
        TestCase(name: "isTransient is false for auth/http/unknown") {
            check(!HermesErrorClassifier.isTransient(.auth), "auth should not retry")
            check(!HermesErrorClassifier.isTransient(.http(500)), "http should not retry")
            check(!HermesErrorClassifier.isTransient(.unknown), "unknown should not retry")
        },
        TestCase(name: "all unreachable URL codes classify as offline") {
            for code in [NSURLErrorCannotConnectToHost,
                         NSURLErrorCannotFindHost,
                         NSURLErrorDNSLookupFailed,
                         NSURLErrorNotConnectedToInternet] {
                checkEqual(HermesErrorClassifier.classify(urlErrorCode: code, midStream: false),
                           .offline, "code \(code) before stream")
            }
        },
        TestCase(name: "unrecognized URL code: unknown before stream, drop mid-stream") {
            // NSURLErrorBadServerResponse is not specially handled.
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorBadServerResponse, midStream: false),
                .unknown)
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorBadServerResponse, midStream: true),
                .streamDropped)
        },
        TestCase(name: "timeout stays timeout regardless of stream phase") {
            checkEqual(
                HermesErrorClassifier.classify(urlErrorCode: NSURLErrorTimedOut, midStream: true),
                .timeout)
        },
        TestCase(name: "http kind carries the original status code") {
            checkEqual(HermesErrorClassifier.classify(statusCode: 429), .http(429))
            checkEqual(HermesErrorClassifier.classify(statusCode: 503), .http(503))
        },
    ]
}
