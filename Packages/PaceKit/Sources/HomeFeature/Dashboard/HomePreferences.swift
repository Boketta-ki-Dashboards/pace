import Foundation
import PaceCore

/// Arten von Widgets auf dem Home-Dashboard. Neue Widgets (z. B. Challenges) kommen als weiterer Fall hinzu.
///
/// Die Rohwerte werden gespeichert und dürfen sich nicht ändern.
public enum HomeModuleKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Die vier regionalen Platzierungen in einer Reihe (Stadt, Landkreis, Bundesland, Land).
    case regionRanks
    case stepsToday
    case week
    case streak
    /// Ranking-Umfeld einer Ebene („Pfungstadt · Dein Umfeld“).
    case neighborhood
    case friends
    case groups
    /// Eine Kennzahl (Schritte, Distanz, aktive Kalorien) mit Verlauf der letzten sieben Tage.
    case activity
    /// Kompakter Kalender mit erreichten Tageszielen.
    case calendar

    public var id: String { rawValue }

    /// Standardtitel des Widgets.
    public var title: String {
        switch self {
        case .regionRanks:
            PaceLocalization.text(de: "Deine Positionen in der Region", en: "Your regional positions", ru: "Твои позиции в регионе")
        case .stepsToday: PaceLocalization.text(de: "Deine Schritte heute", en: "Your steps today", ru: "Твои шаги сегодня")
        case .week: PaceLocalization.text(de: "Deine Woche", en: "Your week", ru: "Твоя неделя")
        case .streak: PaceLocalization.text(de: "Deine Serie", en: "Your streak", ru: "Твоя серия")
        case .neighborhood: PaceLocalization.text(de: "Dein Umfeld", en: "Your ranking neighbors", ru: "Твоё окружение")
        case .friends: PaceLocalization.text(de: "Freunde-Ranking", en: "Friends ranking", ru: "Рейтинг друзей")
        case .groups: PaceLocalization.text(de: "Deine Gruppen", en: "Your groups", ru: "Твои группы")
        case .activity: PaceLocalization.text(de: "Aktivität", en: "Activity", ru: "Активность")
        case .calendar: PaceLocalization.text(de: "Kalender", en: "Calendar", ru: "Календарь")
        }
    }

    /// Kurze Beschreibung, z. B. für VoiceOver in der Widget-Galerie.
    public var summary: String {
        switch self {
        case .regionRanks:
            PaceLocalization.text(
                de: "Dein Platz in Stadt, Landkreis, Bundesland und Land",
                en: "Your rank in city, district, state and country",
                ru: "Твоё место в городе, районе, земле и стране"
            )
        case .stepsToday:
            PaceLocalization.text(
                de: "Schritte, Tagesziel, Distanz und Kalorien",
                en: "Steps, daily goal, distance and calories",
                ru: "Шаги, дневная цель, расстояние и калории"
            )
        case .week:
            PaceLocalization.text(de: "Montag bis Sonntag auf einen Blick", en: "Monday to Sunday at a glance", ru: "С понедельника по воскресенье")
        case .streak:
            PaceLocalization.text(
                de: "Tage in Folge mit erreichtem Tagesziel",
                en: "Days in a row with your daily goal reached",
                ru: "Дни подряд с выполненной дневной целью"
            )
        case .neighborhood:
            PaceLocalization.text(de: "Wer direkt vor und hinter dir liegt", en: "Who is right ahead of and behind you", ru: "Кто прямо перед тобой и за тобой")
        case .friends:
            PaceLocalization.text(
                de: "Vergleich mit ausgewählten Freunden",
                en: "Compare yourself with selected friends",
                ru: "Сравнение с выбранными друзьями"
            )
        case .groups:
            PaceLocalization.text(de: "Gruppen-Streak und Tagesziel", en: "Group streak and daily goal", ru: "Серия группы и дневная цель")
        case .activity:
            PaceLocalization.text(
                de: "Schritte, Distanz oder Kalorien der letzten sieben Tage",
                en: "Steps, distance or calories of the last seven days",
                ru: "Шаги, расстояние или калории за последние семь дней"
            )
        case .calendar:
            PaceLocalization.text(
                de: "Erreichte Tagesziele im Kalender",
                en: "Reached daily goals in a calendar",
                ru: "Выполненные дневные цели в календаре"
            )
        }
    }

    public var systemImage: String {
        switch self {
        case .regionRanks: "trophy"
        case .stepsToday: "figure.walk"
        case .week: "chart.bar"
        case .streak: "flame"
        case .neighborhood: "chart.bar"
        case .friends: "person.2"
        case .groups: "person.3"
        case .activity: "shoe"
        case .calendar: "calendar.badge.plus"
        }
    }

    /// Kategorien der Widget-Galerie in der Reihenfolge des freigegebenen Designs. Die Schrittkarte ist immer auf
    /// Home und erscheint nur beim Bearbeiten (unter „Schritte und Aktivität“).
    public static let galleryKinds: [HomeModuleKind] = [
        .activity, .week, .streak, .friends, .groups, .regionRanks, .neighborhood, .calendar,
    ]

    /// Kategorie, unter der das Widget in der Galerie steht.
    public var galleryCategory: HomeModuleKind {
        self == .stepsToday ? .activity : self
    }

    /// Name der Kategorie in der Widget-Galerie.
    public var galleryTitle: String {
        switch self {
        case .activity, .stepsToday:
            PaceLocalization.text(de: "Schritte und Aktivität", en: "Steps and activity", ru: "Шаги и активность")
        case .week: PaceLocalization.text(de: "Wochenübersicht", en: "Weekly overview", ru: "Обзор недели")
        case .streak: PaceLocalization.text(de: "Persönliche Streak", en: "Personal streak", ru: "Личная серия")
        case .friends: PaceLocalization.text(de: "Freunde", en: "Friends", ru: "Друзья")
        case .groups: PaceLocalization.text(de: "Gruppen", en: "Groups", ru: "Группы")
        case .regionRanks: PaceLocalization.text(de: "Regionale Rankings", en: "Regional rankings", ru: "Региональные рейтинги")
        case .neighborhood: PaceLocalization.text(de: "Ranking-Umfeld", en: "Ranking neighbors", ru: "Соседи по рейтингу")
        case .calendar: PaceLocalization.text(de: "Kalender", en: "Calendar", ru: "Календарь")
        }
    }

    /// Zweite Zeile einer Kategorie in der Galerie (nur, wo das Design eine zeigt).
    public var gallerySubtitle: String? {
        switch self {
        case .groups:
            PaceLocalization.text(de: "Gruppe auswählen", en: "Choose a group", ru: "Выбери группу")
        case .regionRanks:
            RegionLevel.allCases.map(\.widgetTitle).joined(separator: " · ")
        case .activity, .stepsToday, .week, .streak, .friends, .neighborhood, .calendar:
            nil
        }
    }

    /// Die Schrittkarte ist der Kern des Dashboards: immer vorhanden und nie klein.
    public var isRemovable: Bool {
        self != .stepsToday
    }

    public var supportedSizes: [HomeModuleSize] {
        self == .stepsToday ? [.medium, .large, .max] : HomeModuleSize.allCases
    }

    public var defaultSize: HomeModuleSize { .medium }

    /// Widgets, die mehrfach vorkommen dürfen – jeweils mit eigener Konfiguration (z. B. mehrere Freunde-Widgets).
    public var allowsMultiple: Bool {
        switch self {
        case .regionRanks, .neighborhood, .friends, .groups, .activity: true
        case .stepsToday, .week, .streak, .calendar: false
        }
    }

    /// Ob das Widget eine Ranking-Ebene braucht.
    public var usesRegionScope: Bool {
        self == .neighborhood
    }

    /// Regionale Ranking-Widgets – bei ausgeschalteter Ranking-Sichtbarkeit verborgen.
    public var showsRegionalRankings: Bool {
        self == .regionRanks || self == .neighborhood
    }
}

