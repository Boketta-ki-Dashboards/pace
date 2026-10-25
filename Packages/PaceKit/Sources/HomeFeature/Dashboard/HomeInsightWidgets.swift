import ActivityFeature
import Foundation
import PaceCore
import SocialFeature

// MARK: - Tagesvergleich

/// „Heute vs. gestern bis zur gleichen Uhrzeit“ aus Stundenwerten (Wettbewerbsschritte). Ohne Stundenwerte von
/// gestern gibt es keinen Vergleich – nie einen erfundenen Wert.
public struct HomeDayComparisonWidget: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case ahead, behind, even
    }

    /// Schritte heute (mit Live-Schritten).
    public let todaySteps: Int
    /// Schritte gestern bis zur gleichen Uhrzeit; `nil` ohne Vergleich.
    public let yesterdaySteps: Int?
    /// Schritte gestern insgesamt (aus den Tageswerten); `nil`, wenn unbekannt.
    public let yesterdayTotal: Int?
    public let todayText: String
    public let yesterdayText: String?
    public let yesterdayTotalText: String?
    /// z. B. `+1.242` bzw. `−380`.
    public let differenceText: String?
    /// z. B. `+17 %`; `nil`, wenn gestern bis jetzt 0 Schritte (kein sinnvoller Prozentwert).
    public let percentText: String?
    public let direction: Direction
    /// z. B. `bis 14:20`.
    public let timeText: String

    public static var unavailableText: String {
        PaceLocalization.text(de: "Noch kein Vergleich verfügbar", en: "No comparison available yet", ru: "Сравнение пока недоступно")
    }

    /// - Parameters:
    ///   - yesterdayHourly: Stundenwerte von gestern (Stunde → Schritte); `nil` oder leer = kein Vergleich.
    ///   - currentHour/fractionOfCurrentHour: Uhrzeit jetzt (z. B. 14 und 0,33 für 14:20).
    public init(
        todaySteps: Int,
        yesterdayHourly: [Int: Double]?,
        yesterdayTotal: Int?,
        currentHour: Int,
        fractionOfCurrentHour: Double,
        timeText: String,
        formatter: ActivityFormatter
    ) {
        self.todaySteps = max(todaySteps, 0)
        self.yesterdayTotal = yesterdayTotal
        self.timeText = timeText
        todayText = formatter.steps(self.todaySteps)
        yesterdayTotalText = yesterdayTotal.map { formatter.steps($0) }
        if let hourly = yesterdayHourly, !hourly.isEmpty {
            let hour = min(max(currentHour, 0), 23)
            let fullHours = (0..<hour).reduce(0.0) { $0 + (hourly[$1] ?? 0) }
            let partial = (hourly[hour] ?? 0) * min(max(fractionOfCurrentHour, 0), 1)
            let yesterday = Int((fullHours + partial).rounded())
            yesterdaySteps = yesterday
            yesterdayText = formatter.steps(yesterday)
            let difference = self.todaySteps - yesterday
            direction = difference > 0 ? .ahead : difference < 0 ? .behind : .even
            let sign = difference > 0 ? "+" : difference < 0 ? "−" : "±"
            differenceText = sign + formatter.steps(abs(difference))
            percentText = yesterday > 0 ? formatter.signedPercent(Double(self.todaySteps) / Double(yesterday) - 1) : nil
        } else {
            yesterdaySteps = nil
            yesterdayText = nil
            direction = .even
            differenceText = nil
            percentText = nil
        }
    }

    public var isAvailable: Bool {
        yesterdaySteps != nil
    }

    /// Anteil für die Vergleichsbalken (heute bzw. gestern am größeren Wert gemessen).
    public var todayLevel: Double {
        level(todaySteps)
    }

    public var yesterdayLevel: Double {
        level(yesterdaySteps ?? 0)
    }

    private func level(_ value: Int) -> Double {
        let top = max(todaySteps, yesterdaySteps ?? 0, 1)
        return Double(value) / Double(top)
    }

    /// Satz für Klein/Mittel, z. B. „1.242 mehr als gestern um diese Zeit“.
    public var headline: String {
        guard let yesterdaySteps else { return Self.unavailableText }
        let difference = abs(todaySteps - yesterdaySteps).paceFormatted
        switch direction {
        case .ahead:
            return PaceLocalization.text(
                de: "\(difference) mehr als gestern um diese Zeit",
                en: "\(difference) more than yesterday at this time",
                ru: "На \(difference) больше, чем вчера в это время"
            )
        case .behind:
            return PaceLocalization.text(
                de: "\(difference) weniger als gestern um diese Zeit",
                en: "\(difference) fewer than yesterday at this time",
                ru: "На \(difference) меньше, чем вчера в это время"
            )
        case .even:
            return PaceLocalization.text(
                de: "Genau wie gestern um diese Zeit",
                en: "Exactly like yesterday at this time",
                ru: "Ровно как вчера в это время"
            )
        }
    }
}

