import Foundation
import HermesVoiceKit

class Config {
    static let shared = Config()

    let apiEndpoint: URL
    let healthEndpoint: URL
    let apiKey: String
    /// Sent on every request so Hermes can attribute traffic to this client.
    let userAgent: String

    private init() {
        let baseURL = "http://127.0.0.1:8642"
        apiEndpoint = URL(string: "\(baseURL)/v1/chat/completions")!
        healthEndpoint = URL(string: "\(baseURL)/v1/health")!

        // Load API key from ~/.hermes/.env
        apiKey = Config.loadAPIKey()

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        userAgent = "HermesVoice/\(version)"
    }
    
    private static func loadAPIKey() -> String {
        let envPath = NSString("~/.hermes/.env").expandingTildeInPath
        
        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            print("HermesVoice: Warning - Could not read ~/.hermes/.env")
            return ""
        }
        
        if let key = APIKeyParser.parse(env: contents) {
            return key
        }

        print("HermesVoice: Warning - API_SERVER_KEY not found in ~/.hermes/.env")
        return ""
    }
}