/// Größe eines Widgets. Die Größe bestimmt auch den Inhalt: klein das Wichtigste, Max die ausführlichste Darstellung.
public enum HomeModuleSize: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case small
    case medium
    case large
    case max

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: PaceLocalization.text(de: "Klein", en: "Small", ru: "Маленький")
        case .medium: PaceLocalization.text(de: "Mittel", en: "Medium", ru: "Средний")
        case .large: PaceLocalization.text(de: "Groß", en: "Large", ru: "Большой")
        case .max: PaceLocalization.text(de: "Max", en: "Max", ru: "Максимум")
        }
    }

    private var order: Int {
        switch self {
        case .small: 0
        case .medium: 1
        case .large: 2
        case .max: 3
        }
    }

    public static func < (lhs: HomeModuleSize, rhs: HomeModuleSize) -> Bool {
        lhs.order < rhs.order
    }
}

/// Kennzahl des Aktivitäts-Widgets (unterstützte Statistikinhalte).
public enum HomeActivityMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    case steps
    case distance
    case activeEnergy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .steps: PaceLocalization.text(de: "Schritte", en: "Steps", ru: "Шаги")
        case .distance: PaceLocalization.text(de: "Distanz", en: "Distance", ru: "Расстояние")
        case .activeEnergy: PaceLocalization.text(de: "Aktive Kalorien", en: "Active calories", ru: "Активные калории")
        }
    }

    /// Titel des Aktivitäts-Widgets, z. B. „Schritte · 7 Tage“.
    public var widgetTitle: String {
        switch self {
        case .steps: PaceLocalization.text(de: "Schritte · 7 Tage", en: "Steps · 7 days", ru: "Шаги · 7 дней")
        case .distance: PaceLocalization.text(de: "Distanz · 7 Tage", en: "Distance · 7 days", ru: "Расстояние · 7 дней")
        case .activeEnergy:
            PaceLocalization.text(de: "Aktive Kalorien · 7 Tage", en: "Active calories · 7 days", ru: "Активные калории · 7 дней")
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "location"
        case .activeEnergy: "flame"
        }
    }
}

