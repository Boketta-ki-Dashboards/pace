import Foundation
import Observation
import PaceCore

/// Arten von Modulen auf dem Home-Dashboard. Neue Module (z. B. Challenges) kommen als weiterer Fall hinzu.
public enum HomeModuleKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case regionRanks
    case stepsToday
    case week
    case streak
    case neighborhood
    case friends
    case groups

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .regionRanks: "Platzierungen"
        case .stepsToday: "Deine Schritte heute"
        case .week: "Deine Woche"
        case .streak: "Deine Serie"
        case .neighborhood: "Dein Umfeld"
        case .friends: "Deine Freunde"
        case .groups: "Deine Gruppen"
        }
    }

    /// Kurze Beschreibung für „Modul hinzufügen“.
    public var summary: String {
        switch self {
        case .regionRanks: "Dein Platz in Gemeinde, Kreis, Bundesland und Land"
        case .stepsToday: "Schritte, Tagesziel, Distanz und Kalorien"
        case .week: "Montag bis Sonntag auf einen Blick"
        case .streak: "Tage in Folge mit erreichtem Tagesziel"
        case .neighborhood: "Wer direkt vor und hinter dir liegt"
        case .friends: "Rangliste mit deinen Freunden"
        case .groups: "Deine Gruppen und ihre Serien"
        }
    }

    public var systemImage: String {
        switch self {
        case .regionRanks: "trophy"
        case .stepsToday: "figure.walk"
        case .week: "calendar"
        case .streak: "flame"
        case .neighborhood: "person.3.sequence"
        case .friends: "person.2"
        case .groups: "person.3"
        }
    }

    /// Die Schrittkarte ist der Kern des Dashboards: immer vorhanden und nie klein.
    public var isRemovable: Bool {
        self != .stepsToday
    }

    public var supportedSizes: [HomeModuleSize] {
        self == .stepsToday ? [.medium, .large] : HomeModuleSize.allCases
    }

    public var defaultSize: HomeModuleSize { .medium }

    /// Module, die mehrfach vorkommen dürfen (z. B. Umfeld in Gemeinde und im Kreis).
    public var allowsMultiple: Bool {
        self == .neighborhood
    }

    /// Ob das Modul eine Ranking-Ebene braucht.
    public var usesRegionScope: Bool {
        self == .neighborhood
    }
}

/// Größe eines Moduls. Klein zeigt das Wichtigste in einer Zeile, groß zusätzliche Details.
public enum HomeModuleSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Klein"
        case .medium: "Mittel"
        case .large: "Groß"
        }
    }
}

/// Ein Modul auf dem Dashboard mit Größe und – je nach Art – gewählter Ranking-Ebene.
public struct HomeModule: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var kind: HomeModuleKind
    public var size: HomeModuleSize
    /// Ebene des Rankings für „Dein Umfeld“; `nil` für alle anderen Module.
    public var regionLevel: RegionLevel?

    public init(id: String = UUID().uuidString, kind: HomeModuleKind, size: HomeModuleSize? = nil, regionLevel: RegionLevel? = nil) {
        self.id = id
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.regionLevel = kind.usesRegionScope ? (regionLevel ?? .municipality) : nil
    }

    /// Zeilen im Umfeld-Modul: klein nur der eigene Platz, mittel drei, groß fünf.
    public var neighborhoodRows: Int {
        switch size {
        case .small: 1
        case .medium: 3
        case .large: 5
        }
    }

    /// Wie viele Plätze über und unter dem eigenen geladen werden müssen, damit auch Platz 1 und der Letzte volle
    /// Zeilen haben. Klein braucht den Platz darüber für „Noch … Schritte bis Platz …“.
    public var neighborhoodRadius: Int {
        size == .small ? 1 : neighborhoodRows - 1
    }

    /// z. B. `Mittel · Gemeinde` für „Anpassen“.
    public var detailText: String {
        guard let regionLevel else { return size.title }
        return "\(size.title) · \(regionLevel.scopeTitle)"
    }
}

public extension RegionLevel {
    /// Bezeichnung der Ebene für die Modulauswahl.
    var scopeTitle: String {
        switch self {
        case .municipality: "Gemeinde"
        case .district: "Kreis"
        case .state: "Bundesland"
        case .country: "Deutschland"
        }
    }
}

/// Persönliche Einstellungen des Home-Dashboards. Bleiben auf dem Gerät.
///
/// Version 2 speichert Module (Art, Größe, Ebene) statt ein- und ausblendbarer Bereiche. Gespeicherte Einstellungen
/// der Version 1 werden beim Laden übernommen: sichtbare Bereiche in derselben Reihenfolge, dazu die neue Serie.
public struct HomePreferences: Equatable, Sendable {
    public var modules: [HomeModule]
    /// Tagesziel aus Version 1. Das Ziel steht inzwischen im Zielverlauf (`StepGoalSettings`); der Wert wird nur
    /// einmalig dorthin übernommen.
    public var legacyStepGoal: Int?

    public init(modules: [HomeModule] = Self.defaultModules(), legacyStepGoal: Int? = nil) {
        self.modules = modules
        self.legacyStepGoal = legacyStepGoal
    }

    /// Standard-Layout für neue Nutzer.
    public static func defaultModules() -> [HomeModule] {
        [.regionRanks, .stepsToday, .week, .streak, .neighborhood, .friends, .groups].map { HomeModule(kind: $0) }
    }

