import ActivityFeature
import Foundation
import PaceCore

/// Zusätzliche Inhalte, die sich je Widget im Bearbeitungsmodus ein- und ausschalten lassen. Jede Art hat ihre eigenen
/// Inhalte (``HomeModuleKind/availableDetails(for:)``); ohne eigene Auswahl zeigt ein Widget wie bisher den Standard
/// seiner Größe.
///
/// Die Rohwerte werden gespeichert und dürfen sich nicht ändern. Nur echte Daten: Was Pace nicht kennt (z. B. die
/// Platzierungsänderung gegenüber gestern), wird nicht angeboten.
public enum HomeWidgetDetail: String, Codable, CaseIterable, Sendable, Identifiable {
    // Schritte heute
    /// Distanz und aktive Kalorien (gemessen oder geschätzt).
    case distanceEnergy
    /// Stockwerke und Trainingsminuten.
    case floorsExercise
    /// Mini-Diagramm der letzten 7 Tage mit Ziellinie (ab „Groß“).
    case weekChart
    /// Vergleich mit gestern und dem Durchschnitt der letzten 7 Tage.
    case comparison
    /// Persönlicher Tagesbestwert (bester Tag im geladenen Verlauf).
    case dayBest

    // Persönliche Serie
    /// Persönlicher Rekord neben der aktuellen Serie.
    case record
    /// Laufende Woche als kompakte Leiste.
    case week
    /// Nächster Meilenstein der Serie (z. B. „Noch 2 Tage bis 7 Tage“).
    case milestone
    /// Letzte vier Wochen und erreichte Tage der letzten 30 Tage.
    case recentDays

    // Freunde
    /// Abstand zum Platz davor in jeder Zeile.
    case friendGap
    /// Diagramm der Auswahl.
    case friendChart

    // Eine gewählte Gruppe
    /// Heutiger Fortschritt: wie viele Mitglieder ihr Ziel erreicht haben.
    case groupProgress
    /// Tagesziel und beste Serie der Gruppe.
    case groupGoal
    /// Mitglieder und heute erreicht als Kennzahlen.
    case groupMembers

    // Ranking-Umfeld
    /// „Noch … Schritte bis Platz …“ unter dem Umfeld.
    case rankGap

    // Tagesvergleich
    /// Balken heute und gestern bis zur gleichen Uhrzeit.
    case comparisonBars
    /// Schritte gestern insgesamt.
    case yesterdayTotal

    // Flammen-Woche
    /// Aktuelle Serie in Tagen.
    case streakCount

