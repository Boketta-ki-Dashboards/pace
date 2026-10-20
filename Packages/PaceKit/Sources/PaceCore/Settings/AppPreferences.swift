import Foundation
import Observation

/// Darstellung der App.
public enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Folgt der Einstellung des iPhones.
    case automatic
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: PaceLocalization.text(de: "Automatisch", en: "Automatic", ru: "Автоматически")
        case .light: PaceLocalization.text(de: "Hell", en: "Light", ru: "Светлая")
        case .dark: PaceLocalization.text(de: "Dunkel", en: "Dark", ru: "Тёмная")
        }
    }
}

/// Tägliche Erinnerung an das persönliche Tagesziel (lokale Mitteilung).
public struct StreakReminderSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Uhrzeit (Stunde 0–23, Minute 0–59) in der Zeitzone des Geräts.
    public var hour: Int
    public var minute: Int

    public init(isEnabled: Bool = false, hour: Int = 19, minute: Int = 0) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
}

/// Einstellungen, die nur auf dem Gerät gespeichert werden.
public struct AppPreferences: Codable, Equatable, Sendable {
    public var appearance: AppearancePreference
    public var language: LanguagePreference
    public var streakReminder: StreakReminderSettings

    public init(
        appearance: AppearancePreference = .automatic,
        language: LanguagePreference = .system,
        streakReminder: StreakReminderSettings = StreakReminderSettings()
    ) {
        self.appearance = appearance
        self.language = language
        self.streakReminder = streakReminder
    }

    private enum CodingKeys: String, CodingKey {
        case appearance, language, streakReminder
    }

    // Unbekannte oder fehlende Werte (z. B. aus einer neueren Version) fallen auf den Standard zurück.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? container.decodeIfPresent(AppearancePreference.self, forKey: .appearance)) ?? .automatic
        language = (try? container.decodeIfPresent(LanguagePreference.self, forKey: .language)) ?? .system
        streakReminder = (try? container.decodeIfPresent(StreakReminderSettings.self, forKey: .streakReminder)) ?? StreakReminderSettings()
    }
}

public protocol AppPreferencesStoring: Sendable {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences)
}

/// Speichert die Einstellungen als JSON in den `UserDefaults` (Schlüssel `pace.preferences`).
public struct UserDefaultsAppPreferencesStore: AppPreferencesStoring {
    private let suiteName: String?
    private static let key = "pace.preferences"

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return AppPreferences() }
        return preferences
    }

    public func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

public final class InMemoryAppPreferencesStore: AppPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppPreferences

    public init(_ preferences: AppPreferences = AppPreferences()) {
        stored = preferences
    }

    public func load() -> AppPreferences {
        lock.withLock { stored }
    }

    public func save(_ preferences: AppPreferences) {
        lock.withLock { stored = preferences }
    }
}

/// Beobachtbare Einstellungen für die Oberfläche. Änderungen werden sofort gespeichert und – bei der Sprache – direkt
/// angewendet.
@MainActor
@Observable
public final class AppSettings {
    public private(set) var preferences: AppPreferences

    @ObservationIgnored private let store: any AppPreferencesStoring
    @ObservationIgnored private let preferredLanguages: @Sendable () -> [String]
    @ObservationIgnored private let languageSink: @MainActor (AppLanguage) -> Void

    /// - Parameters:
    ///   - preferredLanguages: Bevorzugte Sprachen des Geräts (bei „Wie iPhone“). Enthält auch die Sprache, die in den
    ///     iOS-Einstellungen nur für Pace gewählt wurde.
    ///   - applyLanguage: Wendet die Sprache an; Standard ist die Sprache der ganzen App (`PaceLocalization.shared`).
    ///     Tests übergeben hier einen Rekorder, damit parallel laufende Tests nicht die App-Sprache wechseln.
    public init(
        store: any AppPreferencesStoring,
        preferredLanguages: @escaping @Sendable () -> [String] = { Locale.preferredLanguages },
        applyLanguage: @escaping @MainActor (AppLanguage) -> Void = { PaceLocalization.shared.language = $0 }
    ) {
        self.store = store
        self.preferredLanguages = preferredLanguages
        languageSink = applyLanguage
        preferences = store.load()
        self.applyLanguage()
    }

    public var appearance: AppearancePreference {
        get { preferences.appearance }
        set { update { $0.appearance = newValue } }
    }

    public var language: LanguagePreference {
        get { preferences.language }
        set {
            update { $0.language = newValue }
            applyLanguage()
        }
    }

    public var streakReminder: StreakReminderSettings {
        get { preferences.streakReminder }
        set { update { $0.streakReminder = newValue } }
    }

    /// Die tatsächlich verwendete Sprache (bei „Automatisch“ die passende Gerätesprache).
    public var resolvedLanguage: AppLanguage {
        preferences.language.resolved(preferredLanguages: preferredLanguages())
    }

    /// Setzt alles auf den Ausgangszustand zurück (z. B. nach dem Löschen des Kontos).
    public func reset() {
        update { $0 = AppPreferences() }
        applyLanguage()
    }

    private func update(_ change: (inout AppPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        preferences = updated
        store.save(updated)
    }

    private func applyLanguage() {
        languageSink(resolvedLanguage)
    }
}
