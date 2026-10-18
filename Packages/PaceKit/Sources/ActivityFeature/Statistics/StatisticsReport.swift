import Foundation
import PaceCore

/// Stundenwerte eines Tages für das Tagesdiagramm, optional mit dem Vortag für den Vergleich „zur gleichen Zeit“.
public struct HourlyValues: Equatable, Sendable {
    public let day: LocalDate
    public let metric: StatisticsMetric
    /// Stunde (0–23) → Rohwert. Stunden ohne Samples fehlen.
    public let values: [Int: Double]
    public let previousDay: [Int: Double]?

    public init(day: LocalDate, metric: StatisticsMetric, values: [Int: Double], previousDay: [Int: Double]?) {
        self.day = day
        self.metric = metric
        self.values = values
        self.previousDay = previousDay
    }
}

/// Alles, was die Statistik für einen Zeitraum und eine Kennzahl anzeigt. Reine Berechnung, dadurch testbar.
///
/// Grundsätze:
/// - Nicht lesbare Kennzahlen erscheinen als „nicht verfügbar“, nie als 0. Tage ohne Samples sind dagegen 0.
/// - Schritte sind immer Wettbewerbsschritte (ohne manuell eingetragene) – wie Ziel, Streak und Rankings.
/// - Durchschnitte beziehen sich auf die bereits begonnenen Tage des Zeitraums (inklusive heute).
/// - Zieltage nutzen das Ziel des jeweiligen Tages (Zielverlauf). Heute zählt mit, sobald das Ziel erreicht ist.
public struct StatisticsReport: Equatable, Sendable {
    public struct Bar: Equatable, Sendable, Identifiable {
        public let id: String
        /// Beschriftung der Achse, z. B. `Mo`, `12` (Tag im Monat) oder `8` (Stunde).
        public let label: String
        public let accessibilityLabel: String
        /// Tag des Balkens in Woche und Monat (antippbar); `nil` bei Stunden.
        public let day: LocalDate?
        /// Wert in Diagrammeinheit; `nil` für Zukunft oder fehlende Daten.
        public let value: Double?
        public let reachedGoal: Bool
        /// Heute bzw. die laufende Stunde.
        public let isCurrent: Bool
    }