/// Eigene Einstellungen eines Widgets. Jedes Widget hat seine eigene Konfiguration – Änderungen an einem Widget
/// betreffen keine anderen.
public struct HomeWidgetConfiguration: Hashable, Sendable {
    /// Freunde-Widget: ausgewählte Freunde (öffentliche IDs) in Auswahlreihenfolge; `nil` = alle Freunde.
    public var friendIDs: [UUID]?
    /// Eigener Name des Widgets (z. B. „Meine Laufrunde“); `nil` = Standardtitel.
    public var customName: String?
    /// Gruppen-Widget: die gezeigte Gruppe; `nil` = alle eigenen Gruppen.
    public var groupID: UUID?
    /// Regionale Rankings: gezeigte Ebenen; `nil` = alle vier.
    public var regionLevels: [RegionLevel]?
    /// Aktivitäts-Widget: gezeigte Kennzahl.
    public var metric: HomeActivityMetric?
    /// Eigene Auswahl der Zusatzinhalte (siehe ``HomeWidgetDetail``); `nil` = Standard der Größe, leer = keine.
    public var details: [HomeWidgetDetail]?

    /// Maximale Länge des eigenen Namens.
    public static let nameLength = 30

    public init(
        friendIDs: [UUID]? = nil,
        customName: String? = nil,
        groupID: UUID? = nil,
        regionLevels: [RegionLevel]? = nil,
        metric: HomeActivityMetric? = nil,
        details: [HomeWidgetDetail]? = nil
    ) {
        self.friendIDs = friendIDs
        self.customName = customName
        self.groupID = groupID
        self.regionLevels = regionLevels
        self.metric = metric
        self.details = details
    }

    public var isEmpty: Bool {
        self == HomeWidgetConfiguration()
    }

