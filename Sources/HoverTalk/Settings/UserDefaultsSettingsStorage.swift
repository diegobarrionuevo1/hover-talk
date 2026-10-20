import Foundation
import HoverTalkCore

/// Keeps `Preferences` in a `UserDefaults` domain, the app's own for `.standard`.
struct UserDefaultsSettingsStorage: SettingsStorage {
    let defaults: UserDefaults

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
