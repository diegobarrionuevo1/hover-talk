/// Where `Preferences` keeps its values: `UserDefaults` in the app, `InMemorySettingsStorage`
/// in tests.
public protocol SettingsStorage {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

/// Settings kept in memory only, for tests and previews.
public final class InMemorySettingsStorage: SettingsStorage {
    private var values: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        values[key]
    }

    public func setString(_ value: String, forKey key: String) {
        values[key] = value
    }
}

/// The user's settings, read from and written to a `SettingsStorage` on every access, so
/// several owners of one storage always see the same values.
@MainActor
public final class Preferences {
    public static let readingModeKey = "readingMode"

    private let storage: any SettingsStorage

    public init(storage: any SettingsStorage) {
        self.storage = storage
    }

    /// Stored as the mode's raw value; `ReadingMode.default` while nothing is stored, or when
    /// the stored value is not a mode this version knows.
    public var readingMode: ReadingMode {
        get { storage.string(forKey: Self.readingModeKey).flatMap(ReadingMode.init(rawValue:)) ?? .default }
        set { storage.setString(newValue.rawValue, forKey: Self.readingModeKey) }
    }
}
