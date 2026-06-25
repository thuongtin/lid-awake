import LidAwakeCore
import Foundation

final class SettingsStore {
    private let key = "LidAwake.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(UserSettings.self, from: data)
        else {
            return .defaults
        }

        return settings
    }

    func save(_ settings: UserSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
