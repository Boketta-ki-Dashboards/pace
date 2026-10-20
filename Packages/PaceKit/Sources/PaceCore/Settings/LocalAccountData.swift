import Foundation

/// Alle Daten, die Pace nur auf diesem iPhone speichert (Einstellungen, Tagesziel-Verlauf, Rekord, Home-Aufbau,
/// Profil-Zwischenspeicher) – für den Datenexport und zum Löschen nach dem Löschen des Kontos.
///
/// Gesundheitsdaten gehören nicht dazu: Sie liegen in Apple Health und werden von Pace nicht gespeichert. Die
/// Anmeldung (Schlüsselbund) entfernt `AuthProviding.signOut()`.
public protocol LocalAccountDataStoring: Sendable {
    /// Gespeicherte Abschnitte als JSON, z. B. `settings`, `stepGoalHistory`, `homeLayout`.
    func exportSections() -> [LocalDataSection]
    /// Entfernt alle lokal gespeicherten Pace-Daten.
    func eraseAll()
}

/// Ein Abschnitt der lokal gespeicherten Daten.
public struct LocalDataSection: Equatable, Sendable {
    /// Lesbarer Name im Export, z. B. `stepGoalHistory`.
    public let name: String
    /// JSON-Wert (Objekt, Liste oder einfacher Wert).
    public let json: Data

    public init(name: String, json: Data) {
        self.name = name
        self.json = json
    }
}

/// Lokale Daten in den `UserDefaults`: Alle Stores von Pace speichern unter Schlüsseln mit dem Präfix `pace.`
/// (`pace.preferences`, `pace.goals.steps`, `pace.streak.record`, `pace.home.preferences`, `pace.profile.<id>`).
/// Neue Stores mit diesem Präfix sind dadurch automatisch im Export enthalten und werden mit gelöscht.
public struct UserDefaultsLocalAccountData: LocalAccountDataStoring {
    public static let keyPrefix = "pace."

    /// Lesbare Namen für die bekannten Schlüssel; unbekannte erscheinen unter ihrem Schlüssel.
    static let sectionNames: [String: String] = [
        "pace.preferences": "settings",
        "pace.goals.steps": "stepGoalHistory",
        "pace.streak.record": "streakRecord",
        "pace.home.preferences": "homeLayout",
    ]

    private let suiteName: String?

    /// - Parameter suiteName: `nil` für die Standard-Defaults der App.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func exportSections() -> [LocalDataSection] {
        let defaults = defaults
        return Self.paceKeys(in: defaults).compactMap { key in
            guard let value = defaults.object(forKey: key), let json = Self.json(for: value) else { return nil }
            return LocalDataSection(name: Self.sectionName(for: key), json: json)
        }
        .sorted { $0.name < $1.name }
    }

    public func eraseAll() {
        let defaults = defaults
        for key in Self.paceKeys(in: defaults) {
            defaults.removeObject(forKey: key)
        }
    }

    static func sectionName(for key: String) -> String {
        if let name = sectionNames[key] { return name }
        if key.hasPrefix("pace.profile.") { return "profileCache" }
        return key
    }

    private static func paceKeys(in defaults: UserDefaults) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(keyPrefix) }.sorted()
    }

    /// Die Stores speichern JSON als `Data`; einfache Werte (Zahl, Text, Wahrheitswert) werden als JSON verpackt.
    static func json(for value: Any) -> Data? {
        if let data = value as? Data {
            return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil ? data : nil
        }
        guard JSONSerialization.isValidJSONObject([value]) else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }
}

/// Lokale Daten im Speicher (Tests, Vorschauen).
public final class InMemoryLocalAccountData: LocalAccountDataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var sections: [LocalDataSection]
    private var eraseCount = 0

    public init(_ sections: [LocalDataSection] = []) {
        self.sections = sections
    }

    /// Wie oft gelöscht wurde.
    public var erasures: Int {
        lock.withLock { eraseCount }
    }

    public func exportSections() -> [LocalDataSection] {
        lock.withLock { sections }
    }

    public func eraseAll() {
        lock.withLock {
            sections = []
            eraseCount += 1
        }
    }
}