    public struct Tile: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case steps, distance, activeEnergy, flights, exercise, goal, progress, average, goalDays, bestDay, previous
        }

        public let kind: Kind
        public let title: String
        public let value: String
        public let detail: String?
        /// `false` für „nicht verfügbar“.
        public let isAvailable: Bool

        public var id: Kind { kind }
    }

    public struct Comparison: Equatable, Sendable {
        public enum Direction: Sendable {
            case up, down, same
        }

        public let direction: Direction
        /// z. B. `+12 % ggü. Vorwoche`
        public let text: String

        public init(direction: Direction, text: String) {
            self.direction = direction
            self.text = text
        }
    }

    public struct Best: Equatable, Sendable, Identifiable {
        public let title: String
        public let value: String
        public let detail: String?

        public var id: String { title }
    }

    public static let unavailable = "nicht verfügbar"

    public let period: StatisticsPeriod
    public let metric: StatisticsMetric
    public let title: String
    public let subtitle: String?
    /// Große Zahl ohne Einheit; `nil`, wenn die Kennzahl nicht verfügbar ist.
    public let valueText: String?
    public let unitText: String
    /// z. B. `Ø 7.473 pro Tag` oder `von 10.000 Schritten · 87 %`.
    public let secondaryText: String?
    /// Fortschritt zum Tagesziel (nur Tag + Schritte).
    public let progress: Double?
    public let goalReached: Bool?
    public let comparison: Comparison?
    public let bars: [Bar]
    public let averageLine: Double?
    public let goalLine: Double?
    public let tiles: [Tile]
    public let bests: [Best]
    public let notes: [String]
    public let isMetricAvailable: Bool
    public let canShowPrevious: Bool
    public let canShowNext: Bool

    /// Eingaben für die Berechnung.
    public struct Input: Sendable {
        public var period: StatisticsPeriod
        public var metric: StatisticsMetric
        /// Ein beliebiger Tag im angezeigten Zeitraum.
        public var anchor: LocalDate
        public var history: ActivityHistory
        public var goals: StepGoalHistory
        public var record: StepStreakRecord?
        public var hourly: HourlyValues?
        public var today: LocalDate
        /// Laufende Stunde (0–23) und bereits vergangener Anteil davon – für Tagesdiagramm und Vergleich.
        public var currentHour: Int
        public var fractionOfCurrentHour: Double
        public var formatter: ActivityFormatter
        public var calendar: ActivityCalendar

        public init(
            period: StatisticsPeriod,
            metric: StatisticsMetric,
            anchor: LocalDate,
            history: ActivityHistory,
            goals: StepGoalHistory,
            record: StepStreakRecord? = nil,
            hourly: HourlyValues? = nil,
            today: LocalDate,
            currentHour: Int,
            fractionOfCurrentHour: Double,
            formatter: ActivityFormatter,
            calendar: ActivityCalendar
        ) {
            self.period = period
            self.metric = metric
            self.anchor = anchor
            self.history = history
            self.goals = goals
            self.record = record
            self.hourly = hourly
            self.today = today
            self.currentHour = currentHour
            self.fractionOfCurrentHour = fractionOfCurrentHour
            self.formatter = formatter
            self.calendar = calendar
        }
    }

    public static func make(_ input: Input) -> StatisticsReport {
        switch input.period {
        case .day: makeDay(input)
        case .week, .month: makeRange(input)
        }
    }

    // MARK: - Woche und Monat

    private static func makeRange(_ input: Input) -> StatisticsReport {
        let calendar = input.calendar
        let formatter = input.formatter
        let metric = input.metric
        let (first, last) = bounds(of: input.period, containing: input.anchor, calendar: calendar)
        let days = calendar.days(from: first, through: last)
        let elapsed = days.filter { $0 <= input.today }
        let known = elapsed.compactMap { input.history.summary(for: $0) }
        let isAvailable = metric == .steps || known.isEmpty || known.contains { metric.value(of: $0) != nil }

        let values = known.compactMap { day in metric.value(of: day).map { (day: day, value: $0) } }
        let total = values.reduce(0) { $0 + $1.value }
        let average = values.isEmpty ? nil : total / Double(values.count)

        let bars = days.map { day -> Bar in
            let summary = day <= input.today ? input.history.summary(for: day) : nil
            return Bar(
                id: day.isoString,
                label: input.period == .week ? formatter.weekdayShort(day) : "\(day.day)",
                accessibilityLabel: formatter.dayLong(day),
                day: day,
                value: summary.flatMap(metric.value(of:)).map(metric.chartValue),
                reachedGoal: metric == .steps && summary.map { StepStreakCalculator.isReached($0, goals: input.goals) } == true,
                isCurrent: day == input.today
            )
        }

        var tiles: [Tile] = []
        if isAvailable, let average {
            tiles.append(Tile(
                kind: .average,
                title: "Ø pro Tag",
                value: metric.formatWithUnit(average, formatter: formatter),
                detail: values.count == 1 ? "1 Tag" : "\(values.count) Tage",
                isAvailable: true
            ))
        }
        if metric == .steps, !known.isEmpty {
            let past = known.filter { $0.date < input.today }
            let todayReached = known.first { $0.date == input.today }.map { StepStreakCalculator.isReached($0, goals: input.goals) }
            let reached = past.filter { StepStreakCalculator.isReached($0, goals: input.goals) }.count + (todayReached == true ? 1 : 0)
            let counted = past.count + (todayReached == true ? 1 : 0)
            tiles.append(Tile(
                kind: .goalDays,
                title: "Zieltage",
                value: "\(reached) von \(counted)",
                detail: todayReached == false ? "heute läuft noch" : nil,
                isAvailable: true
            ))
        }
        if isAvailable, let best = values.filter({ $0.value > 0 }).max(by: { ($0.value, $0.day.date) < ($1.value, $1.day.date) }) {
            tiles.append(Tile(
                kind: .bestDay,
                title: "Bester Tag",
                value: metric.formatWithUnit(best.value, formatter: formatter),
                detail: best.day.date == input.today ? "Heute" : formatter.dayWithWeekdayShort(best.day.date),
                isAvailable: true
            ))
        }

        let previous = previousPeriodTotals(input, first: first)
        if isAvailable, let previous {
            tiles.append(Tile(
                kind: .previous,
                title: input.period == .week ? "Vorwoche" : "Vormonat",
                value: metric.formatWithUnit(previous.total, formatter: formatter),
                detail: "Ø \(metric.formatWithUnit(previous.average, formatter: formatter)) pro Tag",
                isAvailable: true
            ))
        }

        var comparison: Comparison?
        if isAvailable, let average, let previous, previous.average > 0 {
            comparison = makeComparison(
                change: average / previous.average - 1,
                suffix: input.period == .week ? "ggü. Vorwoche (Ø pro Tag)" : "ggü. Vormonat (Ø pro Tag)",
                formatter: formatter
            )
        }

        var notes: [String] = []
        if !isAvailable {
            notes.append(unavailableNote(metric))
        }
        if metric == .steps, known.contains(where: \.hasNonCompetitionSteps) {
            notes.append(ActivityTexts.manualStepsNote)
        }

        let (title, subtitle) = rangeTitle(input, first: first, last: last)
        let goalDay = min(last, input.today)
        return StatisticsReport(
            period: input.period,
            metric: metric,
            title: title,
            subtitle: subtitle,
            valueText: isAvailable ? metric.format(total, formatter: formatter) : nil,
            unitText: metric.unit,
            secondaryText: isAvailable ? average.map { "Ø \(metric.format($0, formatter: formatter)) pro Tag" } : nil,
            progress: nil,
            goalReached: nil,
            comparison: comparison,
            bars: bars,
            averageLine: isAvailable ? average.map(metric.chartValue).flatMap { $0 > 0 ? $0 : nil } : nil,
            goalLine: metric == .steps ? Double(input.goals.goal(on: goalDay)) : nil,
            tiles: tiles,
            bests: isAvailable ? bests(input) : [],
            notes: notes,
            isMetricAvailable: isAvailable,
            canShowPrevious: calendar.adding(-1, to: first) >= input.history.range.lowerBound,
            canShowNext: calendar.adding(1, to: last) <= input.today
        )
    }

    /// Summe und Tagesdurchschnitt des vorherigen Zeitraums – nur, wenn er vollständig im Verlauf liegt.
    private static func previousPeriodTotals(_ input: Input, first: LocalDate) -> (total: Double, average: Double)? {
        let calendar = input.calendar
        let previousAnchor = calendar.adding(-1, to: first)
        let (previousFirst, previousLast) = bounds(of: input.period, containing: previousAnchor, calendar: calendar)
        let days = calendar.days(from: previousFirst, through: previousLast)
        let summaries = days.compactMap { input.history.summary(for: $0) }
        guard summaries.count == days.count else { return nil }
        let values = summaries.compactMap { input.metric.value(of: $0) }
        guard values.count == days.count else { return nil }
        let total = values.reduce(0, +)
        return (total, total / Double(days.count))
    }

    private static func rangeTitle(_ input: Input, first: LocalDate, last: LocalDate) -> (String, String?) {
        let formatter = input.formatter
        let calendar = input.calendar
        switch input.period {
        case .week:
            let range = formatter.dayRange(first, last)
            if (first...last).contains(input.today) { return ("Diese Woche", range) }
            if (first...last).contains(calendar.adding(-7, to: input.today)) { return ("Letzte Woche", range) }
            return (range, nil)
        default:
            let month = formatter.monthYear(first)
            return (first...last).contains(input.today) ? ("Dieser Monat", month) : (month, nil)
        }
    }

    /// Bestwerte im geladenen Verlauf (bis zu 12 Monate) für die gewählte Kennzahl.
    private static func bests(_ input: Input) -> [Best] {
        let calendar = input.calendar
        let formatter = input.formatter
        let metric = input.metric
        let history = input.history
        let lower = history.range.lowerBound
        let upper = min(history.range.upperBound, input.today)
        guard lower <= upper else { return [] }
        let days = history.summaries(from: lower, through: upper, calendar: calendar)
        var result: [Best] = []

        let dayValues = days.compactMap { day in metric.value(of: day).map { (day.date, $0) } }
        if let best = dayValues.filter({ $0.1 > 0 }).max(by: { ($0.1, $0.0) < ($1.1, $1.0) }) {
            result.append(Best(
                title: "Bester Tag",
                value: metric.formatWithUnit(best.1, formatter: formatter),
                detail: formatter.dayWithWeekdayShort(best.0)
            ))
        }

        // Nur Wochen und Monate, die vollständig im Verlauf beginnen (keine angeschnittenen Zeiträume am Anfang).
        var weeks: [LocalDate: Double] = [:]
        var months: [LocalDate: Double] = [:]
        for (day, value) in dayValues {
            let week = calendar.startOfWeek(containing: day)
            if week >= lower { weeks[week, default: 0] += value }
            let month = calendar.startOfMonth(containing: day)
            if month >= lower { months[month, default: 0] += value }
        }
        if let best = weeks.filter({ $0.value > 0 }).max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) {
            result.append(Best(
                title: "Beste Woche",
                value: metric.formatWithUnit(best.value, formatter: formatter),
                detail: formatter.dayRange(best.key, calendar.adding(6, to: best.key))
            ))
        }
        if let best = months.filter({ $0.value > 0 }).max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) {
            result.append(Best(
                title: "Bester Monat",
                value: metric.formatWithUnit(best.value, formatter: formatter),
                detail: formatter.monthYear(best.key)
            ))
        }
        if metric == .steps, let record = input.record, record.days > 0 {
            result.append(Best(
                title: "Längste Serie",
                value: record.days == 1 ? "1 Tag" : "\(record.days) Tage",
                detail: formatter.dayRange(record.start, record.end)
            ))
        }
        return result
    }

    // MARK: - Tag

    private static func makeDay(_ input: Input) -> StatisticsReport {
        let calendar = input.calendar
        let formatter = input.formatter
        let metric = input.metric
        let day = input.anchor
        let isToday = day == input.today
        let summary = input.history.summary(for: day)
        let value = summary.flatMap(metric.value(of:))
        let isAvailable = summary == nil || value != nil

        var progress: Double?
        var goalReached: Bool?
        var secondary: String?
        let goal = input.goals.goal(on: day)
        if let summary {
            let reached = StepStreakCalculator.isReached(summary, goals: input.goals)
            goalReached = reached
            if metric == .steps {
                progress = Double(summary.competitionSteps) / Double(goal)
                secondary = "von \(formatter.steps(goal)) Schritten · \(formatter.percent(progress ?? 0))"
            }
        }

        let bars = hourlyBars(input)
        let comparison = dayComparison(input, value: value)

        var tiles: [Tile] = []
        func metricTile(_ kind: Tile.Kind, _ title: String, _ text: String?) {
            tiles.append(Tile(kind: kind, title: title, value: text ?? unavailable, detail: nil, isAvailable: text != nil))
        }
        metricTile(.steps, "Schritte", summary.map { formatter.steps($0.competitionSteps) })
        metricTile(.distance, "Distanz", summary?.walkingRunningDistanceMeters.map(formatter.distance(meters:)))
        metricTile(.activeEnergy, "Aktive Kalorien", summary?.activeEnergyKilocalories.map(formatter.energy(kilocalories:)))
        metricTile(.flights, "Stockwerke", summary?.flightsClimbed.map(formatter.flights))
        metricTile(.exercise, "Trainingsminuten", summary?.exerciseMinutes.map(formatter.exerciseMinutes))
        if let summary {
            let reached = StepStreakCalculator.isReached(summary, goals: input.goals)
            let remaining = max(goal - summary.competitionSteps, 0)
            tiles.append(Tile(
                kind: .goal,
                title: "Tagesziel",
                value: reached ? "Erreicht" : isToday ? "Noch \(formatter.steps(remaining))" : "Nicht erreicht",
                detail: "Ziel: \(formatter.steps(goal)) Schritte",
                isAvailable: true
            ))
            tiles.append(Tile(
                kind: .progress,
                title: "Fortschritt",
                value: formatter.percent(Double(summary.competitionSteps) / Double(goal)),
                detail: nil,
                isAvailable: true
            ))
        }

        var notes: [String] = []
        if summary == nil {
            notes.append("Für diesen Tag liegen keine Daten vor.")
        } else if !isAvailable {
            notes.append(unavailableNote(metric))
        }
        if let summary, summary.hasNonCompetitionSteps {
            notes.append("In Apple Health: \(formatter.steps(summary.healthSteps)) Schritte. \(ActivityTexts.manualStepsNote)")
        }

        let title: String
        if isToday {
            title = "Heute"
        } else if day == calendar.adding(-1, to: input.today) {
            title = "Gestern"
        } else {
            title = formatter.weekdayLong(day)
        }

        return StatisticsReport(
            period: .day,
            metric: metric,
            title: title,
            subtitle: formatter.dayLong(day),
            valueText: value.map { metric.format($0, formatter: formatter) },
            unitText: metric.unit,
            secondaryText: secondary,
            progress: progress,
            goalReached: goalReached,
            comparison: comparison,
            bars: bars,
            averageLine: nil,
            goalLine: nil,
            tiles: tiles,
            bests: [],
            notes: notes,
            isMetricAvailable: isAvailable,
            canShowPrevious: calendar.adding(-1, to: day) >= input.history.range.lowerBound,
            canShowNext: calendar.adding(1, to: day) <= input.today
        )
    }

    /// 24 Stundenbalken, sobald die Stundenwerte dieses Tages und dieser Kennzahl geladen sind.
    private static func hourlyBars(_ input: Input) -> [Bar] {
        guard let hourly = input.hourly, hourly.day == input.anchor, hourly.metric == input.metric else { return [] }
        let isToday = input.anchor == input.today
        return (0..<24).map { hour in
            let isFuture = isToday && hour > input.currentHour
            return Bar(
                id: "h\(hour)",
                label: "\(hour)",
                accessibilityLabel: "\(hour) Uhr",
                day: nil,
                value: isFuture ? nil : input.metric.chartValue(hourly.values[hour] ?? 0),
                reachedGoal: false,
                isCurrent: isToday && hour == input.currentHour
            )
        }
    }

    /// Heute: ggü. gestern zur gleichen Uhrzeit (aus Stundenwerten). Vergangene Tage: ggü. dem ganzen Vortag.
    private static func dayComparison(_ input: Input, value: Double?) -> Comparison? {
        guard let value else { return nil }
        let previousDay = input.calendar.adding(-1, to: input.anchor)
        let previous: Double?
        let suffix: String
        if input.anchor == input.today {
            guard let hourly = input.hourly, hourly.day == input.anchor, hourly.metric == input.metric,
                  let yesterday = hourly.previousDay
            else { return nil }
            let fullHours = (0..<input.currentHour).reduce(0) { $0 + (yesterday[$1] ?? 0) }
            previous = fullHours + (yesterday[input.currentHour] ?? 0) * min(max(input.fractionOfCurrentHour, 0), 1)
            suffix = "ggü. gestern zur gleichen Zeit"
        } else {
            previous = input.history.summary(for: previousDay).flatMap(input.metric.value(of:))
            suffix = "ggü. Vortag"
        }
        guard let previous, previous > 0 else { return nil }
        return makeComparison(change: value / previous - 1, suffix: suffix, formatter: input.formatter)
    }

    // MARK: - Hilfen

    static func bounds(of period: StatisticsPeriod, containing day: LocalDate, calendar: ActivityCalendar) -> (LocalDate, LocalDate) {
        switch period {
        case .day: (day, day)
        case .week: (calendar.startOfWeek(containing: day), calendar.endOfWeek(containing: day))
        case .month: (calendar.startOfMonth(containing: day), calendar.endOfMonth(containing: day))
        }
    }

    private static func makeComparison(change: Double, suffix: String, formatter: ActivityFormatter) -> Comparison {
        let rounded = Int((change * 100).rounded())
        return Comparison(
            direction: rounded > 0 ? .up : rounded < 0 ? .down : .same,
            text: "\(formatter.signedPercent(change)) \(suffix)"
        )
    }

    private static func unavailableNote(_ metric: StatisticsMetric) -> String {
        "Für „\(metric.title)“ sind keine Daten lesbar. Prüfe in der Health-App, ob Pace darauf zugreifen darf."
    }
}