    // Gruppenfortschritt
    /// Hinweis zur heutigen Gruppenflamme (⌈n/3⌉-Regel).
    case groupHint

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .distanceEnergy:
            PaceLocalization.text(de: "Distanz & Kalorien", en: "Distance & calories", ru: "Расстояние и калории")
        case .floorsExercise:
            PaceLocalization.text(de: "Stockwerke & Training", en: "Floors & exercise", ru: "Этажи и тренировка")
        case .weekChart:
            PaceLocalization.text(de: "Mini-Diagramm: letzte 7 Tage", en: "Mini chart: last 7 days", ru: "Мини-диаграмма: последние 7 дней")
        case .comparison:
            PaceLocalization.text(de: "Vergleich: gestern & Ø 7 Tage", en: "Compare: yesterday & 7-day avg.", ru: "Сравнение: вчера и среднее за 7 дней")
        case .dayBest:
            PaceLocalization.text(de: "Persönlicher Tagesbestwert", en: "Personal best day", ru: "Личный рекорд дня")
        case .record:
            PaceLocalization.text(de: "Persönlicher Rekord", en: "Personal record", ru: "Личный рекорд")
        case .week:
            PaceLocalization.text(de: "Kompakte Wochenübersicht", en: "Compact week overview", ru: "Краткий обзор недели")
        case .milestone:
            PaceLocalization.text(de: "Nächster Meilenstein", en: "Next milestone", ru: "Следующая веха")
        case .recentDays:
            PaceLocalization.text(de: "Letzte erfolgreiche Tage", en: "Recent successful days", ru: "Последние успешные дни")
        case .friendGap:
            PaceLocalization.text(de: "Abstand zum Platz davor", en: "Gap to the rank ahead", ru: "Отставание от места выше")
        case .friendChart:
            PaceLocalization.text(de: "Diagramm", en: "Chart", ru: "Диаграмма")
        case .groupProgress:
            PaceLocalization.text(de: "Heute erreicht", en: "Reached today", ru: "Выполнили сегодня")
        case .groupGoal:
            PaceLocalization.text(de: "Tagesziel & beste Serie", en: "Daily goal & best streak", ru: "Дневная цель и лучшая серия")
        case .groupMembers:
            PaceLocalization.text(de: "Mitglieder als Kennzahlen", en: "Members as figures", ru: "Участники в цифрах")
        case .rankGap:
            PaceLocalization.text(de: "Abstand zum nächsten Platz", en: "Gap to the next rank", ru: "До следующего места")
        case .comparisonBars:
            PaceLocalization.text(de: "Balken heute & gestern", en: "Bars today & yesterday", ru: "Столбцы: сегодня и вчера")
        case .yesterdayTotal:
            PaceLocalization.text(de: "Gestern insgesamt", en: "Yesterday in total", ru: "Всего за вчера")
        case .streakCount:
            PaceLocalization.text(de: "Aktuelle Serie", en: "Current streak", ru: "Текущая серия")
        case .groupHint:
            PaceLocalization.text(de: "Hinweis zur Gruppenflamme", en: "Group flame hint", ru: "Подсказка об огне группы")
        }
    }

    public var systemImage: String {
        switch self {
        case .distanceEnergy: "shoeprints.fill"
        case .floorsExercise: "figure.stairs"
        case .weekChart: "chart.bar.xaxis"
        case .comparison: "clock.arrow.circlepath"
        case .dayBest: "trophy"
        case .record: "trophy"
        case .week: "calendar"
        case .milestone: "flag.checkered"
        case .recentDays: "checkmark.circle"
        case .friendGap: "arrow.up.right"
        case .friendChart: "chart.bar"
        case .groupProgress: "person.2.badge.gearshape"
        case .groupGoal: "scope"
        case .groupMembers: "person.3"
        case .rankGap: "arrow.up.right"
        case .comparisonBars: "chart.bar.doc.horizontal"
        case .yesterdayTotal: "clock.arrow.circlepath"
        case .streakCount: "flame"
        case .groupHint: "info.circle"
        }
    }
}

public extension HomeModuleKind {
    /// Alle Zusatzinhalte dieser Art in fester Reihenfolge (so erscheinen sie auch im Widget).
    var allDetails: [HomeWidgetDetail] {
        switch self {
        case .stepsToday: [.distanceEnergy, .floorsExercise, .weekChart, .comparison, .dayBest]
        case .streak: [.record, .week, .milestone, .recentDays]
        case .friends: [.friendGap, .friendChart]
        case .groups: [.groupProgress, .groupGoal, .groupMembers]
        case .neighborhood: [.rankGap]
        case .dayComparison: [.comparisonBars, .yesterdayTotal]
        case .streakWeek: [.streakCount, .record, .milestone]
        case .groupProgress: [.groupHint, .groupGoal]
        case .regionRanks, .week, .activity, .calendar, .records, .activityTimes: []
        }
    }

    /// Zusatzinhalte, die in dieser Größe Platz haben. Klein zeigt nur das Wichtigste; Diagramme (Freunde, 7 Tage)
    /// brauchen mindestens „Groß“.
    func availableDetails(for size: HomeModuleSize) -> [HomeWidgetDetail] {
        guard size != .small || self == .neighborhood else { return [] }
        return allDetails.filter { detail in
            (detail != .friendChart && detail != .weekChart) || size >= .large
        }
    }

    /// Wie viele Zusatzinhalte die Größe höchstens zeigt (mittel 2, groß 3, Max alle) – damit das Widget zu seiner
    /// Größe passt. Freunde und Umfeld haben nur Anzeige-Schalter ohne eigene Fläche und sind nicht begrenzt.
    func detailLimit(for size: HomeModuleSize) -> Int {
        switch self {
        case .friends, .neighborhood:
            return allDetails.count
        default:
            switch size {
            case .small: return 0
            case .medium: return 2
            case .large: return 3
            case .max: return allDetails.count
            }
        }
    }