// MARK: - Aktivitätszeiten

/// Wann du heute aktiv warst: Stundenwerte (Wettbewerbsschritte) in Tageszeiten zusammengefasst. Ohne Stundenwerte
/// bleibt das Widget leer – es wird keine Verteilung aus der Tagessumme erfunden.
public struct HomeActivityTimesWidget: Equatable, Sendable {
    public struct Bucket: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// z. B. `5–11 Uhr`.
        public let hours: String
        public let steps: Int
        public let stepsText: String
        /// 0…1, gemessen an der aktivsten Tageszeit.
        public let level: Double
        public let isPeak: Bool
        /// Die laufende Tageszeit.
        public let isCurrent: Bool
    }

    public struct Hour: Equatable, Sendable, Identifiable {
        public let hour: Int
        public let steps: Int
        public let level: Double
        public let isCurrent: Bool
        public var id: Int { hour }
    }

    /// Tageszeiten: Nacht 0–5, Morgen 5–11, Mittag 11–14, Nachmittag 14–18, Abend 18–24.
    static let ranges: [(id: String, range: Range<Int>)] = [
        ("night", 0..<5), ("morning", 5..<11), ("midday", 11..<14), ("afternoon", 14..<18), ("evening", 18..<24),
    ]

    public let buckets: [Bucket]
    public let hours: [Hour]
    public let totalSteps: Int

    public init(hourly: [Int: Double]?, currentHour: Int, formatter: ActivityFormatter) {
        let values = hourly ?? [:]
        let steps = (0..<24).map { Int((values[$0] ?? 0).rounded()) }
        totalSteps = steps.reduce(0, +)
        let maxHour = max(steps.max() ?? 0, 1)
        hours = (0..<24).map { hour in
            Hour(hour: hour, steps: steps[hour], level: Double(steps[hour]) / Double(maxHour), isCurrent: hour == currentHour)
        }
        let sums = Self.ranges.map { entry in entry.range.reduce(0) { $0 + steps[$1] } }
        let top = max(sums.max() ?? 0, 1)
        let peak = sums.max() ?? 0
        buckets = zip(Self.ranges, sums).map { entry, sum in
            Bucket(
                id: entry.id,
                title: Self.title(entry.id),
                hours: Self.hoursText(entry.range),
                steps: sum,
                stepsText: formatter.steps(sum),
                level: Double(sum) / Double(top),
                isPeak: peak > 0 && sum == peak,
                isCurrent: entry.range.contains(currentHour)
            )
        }
    }

    public var isEmpty: Bool {
        totalSteps == 0
    }

    public var peak: Bucket? {
        buckets.first(where: \.isPeak)
    }

    public static var emptyText: String {
        PaceLocalization.text(
            de: "Für heute gibt es noch keine Stundenwerte.",
            en: "There are no hourly values for today yet.",
            ru: "Почасовых данных за сегодня пока нет."
        )
    }

    /// z. B. „Am aktivsten: Nachmittag“.
    public var peakText: String? {
        peak.map { PaceLocalization.text(de: "Am aktivsten: \($0.title)", en: "Most active: \($0.title)", ru: "Больше всего: \($0.title)") }
    }

    static func title(_ id: String) -> String {
        switch id {
        case "night": PaceLocalization.text(de: "Nacht", en: "Night", ru: "Ночь")
        case "morning": PaceLocalization.text(de: "Morgen", en: "Morning", ru: "Утро")
        case "midday": PaceLocalization.text(de: "Mittag", en: "Midday", ru: "Полдень")
        case "afternoon": PaceLocalization.text(de: "Nachmittag", en: "Afternoon", ru: "День")
        default: PaceLocalization.text(de: "Abend", en: "Evening", ru: "Вечер")
        }
    }

    static func hoursText(_ range: Range<Int>) -> String {
        PaceLocalization.text(
            de: "\(range.lowerBound)–\(range.upperBound) Uhr",
            en: "\(range.lowerBound)–\(range.upperBound) h",
            ru: "\(range.lowerBound)–\(range.upperBound) ч"
        )
    }
}

// MARK: - Persönliche Rekorde