    /// Nur die Felder, die zur Art passen – bereinigt (keine doppelten Freunde, getrimmter Name, sortierte Ebenen,
    /// nur Zusatzinhalte der Art in fester Reihenfolge). Einen eigenen Namen kann jedes Widget haben.
    public func sanitized(for kind: HomeModuleKind) -> HomeWidgetConfiguration {
        var result: HomeWidgetConfiguration
        switch kind {
        case .friends:
            var seen: Set<UUID> = []
            let ids = (friendIDs ?? []).filter { seen.insert($0).inserted }
            result = HomeWidgetConfiguration(friendIDs: ids.isEmpty ? nil : ids)
        case .groups:
            result = HomeWidgetConfiguration(groupID: groupID)
        case .regionRanks:
            let levels = RegionLevel.allCases.filter { (regionLevels ?? []).contains($0) }
            let shown = levels.isEmpty || levels == RegionLevel.allCases ? nil : levels
            result = HomeWidgetConfiguration(regionLevels: shown)
        case .activity:
            result = HomeWidgetConfiguration(metric: metric ?? .steps)
        case .stepsToday, .week, .streak, .neighborhood, .calendar:
            result = HomeWidgetConfiguration()
        }
        result.customName = Self.cleanedName(customName)
        result.details = details.map { chosen in kind.allDetails.filter(chosen.contains) }
        if kind.allDetails.isEmpty {
            result.details = nil
        }
        return result
    }

    /// Getrimmter Name mit einfachen Leerzeichen, höchstens ``nameLength`` Zeichen; leer → `nil`.
    public static func cleanedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let collapsed = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        let limited = String(collapsed.prefix(nameLength)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? nil : limited
    }
}

extension HomeWidgetConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case friendIDs
        case customName = "name"
        case groupID
        case regionLevels = "levels"
        case metric
        case details
    }

    /// Tolerant: unbekannte oder beschädigte Werte werden übersprungen statt das ganze Widget zu verwerfen.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = (try? container.decodeIfPresent([String].self, forKey: .friendIDs)) ?? nil
        friendIDs = ids.map { $0.compactMap(UUID.init(uuidString:)) }
        customName = (try? container.decodeIfPresent(String.self, forKey: .customName)) ?? nil
        let group = (try? container.decodeIfPresent(String.self, forKey: .groupID)) ?? nil
        groupID = group.flatMap(UUID.init(uuidString:))
        let levels = (try? container.decodeIfPresent([String].self, forKey: .regionLevels)) ?? nil
        regionLevels = levels.map { $0.compactMap(RegionLevel.init(rawValue:)) }
        let metric = (try? container.decodeIfPresent(String.self, forKey: .metric)) ?? nil
        self.metric = metric.flatMap(HomeActivityMetric.init(rawValue:))
        let details = (try? container.decodeIfPresent([String].self, forKey: .details)) ?? nil
        self.details = details.map { $0.compactMap(HomeWidgetDetail.init(rawValue:)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(friendIDs?.map(\.uuidString), forKey: .friendIDs)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encodeIfPresent(groupID?.uuidString, forKey: .groupID)
        try container.encodeIfPresent(regionLevels?.map(\.rawValue), forKey: .regionLevels)
        try container.encodeIfPresent(metric?.rawValue, forKey: .metric)
        try container.encodeIfPresent(details?.map(\.rawValue), forKey: .details)
    }
}

/// Ein Widget auf dem Dashboard: stabile ID, Art, Größe und eigene Konfiguration. Die Position ergibt sich aus der
/// Reihenfolge in ``HomePreferences/modules``.
public struct HomeModule: Hashable, Sendable, Identifiable {
    public let id: String
    public var kind: HomeModuleKind
    public var size: HomeModuleSize
    /// Ebene des Rankings für „Dein Umfeld“; `nil` für alle anderen Widgets.
    public var regionLevel: RegionLevel?
    public var configuration: HomeWidgetConfiguration

    public init(
        id: String = UUID().uuidString,
        kind: HomeModuleKind,
        size: HomeModuleSize? = nil,
        regionLevel: RegionLevel? = nil,
        configuration: HomeWidgetConfiguration = HomeWidgetConfiguration()
    ) {
        self.id = id
        self.kind = kind
        self.size = size ?? kind.defaultSize
        self.regionLevel = kind.usesRegionScope ? (regionLevel ?? .municipality) : nil
        self.configuration = configuration.sanitized(for: kind)
    }