    /// Standard ohne eigene Auswahl – genau das, was die Widgets bisher in der jeweiligen Größe zeigen.
    func defaultDetails(for size: HomeModuleSize) -> [HomeWidgetDetail] {
        switch (self, size) {
        case (.stepsToday, .small): []
        case (.stepsToday, .medium): [.distanceEnergy]
        case (.stepsToday, .large): [.distanceEnergy, .floorsExercise]
        // Max: Groß plus Analyse – 7-Tage-Verlauf mit Ziellinie und Vergleich mit gestern und Ø 7 Tagen.
        case (.stepsToday, .max): [.distanceEnergy, .floorsExercise, .weekChart, .comparison]
        case (.streak, .small): []
        case (.streak, .medium): [.record]
        case (.streak, .large): [.record, .week]
        case (.streak, .max): [.record, .week, .recentDays]
        case (.friends, .max): [.friendChart]
        case (.friends, _): []
        case (.groups, .small): []
        case (.groups, .medium): [.groupProgress]
        case (.groups, .large): [.groupProgress, .groupGoal]
        case (.groups, .max): [.groupProgress, .groupGoal, .groupMembers]
        case (.neighborhood, _): [.rankGap]
        case (.dayComparison, .small): []
        case (.dayComparison, .medium): [.comparisonBars]
        case (.dayComparison, _): [.comparisonBars, .yesterdayTotal]
        case (.streakWeek, .small): []
        case (.streakWeek, .medium): [.streakCount]
        case (.streakWeek, .large): [.streakCount, .record]
        case (.streakWeek, .max): [.streakCount, .record, .milestone]
        case (.groupProgress, .small): []
        case (.groupProgress, .medium): [.groupHint]
        case (.groupProgress, _): [.groupHint, .groupGoal]
        case (.regionRanks, _), (.week, _), (.activity, _), (.calendar, _), (.records, _), (.activityTimes, _): []
        }
    }
}

public extension HomeModule {
    /// Zusatzinhalte, die das Widget gerade zeigt: eigene Auswahl oder der Standard der Größe, in fester Reihenfolge,
    /// begrenzt auf das, was in die Größe passt.
    var shownDetails: [HomeWidgetDetail] {
        let available = kind.availableDetails(for: size)
        let chosen = configuration.details ?? kind.defaultDetails(for: size)
        return Array(available.filter(chosen.contains).prefix(kind.detailLimit(for: size)))
    }

    func shows(_ detail: HomeWidgetDetail) -> Bool {
        shownDetails.contains(detail)
    }
}

/// Nächster Meilenstein einer Serie, z. B. bei 5 Tagen die 7 (noch 2 Tage).
public enum StreakMilestone {
    /// Feste Stufen; danach jedes volle Hundert.
    public static let steps = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365]

    /// Der nächste Meilenstein über der aktuellen Serie.
    public static func next(after current: Int) -> Int {
        if let next = steps.first(where: { $0 > current }) { return next }
        return (max(current, steps.last ?? 0) / 100 + 1) * 100
    }

    /// „дня“ bzw. „дней“ nach „до“ (Genitiv): до 21 дня, до 7 дней.
    static func russianDaysGenitive(_ count: Int) -> String {
        count % 10 == 1 && count % 100 != 11 ? "дня" : "дней"
    }

    /// z. B. „Noch 2 Tage bis zu 7 Tagen in Folge“. Ist das Ziel heute noch offen, zählt heute als erster dieser Tage.
    public static func text(current: Int) -> String {
        let target = next(after: current)
        let days = PaceLocalization.days(target - current)
        let goal = target.paceFormatted
        return PaceLocalization.text(
            de: "Noch \(days) bis zu \(goal) Tagen in Folge",
            en: "\(days) more to reach \(goal) in a row",
            ru: "Ещё \(days) до \(goal) \(russianDaysGenitive(target)) подряд"
        )
    }
}

/// Persönlicher Tagesbestwert für die Schrittkarte (Wettbewerbsschritte; manuell eingetragene zählen nicht).
public struct HomeDayBest: Equatable, Sendable {
    public let steps: Int
    public let date: LocalDate
    /// Heute ist (bisher) der beste Tag.
    public let isToday: Bool
    /// z. B. `12.480`.
    public let valueText: String
    /// z. B. `Di., 13. Okt.` oder `Heute`.
    public let detailText: String

    public init(steps: Int, date: LocalDate, isToday: Bool, formatter: ActivityFormatter) {
        self.steps = steps
        self.date = date
        self.isToday = isToday
        valueText = steps.paceFormatted
        detailText = isToday
            ? PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня")
            : formatter.dayWithWeekdayShort(date)
    }

    /// Titel der Kachel, z. B. `Tagesbestwert · Heute`.
    public var title: String {
        PaceLocalization.text(de: "Tagesbestwert", en: "Best day", ru: "Рекорд дня") + " · " + detailText
    }
}
