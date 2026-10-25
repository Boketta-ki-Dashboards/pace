import ActivityFeature
import Foundation
import PaceCore

// MARK: - Freunde

/// Inhalt eines Freunde-Widgets: du und die ausgewählten Freunde aus dem echten Freundesranking (heute).
///
/// Die Plätze werden innerhalb der Auswahl neu vergeben (1, 2, 3 …). Ausgewählte Personen, die nicht mehr in der
/// Freundesliste stehen, werden nicht gezeigt, sondern als Hinweis gezählt.
public struct HomeFriendsWidget: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        /// Platz innerhalb der Auswahl.
        public let rank: Int
        public let entry: LeaderboardEntry

        public var id: UUID { entry.publicUserID }
    }

    /// Alle Zeilen der Auswahl, sortiert.
    public let allRows: [Row]
    /// Ausgewählte Personen, die nicht mehr in der Freundesliste sind.
    public let missingCount: Int
    /// Das Widget zeigt alle Freunde (keine eigene Auswahl).
    public let isAllFriends: Bool

    /// - Parameters:
    ///   - ranking: Freundesranking inklusive dir.
    ///   - friendIDs: Öffentliche IDs aller Freunde (für den Hinweis auf entfernte Freunde); `nil`, solange die
    ///     Freundesliste nicht geladen ist.
    ///   - selection: Ausgewählte Freunde; `nil` = alle.
    public init(ranking: [LeaderboardEntry], friendIDs: Set<UUID>?, selection: [UUID]?) {
        isAllFriends = selection == nil
        let selected = selection.map(Set.init)
        let entries = ranking
            .filter { entry in entry.isCurrentUser || (selected?.contains(entry.publicUserID) ?? true) }
            .sorted { lhs, rhs in
                lhs.competitionSteps != rhs.competitionSteps ? lhs.competitionSteps > rhs.competitionSteps : lhs.rank < rhs.rank
            }
        allRows = entries.enumerated().map { Row(rank: $0.offset + 1, entry: $0.element) }
        if let selection, let friendIDs {
            let known = friendIDs.union(ranking.filter { !$0.isCurrentUser }.map(\.publicUserID))
            missingCount = Set(selection).subtracting(known).count
        } else {
            missingCount = 0
        }
    }

    /// Ob außer dir jemand im Widget steht.
    public var hasFriends: Bool {
        allRows.contains { !$0.entry.isCurrentUser }
    }

    /// Zeilen für eine Größe: Klein Platz 1, Mittel drei, Groß und Max fünf. Ab Mittel bist du immer dabei – liegst
    /// du weiter hinten, ersetzt deine Zeile die letzte.
    public func rows(for size: HomeModuleSize) -> [Row] {
        let limit = Self.rowLimit(for: size)
        var rows = Array(allRows.prefix(limit))
        if size != .small, let me = allRows.first(where: { $0.entry.isCurrentUser }), !rows.contains(me), !rows.isEmpty {
            rows[rows.count - 1] = me
        }
        return rows
    }

    /// Zeilen für das Diagramm des Max-Widgets (höchstens zehn).
    public var chartRows: [Row] {
        Array(allRows.prefix(10))
    }

    public static func rowLimit(for size: HomeModuleSize) -> Int {
        switch size {
        case .small: 1
        case .medium: 3
        case .large, .max: 5
        }
    }

    /// Abstand zum Platz direkt davor in der Auswahl, z. B. `1.240 hinter #2` oder `Gleichstand mit #2`; `nil` für
    /// Platz 1. Gilt auch, wenn die eigene Zeile die letzte sichtbare ersetzt (Bezug ist der echte Platz davor).
    public func gapText(for row: Row) -> String? {
        guard let index = allRows.firstIndex(where: { $0.id == row.id }), index > 0 else { return nil }
        let ahead = allRows[index - 1]
        let gap = ahead.entry.competitionSteps - row.entry.competitionSteps
        let rank = "#\(ahead.rank.paceFormatted)"
        if gap <= 0 {
            return PaceLocalization.text(de: "Gleichstand mit \(rank)", en: "Tied with \(rank)", ru: "Вровень с \(rank)")
        }
        let steps = gap.paceFormatted
        return PaceLocalization.text(de: "\(steps) hinter \(rank)", en: "\(steps) behind \(rank)", ru: "Отставание \(steps) от \(rank)")
    }

    /// z. B. `1 ausgewählte Person ist nicht mehr in deiner Freundesliste.`
    public var missingText: String? {
        guard missingCount > 0 else { return nil }
        let count = missingCount.paceFormatted
        return PaceLocalization.text(
            de: missingCount == 1
                ? "1 ausgewählte Person ist nicht mehr in deiner Freundesliste."
                : "\(count) ausgewählte Personen sind nicht mehr in deiner Freundesliste.",
            en: missingCount == 1
                ? "1 selected person is no longer in your friends list."
                : "\(count) selected people are no longer in your friends list.",
            ru: "\(count) " + PaceLocalization.plural(
                missingCount,
                de: ("", ""),
                en: ("", ""),
                ru: ("выбранный человек больше не в списке друзей.", "выбранных человека больше не в списке друзей.",
                     "выбранных человек больше не в списке друзей.")
            )
        )
    }
}