/// Wählbarer Rekord des Widgets „Persönliche Rekorde“. Rohwerte werden gespeichert.
public enum HomeRecordKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case bestDay, bestWeek, bestMonth, longestStreak, currentStreak, longestDistance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bestDay: PaceLocalization.text(de: "Bester Tag", en: "Best day", ru: "Лучший день")
        case .bestWeek: PaceLocalization.text(de: "Beste Woche", en: "Best week", ru: "Лучшая неделя")
        case .bestMonth: PaceLocalization.text(de: "Bester Monat", en: "Best month", ru: "Лучший месяц")
        case .longestStreak: PaceLocalization.text(de: "Längste Flamme", en: "Longest flame", ru: "Самый долгий огонь")
        case .currentStreak: PaceLocalization.text(de: "Aktuelle Flamme", en: "Current flame", ru: "Текущий огонь")
        case .longestDistance: PaceLocalization.text(de: "Größte Distanz", en: "Longest distance", ru: "Самая большая дистанция")
        }
    }

    public var systemImage: String {
        switch self {
        case .bestDay: "trophy"
        case .bestWeek: "calendar"
        case .bestMonth: "calendar.badge.clock"
        case .longestStreak: "flame.fill"
        case .currentStreak: "flame"
        case .longestDistance: "shoeprints.fill"
        }
    }

    var reportKind: StatisticsReport.Best.Kind {
        switch self {
        case .bestDay: .day
        case .bestWeek: .week
        case .bestMonth: .month
        case .longestStreak: .streak
        case .currentStreak: .currentStreak
        case .longestDistance: .distanceDay
        }
    }
}

/// Persönliche Rekorde aus dem geladenen Verlauf (12 Monate) – dieselben Werte wie in der Statistik.
public struct HomeRecordsWidget: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let kind: HomeRecordKind
        public let value: String
        public let detail: String?
        public var id: HomeRecordKind { kind }
        public var title: String { kind.title }
    }

    public let entries: [Entry]
    public let selected: HomeRecordKind

    public init(bests: [StatisticsReport.Best], selected: HomeRecordKind) {
        self.selected = selected
        entries = HomeRecordKind.allCases.compactMap { kind in
            bests.first { $0.kind == kind.reportKind }.map { Entry(kind: kind, value: $0.value, detail: $0.detail) }
        }
    }

    /// Der gewählte Rekord; `nil`, solange es dafür keinen Wert gibt (z. B. noch keine Serie).
    public var primary: Entry? {
        entries.first { $0.kind == selected }
    }

    /// Weitere Rekorde (ohne den gewählten).
    public var others: [Entry] {
        entries.filter { $0.kind != selected }
    }

    /// Zeitraum, aus dem die Rekorde stammen.
    public static var periodText: String {
        PaceLocalization.text(de: "Letzte 12 Monate", en: "Last 12 months", ru: "Последние 12 месяцев")
    }

    public static var emptyText: String {
        PaceLocalization.text(
            de: "Noch kein Rekord – sobald Schritte im Verlauf sind, erscheint er hier.",
            en: "No record yet – it appears once your history has steps.",
            ru: "Рекорда пока нет – он появится, когда в истории будут шаги."
        )
    }
}

// MARK: - Gruppenfortschritt

/// Fortschritt einer gewählten Gruppe heute – aus den vorhandenen Gruppendaten, ohne zusätzliche Abfrage.
public enum HomeGroupProgressWidget: Equatable, Sendable {
    case group(GroupSummary, GroupDayProgress)
    /// Noch keine Gruppe gewählt.
    case unselected
    /// Die gewählte Gruppe gibt es für dich nicht mehr (verlassen oder gelöscht).
    case missing
    /// Gruppen werden noch geladen.
    case loading

    public init(groupID: UUID?, groups: [GroupSummary], isLoaded: Bool) {
        guard let groupID else {
            self = .unselected
            return
        }
        if let group = groups.first(where: { $0.id == groupID }) {
            self = .group(group, GroupDayProgress(group: group))
        } else {
            self = isLoaded ? .missing : .loading
        }
    }

    public static var unselectedText: String {
        PaceLocalization.text(
            de: "Wähle beim Bearbeiten eine Gruppe aus.",
            en: "Choose a group when editing.",
            ru: "Выбери группу при редактировании."
        )
    }

    public static var missingText: String {
        PaceLocalization.text(
            de: "Du bist nicht mehr in dieser Gruppe oder sie wurde gelöscht. Wähle eine andere Gruppe oder entferne das Widget.",
            en: "You're no longer in this group or it was deleted. Choose another group or remove the widget.",
            ru: "Ты больше не в этой группе, или она удалена. Выбери другую группу или удали виджет."
        )
    }
}