    /// Titel des Widgets: eigener Name oder Standardtitel (beim Aktivitäts-Widget mit Kennzahl).
    public var title: String {
        if let name = configuration.customName { return name }
        return kind == .activity ? metric.widgetTitle : kind.title
    }

    /// Ebenen eines Widgets „Regionale Rankings“ (Standard: alle vier).
    public var regionLevels: [RegionLevel] {
        configuration.regionLevels ?? RegionLevel.allCases
    }

    /// Kennzahl eines Aktivitäts-Widgets.
    public var metric: HomeActivityMetric {
        configuration.metric ?? .steps
    }

    /// Zeilen im Umfeld-Widget: klein nur der eigene Platz, mittel drei, groß fünf, Max sieben (als Diagramm).
    public var neighborhoodRows: Int {
        switch size {
        case .small: 1
        case .medium: 3
        case .large: 5
        case .max: 7
        }
    }

    /// Wie viele Plätze über und unter dem eigenen geladen werden müssen, damit auch Platz 1 und der Letzte volle
    /// Zeilen haben. Klein braucht den Platz darüber für „Noch … Schritte bis Platz …“. Der Server begrenzt auf 10.
    public var neighborhoodRadius: Int {
        size == .small ? 1 : neighborhoodRows - 1
    }

    /// z. B. `Mittel · Gemeinde`.
    public var detailText: String {
        guard let regionLevel else { return size.title }
        return "\(size.title) · \(regionLevel.scopeTitle)"
    }

    /// Kennung für Widgets, die nicht doppelt vorkommen sollen (z. B. zwei Widgets derselben Gruppe); `nil` = beliebig
    /// oft möglich.
    var uniquenessKey: String? {
        switch kind {
        case .groups: "groups:\(configuration.groupID?.uuidString ?? "all")"
        case .activity: "activity:\(metric.rawValue)"
        case .regionRanks: "regionRanks:\(regionLevels.map(\.rawValue).joined(separator: ","))"
        case .stepsToday, .week, .streak, .calendar: kind.rawValue
        case .neighborhood, .friends: nil
        }
    }
}

extension HomeModule: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case size
        case regionLevel
        case configuration = "config"
    }

    /// Unbekannte Arten werfen (das Widget wird übersprungen); unbekannte Größen und Felder fallen auf Standards zurück.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let kind = try container.decode(HomeModuleKind.self, forKey: .kind)
        let size = (try? container.decodeIfPresent(HomeModuleSize.self, forKey: .size)) ?? nil
        let regionLevel = (try? container.decodeIfPresent(RegionLevel.self, forKey: .regionLevel)) ?? nil
        let configuration = (try? container.decodeIfPresent(HomeWidgetConfiguration.self, forKey: .configuration)) ?? nil
        self.init(id: id, kind: kind, size: size, regionLevel: regionLevel, configuration: configuration ?? HomeWidgetConfiguration())
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(regionLevel, forKey: .regionLevel)
        if !configuration.isEmpty {
            try container.encode(configuration, forKey: .configuration)
        }
    }
}

public extension RegionLevel {
    /// Bezeichnung der Ebene für die Auswahl in Widgets.
    var scopeTitle: String {
        switch self {
        case .municipality: PaceLocalization.text(de: "Gemeinde", en: "Municipality", ru: "Община")
        case .district: PaceLocalization.text(de: "Kreis", en: "District", ru: "Район")
        case .state: PaceLocalization.text(de: "Bundesland", en: "State", ru: "Земля")
        case .country: PaceLocalization.text(de: "Deutschland", en: "Germany", ru: "Германия")
        }
    }

