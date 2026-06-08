import Foundation
import HermesVoiceKit

class Config {
    static let shared = Config()

    let apiEndpoint: URL
    let healthEndpoint: URL
    /// Sent on every request so Hermes can attribute traffic to this client.
    let userAgent: String

    private init() {
        let baseURL = "http://127.0.0.1:8642"
        apiEndpoint = URL(string: "\(baseURL)/v1/chat/completions")!
        healthEndpoint = URL(string: "\(baseURL)/v1/health")!

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        userAgent = "HermesVoice/\(version)"
    }

    /// One-time migration of a pre-Keychain credential. Early builds read the API
    /// key from `~/.hermes/.env` on every launch; it now lives in the Keychain
    /// (entered via onboarding/Settings, see `CredentialsStore`). On launch, if
    /// the Keychain has no key but a legacy `.env` does, import it once so
    /// upgraders keep working without re-entering it. Idempotent: a no-op as soon
    /// as a key is present in the Keychain.
    static func migrateLegacyAPIKeyIfNeeded() {
        guard CredentialsStore.current() == nil else { return }

        let envPath = NSString("~/.hermes/.env").expandingTildeInPath
        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8),
              let key = APIKeyParser.parse(env: contents), !key.isEmpty else {
            return
        }
        CredentialsStore.save(key)
    }
}
