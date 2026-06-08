import Foundation
import Combine
import Security

/// Keychain-backed store for the Hermes gateway API key. The key lives in the
/// login Keychain (service `com.hermes.voice`, account `api-server-key`) — never
/// in `UserDefaults`, whose settings JSON is plaintext on disk.
///
/// Shape mirrors `AppSettingsStore`: SwiftUI `SecureField`s bind to the
/// `@Published` `apiKey`, and every edit is written through to the Keychain
/// immediately (`didSet`), so a key typed in onboarding/Settings is live on the
/// next request without a restart. Request-time consumers (the API client, on a
/// background task) read the actor-agnostic `current()` directly, mirroring
/// `AppSettingsStore.loadCurrent()`.
@MainActor
final class CredentialsStore: ObservableObject {
    static let shared = CredentialsStore()

    private nonisolated static let service = "com.hermes.voice"
    private nonisolated static let account = "api-server-key"

    /// The API key bound by SwiftUI. Writing persists to the Keychain at once;
    /// an empty value clears the stored key (no-auth local gateways are valid).
    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            Self.save(apiKey)
        }
    }

    private init() {
        // `didSet` does not fire for assignments in `init`, so this initial load
        // never triggers a redundant write-back.
        apiKey = Self.current() ?? ""
    }

    // MARK: - Keychain primitives (actor-agnostic)
    //
    // The Keychain Services API is thread-safe, so these statics are `nonisolated`
    // and callable from any context (the API client reads `current()` per request
    // off the main actor; `Config` migration writes `save()` at launch).

    /// The stored key, or `nil` when unset/empty.
    nonisolated static func current() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Upsert the key (trimmed). An empty/whitespace value deletes it instead, so
    /// clearing the field really clears the credential.
    nonisolated static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { delete(); return }

        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    /// Remove the stored key (no-op when absent).
    nonisolated static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