    /// Kurze Bezeichnung für die Auswahl der Ebenen („Stadt · Landkreis · Bundesland · Deutschland“).
    var widgetTitle: String {
        switch self {
        case .municipality: PaceLocalization.text(de: "Stadt", en: "City", ru: "Город")
        case .district: PaceLocalization.text(de: "Landkreis", en: "District", ru: "Район")
        case .state: PaceLocalization.text(de: "Bundesland", en: "State", ru: "Земля")
        case .country: PaceLocalization.text(de: "Deutschland", en: "Germany", ru: "Германия")
        }
    }
}

/// Persönliche Einstellungen des Home-Dashboards. Bleiben auf dem Gerät.
///
/// - Version 3 (aktuell): Widgets mit stabiler ID, Art, Größe (bis Max) und eigener Konfiguration (`config`).
/// - Version 2: Module mit Art, Größe und Ebene – wird ohne Verlust übernommen (dieselben Felder ohne `config`).
/// - Version 1: ein- und ausblendbare Bereiche – sichtbare Bereiche werden in derselben Reihenfolge übernommen.
///
/// Unbekannte Arten (z. B. aus einer neueren App-Version) werden übersprungen, unbekannte Felder ignoriert.
public struct HomePreferences: Equatable, Sendable {
    /// Aktuelles Speicherformat.
    public static let currentVersion = 3

    public var modules: [HomeModule]
    /// Tagesziel aus Version 1. Das Ziel steht inzwischen im Zielverlauf (`StepGoalSettings`); der Wert wird nur
    /// einmalig dorthin übernommen.
    public var legacyStepGoal: Int?

    public init(modules: [HomeModule] = Self.defaultModules(), legacyStepGoal: Int? = nil) {
        self.modules = modules
        self.legacyStepGoal = legacyStepGoal
    }

    /// Standard-Layout für neue Nutzer – in der Reihenfolge des freigegebenen Home-Designs: Platzierungen, Schritte,
    /// Woche, Umfeld, Freunde und Gruppen, danach die persönliche Serie.
    public static func defaultModules() -> [HomeModule] {
        [.regionRanks, .stepsToday, .week, .neighborhood, .friends, .groups, .streak].map { HomeModule(kind: $0) }
    }

    /// Repariert gespeicherte Werte: doppelte IDs und doppelte Einzel-Widgets entfallen, nicht erlaubte Größen werden
    /// zurückgesetzt, Konfigurationen bereinigt, die Schrittkarte ist immer vorhanden.
    public func normalized() -> HomePreferences {
        var seenIDs: Set<String> = []
        var seenKeys: Set<String> = []
        var result: [HomeModule] = []
        for module in modules {
            guard seenIDs.insert(module.id).inserted else { continue }
            if let key = module.uniquenessKey, !seenKeys.insert(key).inserted { continue }
            let size = module.kind.supportedSizes.contains(module.size) ? module.size : module.kind.defaultSize
            result.append(HomeModule(
                id: module.id,
                kind: module.kind,
                size: size,
                regionLevel: module.regionLevel,
                configuration: module.configuration
            ))
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

    /// Überspringt Widgets unbekannter Art (z. B. aus einer neueren App-Version), statt alles zu verwerfen.
    private struct LossyModule: Decodable {
        let module: HomeModule?

        init(from decoder: Decoder) throws {
            module = try? HomeModule(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyStepGoal = try? container.decodeIfPresent(Int.self, forKey: .legacyStepGoal)
        // Version 2 und 3 speichern Module unter demselben Schlüssel; Version 3 ergänzt nur `config` und `max`.
        if let modules = try container.decodeIfPresent([LossyModule].self, forKey: .modules) {
            self.init(modules: modules.compactMap(\.module), legacyStepGoal: legacyStepGoal ?? nil)
            return
        }
        let sections = (try? container.decodeIfPresent([LegacySection].self, forKey: .sections)) ?? nil
        self.init(modules: Self.migrated(sections ?? []), legacyStepGoal: legacyStepGoal ?? nil)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(modules, forKey: .modules)
        try container.encodeIfPresent(legacyStepGoal, forKey: .legacyStepGoal)
    }

    /// Version 1 → 3: sichtbare Bereiche in Nutzer-Reihenfolge als mittlere Widgets, die Serie nach der Woche.
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
