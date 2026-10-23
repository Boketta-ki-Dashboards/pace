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

/// Uhrzeit einer Erinnerung (Stunde 0–23, Minute 0–59) in der Zeitzone des Geräts.
public struct ReminderTime: Codable, Hashable, Comparable, Sendable, Identifiable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public var id: Int { minutesOfDay }

    /// Minuten seit Mitternacht.
    public var minutesOfDay: Int { hour * 60 + minute }

    public static func < (lhs: ReminderTime, rhs: ReminderTime) -> Bool {
        lhs.minutesOfDay < rhs.minutesOfDay
    }
}

/// Erinnerungen an das persönliche Tagesziel (lokale Mitteilungen) – eine oder mehrere Uhrzeiten am Tag.
///
/// Gespeichert werden zusätzlich `hour`/`minute` der ersten Uhrzeit, damit ältere App-Versionen die Einstellung weiter
/// lesen können; Einstellungen älterer Versionen (nur eine Uhrzeit) werden übernommen.
public struct StreakReminderSettings: Codable, Equatable, Sendable {
    /// Höchstens so viele Uhrzeiten am Tag (kein Mitteilungs-Spam).
    public static let maximumTimes = 6
    public static let defaultTime = ReminderTime(hour: 19, minute: 0)

    public var isEnabled: Bool
    /// Aufsteigend sortiert, ohne Doppelte, mindestens eine.
    public private(set) var times: [ReminderTime]

    public init(isEnabled: Bool = false, times: [ReminderTime]) {
        self.isEnabled = isEnabled
        self.times = Self.normalized(times)
    }

    public init(isEnabled: Bool = false, hour: Int = 19, minute: Int = 0) {
        self.init(isEnabled: isEnabled, times: [ReminderTime(hour: hour, minute: minute)])
    }

    /// Erste Uhrzeit (für ältere Anzeigen und Versionen).
    public var hour: Int { times[0].hour }
    public var minute: Int { times[0].minute }

    public var canAddTime: Bool { times.count < Self.maximumTimes }

    /// Fügt eine Uhrzeit hinzu (doppelte und über das Maximum hinaus werden ignoriert).
    public mutating func add(_ time: ReminderTime) {
        guard canAddTime else { return }
        times = Self.normalized(times + [time])
    }

    /// Entfernt eine Uhrzeit; die letzte verbleibende bleibt erhalten.
    public mutating func remove(_ time: ReminderTime) {
        guard times.count > 1 else { return }
        times = Self.normalized(times.filter { $0 != time })
    }

    /// Ersetzt eine Uhrzeit (z. B. nach dem Bearbeiten in der Zeitauswahl).
    public mutating func replace(_ old: ReminderTime, with new: ReminderTime) {
        guard let index = times.firstIndex(of: old) else { return }
        var updated = times
        updated[index] = new
        times = Self.normalized(updated)
    }

    /// Vorschlag für eine weitere Uhrzeit: mittig in der größten Lücke zwischen 8 und 21 Uhr.
    public var suggestedNextTime: ReminderTime {
        let candidates = [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 12, minute: 30), ReminderTime(hour: 16, minute: 0),
                          ReminderTime(hour: 19, minute: 0), ReminderTime(hour: 21, minute: 0), ReminderTime(hour: 10, minute: 0),
                          ReminderTime(hour: 14, minute: 0), ReminderTime(hour: 18, minute: 0)]
        return candidates.first { !times.contains($0) } ?? ReminderTime(hour: 20, minute: 30)
    }

    private static func normalized(_ times: [ReminderTime]) -> [ReminderTime] {
        let unique = Array(Set(times)).sorted()
        return unique.isEmpty ? [defaultTime] : Array(unique.prefix(maximumTimes))
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, times, hour, minute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        if let times = try? container.decodeIfPresent([ReminderTime].self, forKey: .times), !times.isEmpty {
            self.init(isEnabled: isEnabled, times: times)
        } else {
            let hour = (try? container.decodeIfPresent(Int.self, forKey: .hour)) ?? Self.defaultTime.hour
            let minute = (try? container.decodeIfPresent(Int.self, forKey: .minute)) ?? Self.defaultTime.minute
            self.init(isEnabled: isEnabled, hour: hour, minute: minute)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(times, forKey: .times)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
    }
}

/// Einstellungen, die nur auf dem Gerät gespeichert werden.
public struct AppPreferences: Codable, Equatable, Sendable {
    public var appearance: AppearancePreference
    public var language: LanguagePreference
    public var streakReminder: StreakReminderSettings
    /// Tag, an dem zuletzt „Geschafft!“ gemeldet wurde (höchstens einmal am Tag).
    public var goalReachedNotifiedOn: LocalDate?
    /// Hinweis auf neue Chatnachrichten, solange Pace läuft (kein Push bei geschlossener App).
    public var chatMessageHints: Bool

    public init(
        appearance: AppearancePreference = .automatic,
        language: LanguagePreference = .system,
        streakReminder: StreakReminderSettings = StreakReminderSettings(),
        goalReachedNotifiedOn: LocalDate? = nil,
        chatMessageHints: Bool = true
    ) {
        self.appearance = appearance
        self.language = language
        self.streakReminder = streakReminder
        self.goalReachedNotifiedOn = goalReachedNotifiedOn
        self.chatMessageHints = chatMessageHints
    }

    private enum CodingKeys: String, CodingKey {
        case appearance, language, streakReminder, goalReachedNotifiedOn, chatMessageHints
    }

    // Unbekannte oder fehlende Werte (z. B. aus einer neueren Version) fallen auf den Standard zurück.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? container.decodeIfPresent(AppearancePreference.self, forKey: .appearance)) ?? .automatic
        language = (try? container.decodeIfPresent(LanguagePreference.self, forKey: .language)) ?? .system
        streakReminder = (try? container.decodeIfPresent(StreakReminderSettings.self, forKey: .streakReminder)) ?? StreakReminderSettings()
        goalReachedNotifiedOn = try? container.decodeIfPresent(LocalDate.self, forKey: .goalReachedNotifiedOn)
        chatMessageHints = (try? container.decodeIfPresent(Bool.self, forKey: .chatMessageHints)) ?? true
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

    public var goalReachedNotifiedOn: LocalDate? {
        get { preferences.goalReachedNotifiedOn }
        set { update { $0.goalReachedNotifiedOn = newValue } }
    }

    public var chatMessageHints: Bool {
        get { preferences.chatMessageHints }
        set { update { $0.chatMessageHints = newValue } }
    }

    /// Die tatsächlich verwendete Sprache (bei „Automatisch“ die passende Gerätesprache).
    public var resolvedLanguage: AppLanguage {
        preferences.language.resolved(preferredLanguages: preferredLanguages())
    }

    /// Sprache, die bei „Wie iPhone“ gilt (passend zu den bevorzugten Sprachen des Geräts).
    public var systemLanguage: AppLanguage {
        LanguagePreference.system.resolved(preferredLanguages: preferredLanguages())
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