// MARK: - Gruppen

/// Was ein Gruppen-Widget zeigt: alle eigenen Gruppen, eine bestimmte Gruppe oder – wenn sie nicht mehr da ist –
/// einen Hinweis.
public enum HomeGroupSelection: Equatable, Sendable {
    case all([GroupSummary])
    case single(GroupSummary)
    /// Die gewählte Gruppe gibt es nicht mehr (verlassen, gelöscht).
    case missing

    /// - Parameters:
    ///   - isLoaded: Ob die Gruppen geladen sind – vorher gilt eine fehlende Gruppe nicht als gelöscht.
    public init(groupID: UUID?, groups: [GroupSummary], isLoaded: Bool) {
        guard let groupID else {
            self = .all(groups)
            return
        }
        if let group = groups.first(where: { $0.id == groupID }) {
            self = .single(group)
        } else {
            self = isLoaded ? .missing : .all([])
        }
    }

    public static var missingText: String {
        PaceLocalization.text(
            de: "Diese Gruppe ist nicht mehr verfügbar. Wähle im Anpassen-Modus eine andere Gruppe.",
            en: "This group is no longer available. Choose another group in customize mode.",
            ru: "Эта группа больше недоступна. Выбери другую группу в режиме настройки."
        )
    }
}

public enum HomeGroupTexts {
    /// z. B. `9 von 8 Mitgliedern haben ihr Ziel erreicht` – kurz: `Heute 9 / 8`.
    public static func todayProgress(_ group: GroupSummary) -> String {
        let reached = group.todayReachedCount.paceFormatted
        let required = group.todayRequiredCount.paceFormatted
        return PaceLocalization.text(
            de: "Heute \(reached) von \(required) erreicht",
            en: "Today \(reached) of \(required) reached",
            ru: "Сегодня \(reached) из \(required)"
        )
    }

    /// z. B. `6 Tage Serie`.
    public static func streak(_ days: Int) -> String {
        PaceLocalization.text(
            de: "\(PaceLocalization.days(days)) Serie",
            en: "\(PaceLocalization.days(days)) streak",
            ru: "Серия: \(PaceLocalization.days(days))"
        )
    }

    public static func members(_ count: Int) -> String {
        "\(count.paceFormatted) " + PaceLocalization.plural(
            count, de: ("Mitglied", "Mitglieder"), en: ("member", "members"), ru: ("участник", "участника", "участников")
        )
    }

    public static var dailyGoal: String {
        PaceLocalization.text(de: "Tagesziel", en: "Daily goal", ru: "Цель дня")
    }

    public static var bestStreak: String {
        PaceLocalization.text(de: "Beste Serie", en: "Best streak", ru: "Лучшая серия")
    }

    public static var membersTitle: String {
        PaceLocalization.text(de: "Mitglieder", en: "Members", ru: "Участники")
    }

    public static var todayTitle: String {
        PaceLocalization.text(de: "Heute erreicht", en: "Reached today", ru: "Выполнили сегодня")
    }
}

// MARK: - Aktivität