    /// Repariert gespeicherte Werte: doppelte IDs und mehrfach vorhandene Einzelmodule entfallen, nicht erlaubte
    /// Größen werden zurückgesetzt, Umfeld-Module haben immer eine Ebene, die Schrittkarte ist immer vorhanden.
    public func normalized() -> HomePreferences {
        var seenIDs: Set<String> = []
        var seenKinds: Set<HomeModuleKind> = []
        var result: [HomeModule] = []
        for module in modules {
            guard seenIDs.insert(module.id).inserted else { continue }
            guard module.kind.allowsMultiple || seenKinds.insert(module.kind).inserted else { continue }
            let size = module.kind.supportedSizes.contains(module.size) ? module.size : module.kind.defaultSize
            result.append(HomeModule(id: module.id, kind: module.kind, size: size, regionLevel: module.regionLevel))
        }
        if !result.contains(where: { $0.kind == .stepsToday }) {
            let index = result.firstIndex { $0.kind == .regionRanks }.map { $0 + 1 } ?? 0
            result.insert(HomeModule(kind: .stepsToday), at: index)
        }
        return HomePreferences(modules: result, legacyStepGoal: legacyStepGoal)
    }
}

extension HomePreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case modules
        case legacyStepGoal = "stepGoal"
        case sections
    }

    /// Bereich aus Version 1.
    private struct LegacySection: Decodable {
        let section: String
        let isVisible: Bool
    }

    /// Überspringt Module unbekannter Art (z. B. aus einer neueren App-Version), statt alles zu verwerfen.
    private struct LossyModule: Decodable {
        let module: HomeModule?

        init(from decoder: Decoder) throws {
            module = try? HomeModule(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyStepGoal = try container.decodeIfPresent(Int.self, forKey: .legacyStepGoal)
        if let modules = try container.decodeIfPresent([LossyModule].self, forKey: .modules) {
            self.init(modules: modules.compactMap(\.module), legacyStepGoal: legacyStepGoal)
            return
        }
        let sections = try container.decodeIfPresent([LegacySection].self, forKey: .sections) ?? []
        self.init(modules: Self.migrated(sections), legacyStepGoal: legacyStepGoal)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .version)
        try container.encode(modules, forKey: .modules)
        try container.encodeIfPresent(legacyStepGoal, forKey: .legacyStepGoal)
    }

    /// Version 1 → 2: sichtbare Bereiche in Nutzer-Reihenfolge als mittlere Module, die neue Serie nach der Woche.
    private static func migrated(_ sections: [LegacySection]) -> [HomeModule] {
        var modules = sections
            .filter { $0.isVisible || $0.section == HomeModuleKind.stepsToday.rawValue }
            .compactMap { HomeModuleKind(rawValue: $0.section) }
            .map { HomeModule(kind: $0) }
        guard !modules.isEmpty else { return defaultModules() }
        let anchor = modules.firstIndex { $0.kind == .week } ?? modules.firstIndex { $0.kind == .stepsToday }
        modules.insert(HomeModule(kind: .streak), at: anchor.map { $0 + 1 } ?? modules.count)
        return modules
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

/// Aufbau des Dashboards, live für alle Ansichten.
@MainActor
@Observable
public final class HomeSettings {
    public private(set) var preferences: HomePreferences

    @ObservationIgnored private let store: any HomePreferencesStoring

    public init(store: any HomePreferencesStoring) {
        self.store = store
        preferences = (store.load() ?? HomePreferences()).normalized()
    }

    /// Alle Module in Nutzer-Reihenfolge.
    public var modules: [HomeModule] { preferences.modules }

    /// Module, die sich (noch) hinzufügen lassen.
    public var addableKinds: [HomeModuleKind] {
        HomeModuleKind.allCases.filter { kind in
            kind.allowsMultiple || !preferences.modules.contains { $0.kind == kind }
        }
    }

    /// Plätze über und unter dem eigenen, die je Ebene für Umfeld-Module geladen werden müssen.
    public var neighborhoodRadii: [RegionLevel: Int] {
        preferences.modules
            .filter { $0.kind == .neighborhood }
            .reduce(into: [:]) { radii, module in
                guard let level = module.regionLevel else { return }
                radii[level] = max(radii[level] ?? 0, module.neighborhoodRadius)
            }
    }

    /// Ob ein Modul Platzierungen anzeigt (sonst werden keine geladen).
    public var showsStandings: Bool {
        preferences.modules.contains { $0.kind == .regionRanks || $0.kind == .neighborhood }
    }

    @discardableResult
    public func add(_ kind: HomeModuleKind) -> HomeModule? {
        guard addableKinds.contains(kind) else { return nil }
        let module = HomeModule(kind: kind)
        update { $0.modules.append(module) }
        return module
    }

    public func remove(_ id: HomeModule.ID) {
        update { preferences in
            preferences.modules.removeAll { $0.id == id && $0.kind.isRemovable }
        }
    }

    public func setSize(_ size: HomeModuleSize, for id: HomeModule.ID) {
        update { preferences in
            guard let index = preferences.modules.firstIndex(where: { $0.id == id }),
                  preferences.modules[index].kind.supportedSizes.contains(size)
            else { return }
            preferences.modules[index].size = size
        }
    }

    public func setRegionLevel(_ level: RegionLevel, for id: HomeModule.ID) {
        update { preferences in
            guard let index = preferences.modules.firstIndex(where: { $0.id == id }),
                  preferences.modules[index].kind.usesRegionScope
            else { return }
            preferences.modules[index].regionLevel = level
        }
    }

    /// Verschiebt Module wie `List.onMove`.
    public func moveModules(fromOffsets source: IndexSet, toOffset destination: Int) {
        update { preferences in
            let moving = source.sorted().map { preferences.modules[$0] }
            var remaining = preferences.modules.enumerated().filter { !source.contains($0.offset) }.map(\.element)
            let insertion = destination - source.filter { $0 < destination }.count
            remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
            preferences.modules = remaining
        }
    }

    public func resetLayout() {
        update { $0.modules = HomePreferences.defaultModules() }
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
