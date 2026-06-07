import Foundation
import Combine
import HermesVoiceKit

/// Single source of truth for user settings, persisted as JSON in `UserDefaults`.
/// SwiftUI observes `settings`; system-level side effects (re-registering the
/// hotkey, appearance, launch-at-login) are applied by `AppDelegate`, which
/// subscribes to changes. (De)serialization lives in `HermesVoiceKit.AppSettings`.
@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    nonisolated static let defaultsKey = "hermesVoiceSettings"

    @Published var settings: AppSettings {
        didSet { Self.persist(settings) }
    }

    private init() {
        settings = Self.loadCurrent()
    }

    /// Synchronous, actor-agnostic read of the persisted settings. `UserDefaults`
    /// is thread-safe, so request-time consumers (the API client, on a background
    /// task) can read host/port/model without hopping to the main actor.
    nonisolated static func loadCurrent() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return .default
        }
        return AppSettings.decode(data)
    }

    nonisolated static func persist(_ settings: AppSettings) {
        UserDefaults.standard.set(AppSettings.encode(settings), forKey: defaultsKey)
    }
}
