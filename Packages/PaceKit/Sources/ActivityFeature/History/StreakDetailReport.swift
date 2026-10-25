import Foundation
import PaceCore

/// Persönliche Flamme im Detail (aus dem Flammen-Widget): aktuelle Serie, Rekord, Beginn, letzter erfolgreicher Tag,
/// frühere Serien, Erklärung und ein Flammenkalender mit Tagesdetails. Reine Berechnung, dadurch testbar.
///
/// Grundlage ist dieselbe Regel wie überall (``StepStreakCalculator``): Wettbewerbsschritte gegen das am jeweiligen Tag
/// gültige Ziel. Ausgewertet wird der geladene Verlauf (12 Monate); was davor lag, wird nicht erfunden – nur ein
/// gespeicherter Rekord kann älter sein.
public struct StreakDetailReport: Equatable, Sendable {
    /// Eine abgeschlossene oder laufende Serie.
    public struct Run: Equatable, Sendable, Identifiable {
        public let start: LocalDate
        public let end: LocalDate
        public let days: Int
        public let isCurrent: Bool
        /// z. B. `12 Tage`.
        public let daysText: String
        /// z. B. `3.–14. Okt.`
        public let rangeText: String

        public var id: LocalDate { start }
    }

    public enum CellState: Equatable, Sendable {
        case reached
        case missed
        /// Heute, Ziel noch offen.
        case pending
        case future
        /// Kein Tageswert (außerhalb des geladenen Verlaufs).
        case noData
    }

    public struct Cell: Equatable, Sendable, Identifiable {
        public let day: LocalDate
        public let state: CellState
        public let isToday: Bool
        public let isSelected: Bool
        /// Erster bzw. letzter Tag einer Serie (Serie beginnt hier bzw. endete hier).
        public let isRunStart: Bool
        public let isRunEnd: Bool
        public let accessibilityLabel: String

        public var id: LocalDate { day }
        /// Antippbar: Tage bis heute.
        public var isSelectable: Bool { state != .future }
    }

    /// Details des ausgewählten Tags.
    public struct SelectedDay: Equatable, Sendable {
        public let day: LocalDate
        public let title: String
        /// z. B. `9.420 von 8.000 Schritten`; `nil` ohne Daten.
        public let stepsText: String?
        /// z. B. `Ziel an diesem Tag: 8.000 Schritte`.
        public let goalText: String
        public let state: CellState
        /// z. B. „Flamme fortgesetzt – Tag 5 der Serie“.
        public let statusText: String
        /// Länge der Serie an diesem Tag (0, wenn nicht erreicht).
        public let runLength: Int
    }

    public let currentDays: Int
    /// z. B. `5 Tage` bzw. `365+ Tage` (reicht bis zum Anfang des Verlaufs).
    public let currentText: String
    public let isTodayReached: Bool
    public let statusText: String
    /// Beginn der aktuellen Serie, z. B. `Mo., 12. Okt.`; `nil` ohne laufende Serie.
    public let currentStartText: String?
    /// Letzter Tag mit erreichtem Ziel; `nil`, wenn es im Verlauf keinen gibt.
    public let lastReachedText: String?
    /// Rekord (gespeichert oder im Verlauf); `nil` ohne Rekord.
    public let recordText: String?
    public let recordRangeText: String?
    /// Frühere Serien ab 2 Tagen, neueste zuerst (höchstens ``maximumRuns``).
    public let pastRuns: [Run]
    public let monthTitle: String
    public let weekdays: [String]
    /// Wochen ab Montag; `nil` für Tage außerhalb des Monats.
    public let weeks: [[Cell?]]
    public let selected: SelectedDay?
    public let canShowPreviousMonth: Bool
    public let canShowNextMonth: Bool
    /// Hinweis auf den ausgewerteten Zeitraum.
    public let historyNote: String

    public static let maximumRuns = 10

    public static func make(
        history: ActivityHistory,
        goals: StepGoalHistory,
        record storedRecord: StepStreakRecord?,
        today: LocalDate,
        displayedMonth: LocalDate,
        selectedDay: LocalDate?,
        calendar: ActivityCalendar,
        formatter: ActivityFormatter
    ) -> StreakDetailReport {
        let first = history.range.lowerBound
        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)
        func reached(_ day: LocalDate) -> Bool {
            history.summary(for: day).map { StepStreakCalculator.isReached($0, goals: goals) } ?? false
        }

