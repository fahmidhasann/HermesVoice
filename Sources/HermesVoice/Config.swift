import Foundation
import HermesVoiceKit

class Config {
    static let shared = Config()
    
    let apiEndpoint: URL
    let apiKey: String
    let sessionId: String
    
    private init() {
        // API endpoint
        apiEndpoint = URL(string: "http://127.0.0.1:8642/v1/chat/completions")!
        
        // Load API key from ~/.hermes/.env
        apiKey = Config.loadAPIKey()
        
        // Session ID - persisted in UserDefaults
        if let existingId = UserDefaults.standard.string(forKey: "hermesSessionId") {
            sessionId = existingId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "hermesSessionId")
            sessionId = newId
        }
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
