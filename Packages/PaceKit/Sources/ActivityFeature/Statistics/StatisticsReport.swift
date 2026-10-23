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
/// - Nicht lesbare Kennzahlen erscheinen als „nicht verfügbar“, nie als 0. Tage ohne Samples sind dagegen 0 – außer
///   bei aktiven Kalorien: Dort ist ein Tag ohne Samples „nicht verfügbar“ (gemessene 0 bleibt 0).
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
        public enum Kind: String, Sendable {
            case day, week, month, streak
        }

        public let kind: Kind
        public let title: String
        public let value: String
        public let detail: String?

        public var id: Kind { kind }
    }

    /// „nicht verfügbar“ in der Sprache der App.
    public static var unavailable: String {
        PaceLocalization.text(de: "nicht verfügbar", en: "not available", ru: "нет данных")
    }

    public let period: StatisticsPeriod
    public let metric: StatisticsMetric
    /// Der angezeigte Tag bzw. ein Tag im angezeigten Zeitraum.
    public let anchor: LocalDate
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
                title: PaceLocalization.text(de: "Ø pro Tag", en: "Avg. per day", ru: "В среднем за день"),
                value: metric.formatWithUnit(average, formatter: formatter),
                detail: ActivityTexts.days(values.count),
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
                title: PaceLocalization.text(de: "Zieltage", en: "Goal days", ru: "Дни с целью"),
                value: PaceLocalization.text(de: "\(reached) von \(counted)", en: "\(reached) of \(counted)", ru: "\(reached) из \(counted)"),
                detail: todayReached == false
                    ? PaceLocalization.text(de: "heute läuft noch", en: "today is still open", ru: "сегодня ещё не закончен")
                    : nil,
                isAvailable: true
            ))
        }
        if isAvailable, let best = values.filter({ $0.value > 0 }).max(by: { ($0.value, $0.day.date) < ($1.value, $1.day.date) }) {
            tiles.append(Tile(
                kind: .bestDay,
                title: Texts.bestDay,
                value: metric.formatWithUnit(best.value, formatter: formatter),
                detail: best.day.date == input.today ? Texts.today : formatter.dayWithWeekdayShort(best.day.date),
                isAvailable: true
            ))
        }

        let previous = previousPeriodTotals(input, first: first)
        if isAvailable, let previous {
            tiles.append(Tile(
                kind: .previous,
                title: input.period == .week
                    ? PaceLocalization.text(de: "Vorwoche", en: "Previous week", ru: "Прошлая неделя")
                    : PaceLocalization.text(de: "Vormonat", en: "Previous month", ru: "Прошлый месяц"),
                value: metric.formatWithUnit(previous.total, formatter: formatter),
                detail: Texts.averagePerDay(metric.formatWithUnit(previous.average, formatter: formatter)),
                isAvailable: true
            ))
        }

        // Verglichen werden nur abgeschlossene Tage: Der laufende Tag würde den Schnitt gegenüber den vollständigen
        // Tagen des Vorzeitraums drücken. Am ersten Tag des Zeitraums gibt es deshalb noch keinen Vergleich.
        let completed = values.filter { $0.day.date < input.today }
        let completedAverage = completed.isEmpty ? nil : completed.reduce(0) { $0 + $1.value } / Double(completed.count)
        var comparison: Comparison?
        if isAvailable, let completedAverage, let previous, previous.average > 0 {
            comparison = makeComparison(
                change: completedAverage / previous.average - 1,
                suffix: input.period == .week
                    ? PaceLocalization.text(
                        de: "ggü. Vorwoche (Ø pro Tag)",
                        en: "vs. previous week (avg. per day)",
                        ru: "к прошлой неделе (в среднем за день)"
                    )
                    : PaceLocalization.text(
                        de: "ggü. Vormonat (Ø pro Tag)",
                        en: "vs. previous month (avg. per day)",
                        ru: "к прошлому месяцу (в среднем за день)"
                    ),
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
        // Eine einzige Ziellinie nur, wenn das Ziel im ganzen Zeitraum gleich war – Zieländerungen wirken nicht
        // zurück, die Balkenfarbe richtet sich nach dem Ziel des jeweiligen Tages.
        let hasSingleGoal = Set(elapsed.map { input.goals.goal(on: $0) }).count <= 1
        return StatisticsReport(
            period: input.period,
            metric: metric,
            anchor: input.anchor,
            title: title,
            subtitle: subtitle,
            valueText: isAvailable ? metric.format(total, formatter: formatter) : nil,
            unitText: metric.unit(for: total),
            // Schritte wie auf Home ohne Einheit („Ø 7.473 pro Tag“), Distanz und Kalorien mit („Ø 6,5 km pro Tag“).
            secondaryText: isAvailable ? average.map { value in
                let text = metric == .steps ? metric.format(value, formatter: formatter) : metric.formatWithUnit(value, formatter: formatter)
                return Texts.averagePerDay(text)
            } : nil,
            progress: nil,
            goalReached: nil,
            comparison: comparison,
            bars: bars,
            averageLine: isAvailable ? average.map(metric.chartValue).flatMap { $0 > 0 ? $0 : nil } : nil,
            goalLine: metric == .steps && hasSingleGoal ? Double(input.goals.goal(on: goalDay)) : nil,
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
            if (first...last).contains(input.today) {
                return (PaceLocalization.text(de: "Diese Woche", en: "This week", ru: "Эта неделя"), range)
            }
            if (first...last).contains(calendar.adding(-7, to: input.today)) {
                return (PaceLocalization.text(de: "Letzte Woche", en: "Last week", ru: "Прошлая неделя"), range)
            }
            return (range, nil)
        default:
            let month = formatter.monthYear(first)
            return (first...last).contains(input.today)
                ? (PaceLocalization.text(de: "Dieser Monat", en: "This month", ru: "Этот месяц"), month)
                : (month, nil)
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
                kind: .day,
                title: Texts.bestDay,
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
                kind: .week,
                title: PaceLocalization.text(de: "Beste Woche", en: "Best week", ru: "Лучшая неделя"),
                value: metric.formatWithUnit(best.value, formatter: formatter),
                detail: formatter.dayRange(best.key, calendar.adding(6, to: best.key))
            ))
        }
        if let best = months.filter({ $0.value > 0 }).max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) {
            result.append(Best(
                kind: .month,
                title: PaceLocalization.text(de: "Bester Monat", en: "Best month", ru: "Лучший месяц"),
                value: metric.formatWithUnit(best.value, formatter: formatter),
                detail: formatter.monthYear(best.key)
            ))
        }
        if metric == .steps, let record = input.record, record.days > 0 {
            result.append(Best(
                kind: .streak,
                title: PaceLocalization.text(de: "Längste Serie", en: "Longest streak", ru: "Самая длинная серия"),
                value: ActivityTexts.days(record.days),
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
                let fraction = Double(summary.competitionSteps) / Double(goal)
                progress = fraction
                let goalText = formatter.steps(goal)
                secondary = PaceLocalization.text(
                    de: "von \(goalText) Schritten",
                    en: "of \(goalText) steps",
                    ru: "из \(goalText) шагов"
                ) + " · \(formatter.percent(fraction))"
            }
        }

        // Ohne lesbare Werte dieser Kennzahl keine Stundenbalken – sie zeigten sonst überall 0.
        let bars = isAvailable ? hourlyBars(input) : []
        let comparison = dayComparison(input, value: value)

        var tiles: [Tile] = []
        func metricTile(_ kind: Tile.Kind, _ title: String, _ text: String?) {
            tiles.append(Tile(kind: kind, title: title, value: text ?? unavailable, detail: nil, isAvailable: text != nil))
        }
        metricTile(.steps, StatisticsMetric.steps.title, summary.map { formatter.steps($0.competitionSteps) })
        metricTile(.distance, Texts.distance, summary?.walkingRunningDistanceMeters.map(formatter.distance(meters:)))
        metricTile(.activeEnergy, Texts.activeCalories, summary?.activeEnergyKilocalories.map(formatter.energy(kilocalories:)))
        metricTile(.flights, Texts.floors, summary?.flightsClimbed.map(formatter.flights))
        metricTile(.exercise, Texts.exerciseMinutes, summary?.exerciseMinutes.map(formatter.exerciseMinutes))
        if let summary {
            let reached = StepStreakCalculator.isReached(summary, goals: input.goals)
            let remaining = max(goal - summary.competitionSteps, 0)
            let remainingText = formatter.steps(remaining)
            tiles.append(Tile(
                kind: .goal,
                title: PaceLocalization.text(de: "Tagesziel", en: "Daily goal", ru: "Цель на день"),
                value: reached
                    ? PaceLocalization.text(de: "Erreicht", en: "Reached", ru: "Достигнута")
                    : isToday
                        ? PaceLocalization.text(de: "Noch \(remainingText)", en: "\(remainingText) to go", ru: "Ещё \(remainingText)")
                        : PaceLocalization.text(de: "Nicht erreicht", en: "Not reached", ru: "Не достигнута"),
                detail: PaceLocalization.text(de: "Ziel: ", en: "Goal: ", ru: "Цель: ") + ActivityTexts.steps(goal, formatter: formatter),
                isAvailable: true
            ))
            tiles.append(Tile(
                kind: .progress,
                title: PaceLocalization.text(de: "Fortschritt", en: "Progress", ru: "Прогресс"),
                value: formatter.percent(Double(summary.competitionSteps) / Double(goal)),
                detail: nil,
                isAvailable: true
            ))
        }

        var notes: [String] = []
        if summary == nil {
            notes.append(Texts.noDataForDay)
        } else if !isAvailable {
            notes.append(unavailableNote(metric))
        }
        if let summary, summary.hasNonCompetitionSteps {
            notes.append(Texts.healthStepsNote(summary.healthSteps, formatter: formatter))
        }

        let title: String
        if isToday {
            title = Texts.today
        } else if day == calendar.adding(-1, to: input.today) {
            title = Texts.yesterday
        } else {
            title = formatter.weekdayLong(day)
        }

        return StatisticsReport(
            period: .day,
            metric: metric,
            anchor: input.anchor,
            title: title,
            subtitle: formatter.dayLong(day),
            valueText: value.map { metric.format($0, formatter: formatter) },
            unitText: metric.unit(for: value ?? 5),
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
                accessibilityLabel: Texts.hour(hour),
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
            suffix = PaceLocalization.text(
                de: "ggü. gestern zur gleichen Zeit",
                en: "vs. yesterday at the same time",
                ru: "к вчерашнему дню в это же время"
            )
        } else {
            previous = input.history.summary(for: previousDay).flatMap(input.metric.value(of:))
            suffix = PaceLocalization.text(de: "ggü. Vortag", en: "vs. previous day", ru: "к предыдущему дню")
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
        if metric == .activeEnergy {
            return ActivityTexts.activeEnergyUnavailableNote
        }
        let title = metric.title
        return PaceLocalization.text(
            de: "Für „\(title)“ sind keine Daten lesbar. Prüfe in der Health-App, ob Pace darauf zugreifen darf.",
            en: "No “\(title)” data is readable. Check in the Health app whether Pace has access.",
            ru: "Данные «\(title)» недоступны. Проверь в приложении «Здоровье», есть ли у Pace доступ."
        )
    }
}