        // Serien im Verlauf (bis heute; heute zählt nur, wenn erreicht).
        var runs: [(start: LocalDate, end: LocalDate)] = []
        var runStart: LocalDate?
        var lastReached: LocalDate?
        if first <= today {
            for day in calendar.days(from: first, through: today) {
                if reached(day) {
                    if runStart == nil { runStart = day }
                    lastReached = day
                } else if let start = runStart {
                    runs.append((start, calendar.adding(-1, to: day)))
                    runStart = nil
                }
            }
        }
        if let start = runStart, let end = lastReached {
            runs.append((start, end))
        }
        let yesterday = calendar.adding(-1, to: today)
        let currentRun = runs.last.flatMap { $0.end >= yesterday ? $0 : nil }
        let pastRuns = runs
            .filter { run in currentRun.map { $0.start != run.start } ?? true }
            .map { run in
                let days = calendar.days(from: run.start, through: run.end).count
                return Run(
                    start: run.start,
                    end: run.end,
                    days: days,
                    isCurrent: false,
                    daysText: ActivityTexts.days(days),
                    rangeText: formatter.dayRange(run.start, run.end)
                )
            }
            .filter { $0.days >= 2 }
            .reversed()
            .prefix(maximumRuns)

        let record = StepStreakRecord.best(stored: storedRecord, streak: streak)

        // Monatsraster ab Montag.
        let monthStart = calendar.startOfMonth(containing: displayedMonth)
        let monthEnd = calendar.endOfMonth(containing: monthStart)
        let gridStart = calendar.startOfWeek(containing: monthStart)
        let gridEnd = calendar.adding(6, to: calendar.startOfWeek(containing: monthEnd))
        let selected = selectedDay.flatMap { $0 <= today ? $0 : nil }
        var cells: [Cell?] = []
        for day in calendar.days(from: gridStart, through: gridEnd) {
            guard day >= monthStart, day <= monthEnd else {
                cells.append(nil)
                continue
            }
            let state = cellState(day, today: today, history: history, reached: reached)
            let isReached = state == .reached
            let previous = calendar.adding(-1, to: day)
            let next = calendar.adding(1, to: day)
            let isRunStart = isReached && !reached(previous)
            // Ende einer Serie: Am Folgetag (vor heute bzw. heute verpasst ist nicht möglich) nicht erreicht.
            let isRunEnd = isReached && next < today && !reached(next)
            cells.append(Cell(
                day: day,
                state: state,
                isToday: day == today,
                isSelected: day == selected,
                isRunStart: isRunStart,
                isRunEnd: isRunEnd,
                accessibilityLabel: formatter.dayWithWeekdayShort(day) + ", " + StreakTexts.stateName(state)
            ))
        }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }

        let selectedDetails = selected.map { day -> SelectedDay in
            let state = cellState(day, today: today, history: history, reached: reached)
            var runLength = 0
            var cursor = day
            while cursor >= first, reached(cursor) {
                runLength += 1
                cursor = calendar.adding(-1, to: cursor)
            }
            let goal = goals.goal(on: day)
            let summary = history.summary(for: day)
            let status: String
            switch state {
            case .reached:
                status = runLength == 1 ? StreakTexts.runStarted : StreakTexts.runContinued(day: runLength)
            case .missed:
                var previousLength = 0
                var back = calendar.adding(-1, to: day)
                while back >= first, reached(back) {
                    previousLength += 1
                    back = calendar.adding(-1, to: back)
                }
                status = previousLength > 0 ? StreakTexts.runEnded(after: previousLength) : StreakTexts.notReached
            case .pending:
                let remaining = max(goal - (summary?.competitionSteps ?? 0), 0)
                status = StreakTexts.stillOpen(formatter.steps(remaining))
            case .noData, .future:
                status = StreakTexts.noData
            }
            return SelectedDay(
                day: day,
                title: formatter.dayWithWeekdayShort(day),
                stepsText: summary.map { StreakTexts.steps(formatter.steps($0.competitionSteps), of: formatter.steps(goal)) },
                goalText: StreakTexts.goal(formatter.steps(goal)),
                state: state,
                statusText: status,
                runLength: runLength
            )
        }

        let weekdayStart = calendar.startOfWeek(containing: today)
        return StreakDetailReport(
            currentDays: streak.current,
            currentText: DayDetailsReport.daysText(streak.current, open: streak.reachesHistoryStart),
            isTodayReached: streak.isTodayReached,
            statusText: StreakTexts.status(current: streak.current, isTodayReached: streak.isTodayReached),
            currentStartText: streak.currentStart.map(formatter.dayWithWeekdayShort),
            lastReachedText: lastReached.map(formatter.dayWithWeekdayShort),
            recordText: record.flatMap { $0.days > 0 ? ActivityTexts.days($0.days) : nil },
            recordRangeText: record.flatMap { $0.days > 0 ? formatter.dayRange($0.start, $0.end) : nil },
            pastRuns: Array(pastRuns),
            monthTitle: formatter.monthYear(monthStart),
            weekdays: (0..<7).map { formatter.weekdayLetter(calendar.adding($0, to: weekdayStart)) },
            weeks: weeks,
            selected: selectedDetails,
            canShowPreviousMonth: calendar.adding(-1, to: monthStart) >= first,
            canShowNextMonth: calendar.adding(1, to: monthEnd) <= today,
            historyNote: StreakTexts.historyNote(formatter.dayLongWithYear(first))
        )
    }

    private static func cellState(
        _ day: LocalDate,
        today: LocalDate,
        history: ActivityHistory,
        reached: (LocalDate) -> Bool
    ) -> CellState {
        if day > today { return .future }
        guard history.summary(for: day) != nil else { return .noData }
        if reached(day) { return .reached }
        return day == today ? .pending : .missed
    }
}

