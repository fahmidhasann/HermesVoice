import Foundation

/// Categorized failure reason for a Hermes request, used to drive friendly
/// guidance, the connection indicator, and retry decisions.
public enum HermesErrorKind: Equatable, Sendable {
    /// The gateway can't be reached at all (connection refused / DNS).
    case offline
    /// Authentication/authorization failure (401/403).
    case auth
    /// Some other non-2xx HTTP status.
    case http(Int)
    /// The connection dropped after the response started streaming.
    case streamDropped
    /// The request timed out.
    case timeout
    /// Anything we couldn't classify.
    case unknown
}

/// Pure mapping from raw HTTP status / `URLError` codes to `HermesErrorKind`,
/// kept hardware-free so it can be unit-tested.
public enum HermesErrorClassifier {
    /// Classify a non-2xx HTTP status code.
    public static func classify(statusCode: Int) -> HermesErrorKind {
        switch statusCode {
        case 401, 403: return .auth
        default:       return .http(statusCode)
        }
    }

    /// Classify a `URLError` by its numeric code. `midStream` distinguishes a
    /// connection that never opened (offline) from one lost while streaming.
    public static func classify(urlErrorCode: Int, midStream: Bool) -> HermesErrorKind {
        switch urlErrorCode {
        case NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet:
            return .offline
        case NSURLErrorNetworkConnectionLost:
            return midStream ? .streamDropped : .offline
        case NSURLErrorTimedOut:
            return .timeout
        default:
            return midStream ? .streamDropped : .unknown
        }
    }

    /// Whether a failure is worth retrying automatically.
    public static func isTransient(_ kind: HermesErrorKind) -> Bool {
        switch kind {
        case .offline, .streamDropped, .timeout: return true
        case .auth, .http, .unknown:             return false
        }
    }
}