/// Inhalt des Aktivitäts-Widgets: eine Kennzahl der letzten sieben Tage (bis heute).
public struct HomeActivityWidget: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        /// `nil`, wenn die Kennzahl für den Tag nicht lesbar ist.
        public let value: Double?
        public let letter: String
        public let isToday: Bool
        public let valueText: String?

        public var id: LocalDate { date }
    }

    public let metric: HomeActivityMetric
    public let days: [Day]
    public let todayText: String?
    public let totalText: String?
    public let averageText: String?
    public let bestDayText: String?
    /// Höchster Wert der Woche (Skala für Balken); mindestens 1.
    public let maximum: Double
    /// Aktive Kalorien: mindestens ein Tag der Woche ist geschätzt (Summe und Durchschnitt mit „≈“).
    public let isEstimated: Bool
    /// Aktive Kalorien: der heutige Wert ist geschätzt (Beschriftung unter dem heutigen Wert).
    public let isTodayEstimated: Bool

    public init(metric: HomeActivityMetric, overview: ActivityOverview, formatter: ActivityFormatter) {
        self.metric = metric
        let today = overview.today.date
        let summaries = overview.lastSevenDays.days.sorted { $0.date < $1.date }
        // Aktive Kalorien: geschätzte Werte (ohne gemessene aus Apple Health) tragen ein „≈“.
        isEstimated = metric == .activeEnergy && summaries.contains { $0.activeEnergy.isEstimated }
        let format: (Double, Bool) -> String = { value, estimated in
            switch metric {
            case .steps: formatter.steps(Int(value.rounded()))
            case .distance: formatter.distance(meters: value)
            case .activeEnergy: (estimated ? ActivityTexts.approximatelyPrefix : "") + formatter.energy(kilocalories: value)
            }
        }
        days = summaries.map { summary in
            let value = Self.value(of: metric, in: summary)
            return Day(
                date: summary.date,
                value: value,
                letter: HomeFormat.weekdayLetter(summary.date, formatter: formatter),
                isToday: summary.date == today,
                valueText: value.map { format($0, metric == .activeEnergy && summary.activeEnergy.isEstimated) }
            )
        }
        let values = days.compactMap(\.value)
        let isTodayEstimated = metric == .activeEnergy && overview.today.activeEnergy.isEstimated
        self.isTodayEstimated = isTodayEstimated
        todayText = Self.value(of: metric, in: overview.today).map { format($0, isTodayEstimated) }
        totalText = values.isEmpty ? nil : format(values.reduce(0, +), isEstimated)
        averageText = values.isEmpty ? nil : format(values.reduce(0, +) / Double(values.count), isEstimated)
        if let best = days.filter({ $0.value != nil }).max(by: { ($0.value ?? 0) < ($1.value ?? 0) }), let value = best.value {
            let bestSummary = summaries.first { $0.date == best.date }
            bestDayText = "\(formatter.weekdayShort(best.date)) · \(format(value, metric == .activeEnergy && bestSummary?.activeEnergy.isEstimated == true))"
        } else {
            bestDayText = nil
        }
        maximum = max(values.max() ?? 0, 1)
    }

    static func value(of metric: HomeActivityMetric, in summary: DailyActivitySummary) -> Double? {
        switch metric {
        case .steps: Double(summary.competitionSteps)
        case .distance: summary.walkingRunningDistanceMeters
        case .activeEnergy: summary.activeEnergy.kilocalories
        }
    }

    public static var todayTitle: String {
        PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня")
    }

    public static var totalTitle: String {
        PaceLocalization.text(de: "7 Tage gesamt", en: "7-day total", ru: "За 7 дней")
    }

    public static var averageTitle: String {
        PaceLocalization.text(de: "Durchschnitt", en: "Average", ru: "В среднем")
    }

    public static var bestDayTitle: String {
        PaceLocalization.text(de: "Bester Tag", en: "Best day", ru: "Лучший день")
    }

    public static var unavailableText: String {
        PaceLocalization.text(
            de: "Für diese Kennzahl liegen in Apple Health keine Werte vor.",
            en: "Apple Health has no values for this metric.",
            ru: "В Apple Health нет данных для этого показателя."
        )
    }
}
