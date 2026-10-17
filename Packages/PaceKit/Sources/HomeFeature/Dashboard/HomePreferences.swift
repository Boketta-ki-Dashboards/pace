import Foundation
import Observation

/// Bereiche des Home-Dashboards. Die Reihenfolge und Sichtbarkeit wählt der Nutzer über „Anpassen“.
public enum HomeSection: String, Codable, CaseIterable, Sendable, Identifiable {
    case regionRanks
    case stepsToday
    case week
    case neighborhood
    case friends
    case groups

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .regionRanks: "Platzierungen"
        case .stepsToday: "Deine Schritte heute"
        case .week: "Deine Woche"
        case .neighborhood: "Dein Umfeld"
        case .friends: "Deine Freunde"
        case .groups: "Deine Gruppen"
        }
    }

    public var systemImage: String {
        switch self {
        case .regionRanks: "trophy"
        case .stepsToday: "figure.walk"
        case .week: "calendar"
        case .neighborhood: "person.3.sequence"
        case .friends: "person.2"
        case .groups: "person.3"
        }
    }

    /// Die Schrittkarte ist der Kern des Dashboards und bleibt immer sichtbar.
    public var canBeHidden: Bool {
        self != .stepsToday
    }
}

public struct HomeSectionSetting: Codable, Equatable, Sendable, Identifiable {
    public let section: HomeSection
    public var isVisible: Bool

    public init(section: HomeSection, isVisible: Bool) {
        self.section = section
        self.isVisible = isVisible
    }

    public var id: HomeSection { section }
}

/// Persönliche Einstellungen des Home-Dashboards. Bleiben auf dem Gerät.
public struct HomePreferences: Codable, Equatable, Sendable {
    public static let defaultStepGoal = 10_000
    public static let stepGoalRange = 1_000...50_000
    public static let stepGoalIncrement = 500

    public var stepGoal: Int
    public var sections: [HomeSectionSetting]

    public init(stepGoal: Int = Self.defaultStepGoal, sections: [HomeSectionSetting] = Self.defaultSections) {
        self.stepGoal = stepGoal
        self.sections = sections
    }

    public static let defaultSections = HomeSection.allCases.map { HomeSectionSetting(section: $0, isVisible: true) }

    /// Repariert gespeicherte Werte: unbekannte oder doppelte Bereiche entfallen, neue kommen ans Ende, die
    /// Schrittkarte ist immer sichtbar, das Ziel liegt im erlaubten Bereich.
    public func normalized() -> HomePreferences {
        var seen: Set<HomeSection> = []
        var result: [HomeSectionSetting] = []
        for setting in sections where seen.insert(setting.section).inserted {
            result.append(HomeSectionSetting(section: setting.section, isVisible: setting.isVisible || !setting.section.canBeHidden))
        }
        for section in HomeSection.allCases where !seen.contains(section) {
            result.append(HomeSectionSetting(section: section, isVisible: true))
        }
        return HomePreferences(stepGoal: Self.clampedGoal(stepGoal), sections: result)
    }

    /// Ziel im erlaubten Bereich, gerundet auf 500er-Schritte.
    public static func clampedGoal(_ goal: Int) -> Int {
        let clamped = min(max(goal, stepGoalRange.lowerBound), stepGoalRange.upperBound)
        return (clamped + stepGoalIncrement / 2) / stepGoalIncrement * stepGoalIncrement
    }
}

/// Speichert die Home-Einstellungen.
public protocol HomePreferencesStoring: Sendable {
    func load() -> HomePreferences?
    func save(_ preferences: HomePreferences)
}

/// Speichert die Home-Einstellungen als JSON in den `UserDefaults`.
public struct UserDefaultsHomePreferencesStore: HomePreferencesStoring {
    private let suiteName: String?
    private let key = "pace.home.preferences"

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load() -> HomePreferences? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HomePreferences.self, from: data)
    }

    public func save(_ preferences: HomePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

/// Tagesziel und Aufbau des Dashboards, live für alle Ansichten.
@MainActor
@Observable
public final class HomeSettings {
    public private(set) var preferences: HomePreferences

    @ObservationIgnored private let store: any HomePreferencesStoring

    public init(store: any HomePreferencesStoring) {
        self.store = store
        preferences = (store.load() ?? HomePreferences()).normalized()
    }

    public var stepGoal: Int { preferences.stepGoal }

    /// Alle Bereiche in Nutzer-Reihenfolge, auch ausgeblendete (für „Anpassen“).
    public var sections: [HomeSectionSetting] { preferences.sections }

    /// Die angezeigten Bereiche in Nutzer-Reihenfolge.
    public var visibleSections: [HomeSection] {
        preferences.sections.filter(\.isVisible).map(\.section)
    }

    /// Mögliche Tagesziele in 500er-Schritten.
    public static let stepGoalOptions = Array(stride(
        from: HomePreferences.stepGoalRange.lowerBound,
        through: HomePreferences.stepGoalRange.upperBound,
        by: HomePreferences.stepGoalIncrement
    ))

    public func setStepGoal(_ goal: Int) {
        update { $0.stepGoal = HomePreferences.clampedGoal(goal) }
    }

    public func setVisible(_ isVisible: Bool, for section: HomeSection) {
        guard section.canBeHidden || isVisible else { return }
        update { preferences in
            guard let index = preferences.sections.firstIndex(where: { $0.section == section }) else { return }
            preferences.sections[index].isVisible = isVisible
        }
    }

    /// Verschiebt Bereiche wie `List.onMove`.
    public func moveSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        update { preferences in
            let moving = source.sorted().map { preferences.sections[$0] }
            var remaining = preferences.sections.enumerated().filter { !source.contains($0.offset) }.map(\.element)
            let insertion = destination - source.filter { $0 < destination }.count
            remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
            preferences.sections = remaining
        }
    }

    public func resetLayout() {
        update { $0.sections = HomePreferences.defaultSections }
    }

    private func update(_ change: (inout HomePreferences) -> Void) {
        var updated = preferences
        change(&updated)
        updated = updated.normalized()
        guard updated != preferences else { return }
        preferences = updated
        store.save(updated)
    }
}

/// Hält die Home-Einstellungen nur im Speicher – für Vorschauen und Tests.
public final class InMemoryHomePreferencesStore: HomePreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HomePreferences?

    public init(_ preferences: HomePreferences? = nil) {
        stored = preferences
    }

    public func load() -> HomePreferences? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func save(_ preferences: HomePreferences) {
        lock.lock()
        defer { lock.unlock() }
        stored = preferences
    }
}