/// Wiederkehrende Texte der Statistik und der Tagesdetails.
enum Texts {
    static var today: String { PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня") }
    static var yesterday: String { PaceLocalization.text(de: "Gestern", en: "Yesterday", ru: "Вчера") }
    static var bestDay: String { PaceLocalization.text(de: "Bester Tag", en: "Best day", ru: "Лучший день") }
    static var distance: String { PaceLocalization.text(de: "Distanz", en: "Distance", ru: "Дистанция") }
    static var activeCalories: String { PaceLocalization.text(de: "Aktive Kalorien", en: "Active calories", ru: "Активные калории") }
    static var floors: String { PaceLocalization.text(de: "Stockwerke", en: "Floors", ru: "Этажи") }
    static var exerciseMinutes: String { PaceLocalization.text(de: "Trainingsminuten", en: "Exercise minutes", ru: "Минуты тренировки") }
    static var noDataForDay: String {
        PaceLocalization.text(de: "Für diesen Tag liegen keine Daten vor.", en: "There is no data for this day.", ru: "Для этого дня нет данных.")
    }

    /// „Ø 7.473 pro Tag“
    static func averagePerDay(_ value: String) -> String {
        PaceLocalization.text(de: "Ø \(value) pro Tag", en: "Avg. \(value) per day", ru: "В среднем \(value) в день")
    }

    /// „8 Uhr“ / „8:00“
    static func hour(_ hour: Int) -> String {
        PaceLocalization.text(de: "\(hour) Uhr", en: "\(hour):00", ru: "\(hour):00")
    }

    /// „In Apple Health: 9.120 Schritte. Manuell eingetragene Schritte zählen nicht für Rankings.“
    static func healthStepsNote(_ steps: Int, formatter: ActivityFormatter) -> String {
        let stepsText = ActivityTexts.steps(steps, formatter: formatter)
        return PaceLocalization.text(
            de: "In Apple Health: \(stepsText).",
            en: "In Apple Health: \(stepsText).",
            ru: "В Apple Health: \(stepsText)."
        ) + " " + ActivityTexts.manualStepsNote
    }
}
