import Foundation
import PaceCore

/// Zustand eines Tages im Monatskalender.
public enum CalendarDayStatus: Equatable, Sendable {
    /// Tagesziel erreicht – volle grüne Fläche statt Ring.
    case reached
    /// Gemessen, Ziel (noch) nicht erreicht: Ring mit Fortschritt 0…1. Auch eine gemessene Null.
    case inProgress(fraction: Double)
    /// Keine Daten (außerhalb des geladenen Verlaufs) – klar unterscheidbar von einer gemessenen Null.
    case noData
    /// Nach heute: neutral, ohne Schrittzahl.
    case future
}

/// Ein Tag im Monatsraster.
public struct CalendarDay: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    public let status: CalendarDayStatus
    /// Schritte und Ziel dieses Tages; `nil` ohne Daten und in der Zukunft.
    public let progress: DayGoalProgress?
    public let isToday: Bool
    public let isSelected: Bool
    /// `17`
    public let dayText: String
    /// `8.432` bzw. `–` ohne Daten und in der Zukunft.
    public let stepsText: String
    public let accessibilityLabel: String

    public var id: LocalDate { date }

    /// Vergangene Tage und heute lassen sich auswählen, die Zukunft nicht.
    public var isSelectable: Bool {
        status != .future
    }
}

/// Monatsraster des Kalenders (Referenzbild 9). Reine Berechnung, dadurch testbar.
///
/// - Wochenbeginn und Wochentagsnamen folgen der App-Sprache (Deutsch und Russisch Montag, Englisch Sonntag).
/// - Bewertet wird mit dem Ziel, das am jeweiligen Tag galt (Zielverlauf) – dieselbe Grundlage wie die Streak.
public struct CalendarMonth: Equatable, Sendable {
    public struct Weekday: Equatable, Sendable, Identifiable {
        /// 1 = Sonntag … 7 = Samstag (wie `Calendar`).
        public let weekday: Int
        /// `Mo`, `Mon`, `Пн`
        public let title: String
        /// `Montag`, `Monday`, `Понедельник`
        public let accessibilityLabel: String

        public var id: Int { weekday }
    }

    /// Erster Tag des Monats.
    public let month: LocalDate
    /// `Oktober 2026`
    public let title: String
    public let weekdays: [Weekday]
    /// Zeilenweise, je 7 Einträge; `nil` für Felder vor dem 1. und nach dem letzten Tag.
    public let cells: [CalendarDay?]
    public let canShowPrevious: Bool
    public let canShowNext: Bool

    public var weeks: [[CalendarDay?]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    public var days: [CalendarDay] {
        cells.compactMap { $0 }
    }

    public struct Input: Sendable {
        /// Ein beliebiger Tag im angezeigten Monat.
        public var month: LocalDate
        public var selected: LocalDate?
        /// `nil`, solange kein Verlauf geladen ist – dann sind alle vergangenen Tage „ohne Daten“.
        public var history: ActivityHistory?
        public var goals: StepGoalHistory
        public var today: LocalDate
        /// Frühester Monat, zu dem zurückgeblättert werden kann.
        public var firstMonth: LocalDate
        public var formatter: ActivityFormatter
        public var calendar: ActivityCalendar

        public init(
            month: LocalDate,
            selected: LocalDate?,
            history: ActivityHistory?,
            goals: StepGoalHistory,
            today: LocalDate,
            firstMonth: LocalDate,
            formatter: ActivityFormatter,
            calendar: ActivityCalendar
        ) {
            self.month = month
            self.selected = selected
            self.history = history
            self.goals = goals
            self.today = today
            self.firstMonth = firstMonth
            self.formatter = formatter
            self.calendar = calendar
        }
    }

    public static func make(_ input: Input) -> CalendarMonth {
        let calendar = input.calendar
        let formatter = input.formatter
        let first = calendar.startOfMonth(containing: input.month)
        let last = calendar.endOfMonth(containing: input.month)
        let firstWeekday = formatter.firstWeekday

        // Spalte → Wochentag; die Namen kommen von echten Tagen dieses Monats.
        let weekdayOfFirst = Self.weekday(of: first, calendar: calendar)
        let weekdays = (0..<7).map { column -> Weekday in
            let weekday = (firstWeekday - 1 + column) % 7 + 1
            let sample = calendar.adding((weekday - weekdayOfFirst + 7) % 7, to: first)
            return Weekday(weekday: weekday, title: formatter.weekdayShort(sample), accessibilityLabel: formatter.weekdayLong(sample))
        }

        let leading = (weekdayOfFirst - firstWeekday + 7) % 7
        var cells: [CalendarDay?] = Array(repeating: nil, count: leading)
        for date in calendar.days(from: first, through: last) {
            cells.append(day(date, input: input))
        }
        let trailing = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailing))

        let firstMonth = calendar.startOfMonth(containing: input.firstMonth)
        let currentMonth = calendar.startOfMonth(containing: input.today)
        return CalendarMonth(
            month: first,
            title: formatter.monthYear(first),
            weekdays: weekdays,
            cells: cells,
            canShowPrevious: first > firstMonth,
            canShowNext: first < currentMonth
        )
    }

    /// Zustand eines einzelnen Tages – auch für die Übersicht der letzten 7 Tage.
    public static func status(
        of date: LocalDate,
        history: ActivityHistory?,
        goals: StepGoalHistory,
        today: LocalDate
    ) -> (status: CalendarDayStatus, progress: DayGoalProgress?) {
        if date > today { return (.future, nil) }
        guard let progress = DayGoalProgress(summary: history?.summary(for: date), goals: goals, today: today) else {
            return (.noData, nil)
        }
        return (progress.isReached ? .reached : .inProgress(fraction: min(max(progress.fraction, 0), 1)), progress)
    }

    private static func day(_ date: LocalDate, input: Input) -> CalendarDay {
        let formatter = input.formatter
        let (status, progress) = Self.status(of: date, history: input.history, goals: input.goals, today: input.today)
        let isToday = date == input.today
        let stepsText = progress.map { $0.stepsText(formatter: formatter) } ?? "–"

        var label = formatter.dayLong(date)
        if isToday {
            label += ", " + PaceLocalization.text(de: "heute", en: "today", ru: "сегодня")
        }
        switch status {
        case .future:
            label += ": " + PaceLocalization.text(de: "noch keine Werte", en: "no values yet", ru: "данных пока нет")
        case .noData:
            label += ": " + PaceLocalization.text(de: "keine Daten", en: "no data", ru: "нет данных")
        case .reached, .inProgress:
            if let progress {
                label += ": " + progress.accessibilityText(formatter: formatter)
            }
        }

        return CalendarDay(
            date: date,
            status: status,
            progress: progress,
            isToday: isToday,
            isSelected: date == input.selected,
            dayText: date.day.formatted(.number.locale(formatter.locale)),
            stepsText: stepsText,
            accessibilityLabel: label
        )
    }

    /// 1 = Sonntag … 7 = Samstag.
    static func weekday(of day: LocalDate, calendar: ActivityCalendar) -> Int {
        calendar.calendar.component(.weekday, from: calendar.startOfDay(day))
    }
}