/// Texte der Flammen-Detailseite.
public enum StreakTexts {
    public static var title: String { PaceLocalization.text(de: "Deine Flamme", en: "Your flame", ru: "Твоя серия") }
    public static var record: String { PaceLocalization.text(de: "Rekord", en: "Record", ru: "Рекорд") }
    public static var started: String { PaceLocalization.text(de: "Beginn", en: "Started", ru: "Начало") }
    public static var lastSuccess: String {
        PaceLocalization.text(de: "Zuletzt geschafft", en: "Last reached", ru: "Последний успех")
    }
    public static var calendar: String { PaceLocalization.text(de: "Flammenkalender", en: "Flame calendar", ru: "Календарь серии") }
    public static var pastStreaks: String { PaceLocalization.text(de: "Frühere Serien", en: "Past streaks", ru: "Прошлые серии") }
    public static var noPastStreaks: String {
        PaceLocalization.text(
            de: "Im ausgewerteten Zeitraum gab es noch keine abgeschlossene Serie ab zwei Tagen.",
            en: "There's no finished streak of two days or more in the analysed period yet.",
            ru: "В рассматриваемом периоде ещё нет завершённых серий от двух дней."
        )
    }
    public static var howItWorks: String { PaceLocalization.text(de: "So funktioniert die Flamme", en: "How the flame works", ru: "Как работает серия") }
    public static var rule: String {
        PaceLocalization.text(
            de: "Deine Flamme wächst um einen Tag, wenn du an diesem Tag dein Tagesziel erreichst. Es zählen deine Wettbewerbsschritte – manuell in Apple Health eingetragene Schritte nicht. Maßgeblich ist das Ziel, das an dem Tag galt; spätere Zieländerungen wirken nicht zurück. Heute zählt mit, sobald du dein Ziel erreicht hast. Verpasst du einen Tag, beginnt die Flamme neu.",
            en: "Your flame grows by one day whenever you reach your daily goal that day. Your competition steps count – steps entered manually in Apple Health don't. The goal that applied on that day is what counts; later goal changes don't apply retroactively. Today counts as soon as you reach your goal. Miss a day and the flame starts over.",
            ru: "Серия растёт на один день, когда ты выполняешь дневную цель. Считаются шаги для соревнований – шаги, введённые вручную в «Здоровье», не считаются. Важна цель, действовавшая в тот день; более поздние изменения цели не действуют задним числом. Сегодня засчитывается, как только цель выполнена. Пропустишь день – серия начнётся заново."
        )
    }
    public static var personalOnly: String {
        PaceLocalization.text(
            de: "Das ist deine persönliche Flamme. Gruppenflammen findest du in der jeweiligen Gruppe.",
            en: "This is your personal flame. Group flames are in each group.",
            ru: "Это твоя личная серия. Серии групп находятся в самих группах."
        )
    }
    public static var runStarted: String { PaceLocalization.text(de: "Serie gestartet", en: "Streak started", ru: "Серия началась") }
    public static func runContinued(day: Int) -> String {
        PaceLocalization.text(
            de: "Flamme fortgesetzt – Tag \(day.paceFormatted) der Serie",
            en: "Flame continued – day \(day.paceFormatted) of the streak",
            ru: "Серия продолжена – день \(day.paceFormatted)"
        )
    }
    public static func runEnded(after days: Int) -> String {
        // Deutsch im Dativ („nach 4 Tagen“).
        let dative = "\(days.paceFormatted) " + PaceLocalization.plural(days, de: ("Tag", "Tagen"), en: ("day", "days"), ru: ("день", "дня", "дней"))
        return PaceLocalization.text(
            de: "Tagesziel verpasst – die Flamme erlosch nach \(dative)",
            en: "Daily goal missed – the flame ended after \(dative)",
            ru: "Цель не выполнена – серия прервалась через \(dative)"
        )
    }
    public static var notReached: String {
        PaceLocalization.text(de: "Tagesziel nicht erreicht", en: "Daily goal not reached", ru: "Цель не выполнена")
    }
    public static func stillOpen(_ remaining: String) -> String {
        PaceLocalization.text(
            de: "Heute noch \(remaining) Schritte bis zum Ziel",
            en: "\(remaining) steps to go today",
            ru: "Сегодня осталось \(remaining) шагов"
        )
    }
    public static var noData: String {
        PaceLocalization.text(de: "Für diesen Tag liegen keine Daten vor.", en: "There is no data for this day.", ru: "Для этого дня нет данных.")
    }
    static func steps(_ steps: String, of goal: String) -> String {
        PaceLocalization.text(de: "\(steps) von \(goal) Schritten", en: "\(steps) of \(goal) steps", ru: "\(steps) из \(goal) шагов")
    }
    static func goal(_ goal: String) -> String {
        PaceLocalization.text(de: "Ziel an diesem Tag: \(goal) Schritte", en: "Goal that day: \(goal) steps", ru: "Цель в этот день: \(goal) шагов")
    }
    static func historyNote(_ first: String) -> String {
        PaceLocalization.text(
            de: "Ausgewertet werden deine Schritte seit \(first) (12 Monate). Frühere Serien kennt Pace nicht – nur ein gespeicherter Rekord kann älter sein.",
            en: "Your steps since \(first) are analysed (12 months). Pace doesn't know earlier streaks – only a saved record can be older.",
            ru: "Учитываются шаги с \(first) (12 месяцев). Более ранние серии Pace не знает – только сохранённый рекорд может быть старше."
        )
    }
    static func status(current: Int, isTodayReached: Bool) -> String {
        switch (current, isTodayReached) {
        case (_, true):
            PaceLocalization.text(de: "Heute geschafft – weiter so!", en: "Done for today – keep it up!", ru: "Сегодня цель достигнута – так держать!")
        case (0, false):
            PaceLocalization.text(
                de: "Erreiche heute dein Tagesziel, um eine neue Flamme zu starten.",
                en: "Reach your daily goal today to start a new flame.",
                ru: "Достигни цели сегодня, чтобы начать новую серию."
            )
        default:
            PaceLocalization.text(
                de: "Erreiche heute dein Tagesziel, damit die Flamme weiterbrennt.",
                en: "Reach your daily goal today to keep the flame going.",
                ru: "Достигни цели сегодня, чтобы серия продолжилась."
            )
        }
    }
    static func stateName(_ state: StreakDetailReport.CellState) -> String {
        switch state {
        case .reached: PaceLocalization.text(de: "Ziel erreicht", en: "Goal reached", ru: "Цель выполнена")
        case .missed: PaceLocalization.text(de: "Ziel verpasst", en: "Goal missed", ru: "Цель не выполнена")
        case .pending: PaceLocalization.text(de: "heute, Ziel noch offen", en: "today, goal still open", ru: "сегодня, цель ещё открыта")
        case .future: PaceLocalization.text(de: "in der Zukunft", en: "in the future", ru: "в будущем")
        case .noData: PaceLocalization.text(de: "keine Daten", en: "no data", ru: "нет данных")
        }
    }
}
