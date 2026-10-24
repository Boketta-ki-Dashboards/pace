import Foundation
import PaceCore

/// Alles, was die Tagesdetails (Referenzbild 8) für einen Tag zeigen. Reine Berechnung, dadurch testbar.
///
/// Grundsätze wie in der Statistik: Schritte sind Wettbewerbsschritte, bewertet mit dem Ziel des jeweiligen Tages;
/// nicht lesbare Kennzahlen erscheinen als „–“, nie als 0; Herzwerte nur, wenn Apple Health welche liefert.
public struct DayDetailsReport: Equatable, Sendable {
    /// Eine Kachel, z. B. `6,1 km` · `Distanz` oder `62` `/min` · `Ruhepuls`.
    public struct Tile: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case distance, activeEnergy, flights, exercise, restingHeartRate, walkingHeartRate
        }

        public let kind: Kind
        /// `6,1 km`, `8`, `62`; `–`, wenn nicht lesbar.
        public let value: String
        /// Kleine Einheit hinter der Zahl (Puls: `/min`).
        public let unit: String?
        public let title: String
        public let isAvailable: Bool

        public var id: Kind { kind }

        public var accessibilityLabel: String {
            guard isAvailable else { return "\(title): \(StatisticsReport.unavailable)" }
            return "\(title): \(value)" + (unit.map { " \($0)" } ?? "")
        }
    }

    /// Ein Stundenbalken im Tagesverlauf.
    public struct HourBar: Equatable, Sendable, Identifiable {
        public let hour: Int
        /// Wettbewerbsschritte dieser Stunde; `nil` für Stunden nach jetzt.
        public let value: Double?
        public let isCurrent: Bool

        public var id: Int { hour }
    }

    public enum Hourly: Equatable, Sendable {
        case loading
        case failed
        /// Für den Tag gibt es keine Daten – kein Diagramm voller Nullen.
        case unavailable
        case loaded([HourBar])
    }

    /// Karte „Deine Streak“.
    public struct Streak: Equatable, Sendable {
        /// `3 Tage`
        public let valueText: String
        /// `Aktuelle Serie bis gestern`
        public let caption: String
        /// `Rekord: 12 Tage`
        public let recordText: String
        /// `Erreiche heute dein Ziel für Tag 4.`
        public let hint: String
        /// Flamme kräftig, wenn eine Serie läuft.
        public let isActive: Bool
        public let isTodayReached: Bool

        public var accessibilityLabel: String {
            "\(valueText), \(caption). \(recordText). \(hint)"
        }
    }

    /// Ein Tag in „Deine letzten 7 Tage“.
    public struct RecentDay: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        /// `So`, `Sun`, `Вс`
        public let weekday: String
        public let status: CalendarDayStatus
        /// `4.100`, heute (noch offen) `84%`, ohne Daten `–`.
        public let valueText: String
        public let isSelected: Bool
        public let accessibilityLabel: String

        public var id: LocalDate { date }
    }

    public let day: LocalDate
    public let isToday: Bool
    /// `Samstag, 17. Oktober 2026`
    public let dateText: String
    /// `nil`, wenn für den Tag keine Daten vorliegen.
    public let progress: DayGoalProgress?
    public let tiles: [Tile]
    /// Ruhepuls und Ø Puls beim Gehen – nur vorhandene Werte.
    public let heartTiles: [Tile]
    public let hourly: Hourly
    public let streak: Streak
    public let recentDays: [RecentDay]
    public let notes: [String]

    public struct Input: Sendable {
        public var day: LocalDate
        public var today: LocalDate
        public var history: ActivityHistory
        public var goals: StepGoalHistory
        /// Bisher längste Serie (gespeichert oder im Verlauf).
        public var record: StepStreakRecord?
        /// Wettbewerbsschritte je Stunde; `nil`, solange nicht geladen.
        public var hourly: [Int: Double]?
        public var hourlyFailed: Bool
        /// Laufende Stunde (0–23) – für heute bleiben spätere Stunden leer.
        public var currentHour: Int
        public var heartRate: DailyHeartRate?
        public var formatter: ActivityFormatter
        public var calendar: ActivityCalendar

        public init(
            day: LocalDate,
            today: LocalDate,
            history: ActivityHistory,
            goals: StepGoalHistory,
            record: StepStreakRecord?,
            hourly: [Int: Double]?,
            hourlyFailed: Bool = false,
            currentHour: Int,
            heartRate: DailyHeartRate? = nil,
            formatter: ActivityFormatter,
            calendar: ActivityCalendar
        ) {
            self.day = day
            self.today = today
            self.history = history
            self.goals = goals
            self.record = record
            self.hourly = hourly
            self.hourlyFailed = hourlyFailed
            self.currentHour = currentHour
            self.heartRate = heartRate
            self.formatter = formatter
            self.calendar = calendar
        }
    }

    public static func make(_ input: Input) -> DayDetailsReport {
        let formatter = input.formatter
        let summary = input.history.summary(for: input.day)
        let isToday = input.day == input.today

        var notes: [String] = []
        if summary == nil {
            notes.append(Texts.noDataForDay)
        } else if let summary, summary.hasNonCompetitionSteps {
            notes.append(Texts.healthStepsNote(summary.healthSteps, formatter: formatter))
        }

        return DayDetailsReport(
            day: input.day,
            isToday: isToday,
            dateText: formatter.dayLongWithYear(input.day),
            progress: DayGoalProgress(summary: summary, goals: input.goals, today: input.today),
            tiles: movementTiles(summary, formatter: formatter),
            heartTiles: heartTiles(input.heartRate, formatter: formatter),
            hourly: hourly(input, hasData: summary != nil),
            streak: streak(input),
            recentDays: recentDays(input),
            notes: notes
        )
    }

    // MARK: - Kacheln

    private static func movementTiles(_ summary: DailyActivitySummary?, formatter: ActivityFormatter) -> [Tile] {
        func tile(_ kind: Tile.Kind, _ title: String, _ value: String?) -> Tile {
            Tile(kind: kind, value: value ?? "–", unit: nil, title: title, isAvailable: value != nil)
        }
        return [
            tile(.distance, Texts.distance, summary?.walkingRunningDistanceMeters.map(formatter.distance(meters:))),
            tile(
                .activeEnergy,
                summary?.activeEnergy.isEstimated == true
                    ? PaceLocalization.text(de: "Aktiv (geschätzt)", en: "Active (estimated)", ru: "Активность (расчёт)")
                    : PaceLocalization.text(de: "Aktiv", en: "Active", ru: "Активность"),
                summary.flatMap { formatter.energy($0.activeEnergy) }
            ),
            tile(.flights, Texts.floors, summary?.flightsClimbed.map(formatter.flights)),
            tile(.exercise, Texts.exerciseMinutes, summary?.exerciseMinutes.map(formatter.flights)),
        ]
    }

    private static func heartTiles(_ heartRate: DailyHeartRate?, formatter: ActivityFormatter) -> [Tile] {
        guard let heartRate else { return [] }
        var tiles: [Tile] = []
        if let resting = heartRate.restingBeatsPerMinute {
            let value = formatter.beatsPerMinute(resting)
            tiles.append(Tile(
                kind: .restingHeartRate,
                value: value.value,
                unit: value.unit,
                title: PaceLocalization.text(de: "Ruhepuls", en: "Resting heart rate", ru: "Пульс в покое"),
                isAvailable: true
            ))
        }
        if let walking = heartRate.walkingAverageBeatsPerMinute {
            let value = formatter.beatsPerMinute(walking)
            tiles.append(Tile(
                kind: .walkingHeartRate,
                value: value.value,
                unit: value.unit,
                title: PaceLocalization.text(de: "Ø Puls beim Gehen", en: "Avg. walking heart rate", ru: "Средний пульс при ходьбе"),
                isAvailable: true
            ))
        }
        return tiles
    }

    // MARK: - Tagesverlauf

    private static func hourly(_ input: Input, hasData: Bool) -> Hourly {
        guard hasData else { return .unavailable }
        guard let values = input.hourly else { return input.hourlyFailed ? .failed : .loading }
        let isToday = input.day == input.today
        return .loaded((0..<24).map { hour in
            HourBar(
                hour: hour,
                value: isToday && hour > input.currentHour ? nil : max(values[hour] ?? 0, 0),
                isCurrent: isToday && hour == input.currentHour
            )
        })
    }

    // MARK: - Streak

    private static func streak(_ input: Input) -> Streak {
        let atDay = StepStreakCalculator.streak(
            history: input.history,
            goals: input.goals,
            today: input.day,
            calendar: input.calendar
        )
        let recordText: String
        if let record = input.record, record.days > 0 {
            let days = ActivityTexts.days(record.days)
            recordText = PaceLocalization.text(de: "Rekord: \(days)", en: "Record: \(days)", ru: "Рекорд: \(days)")
        } else {
            recordText = PaceLocalization.text(de: "Noch kein Rekord", en: "No record yet", ru: "Рекорда пока нет")
        }
        let hasData = input.history.summary(for: input.day) != nil

        if input.day == input.today {
            if atDay.isTodayReached {
                let days = atDay.current
                return Streak(
                    valueText: daysText(days, open: atDay.reachesHistoryStart),
                    caption: PaceLocalization.text(
                        de: "Aktuelle Serie inklusive heute",
                        en: "Current streak including today",
                        ru: "Текущая серия вместе с сегодняшним днём"
                    ),
                    recordText: recordText,
                    hint: PaceLocalization.text(
                        de: "Heute geschafft – Tag \(days.paceFormatted) zählt.",
                        en: "Done for today – day \(days.paceFormatted) counts.",
                        ru: "Сегодня цель достигнута – день \(days.paceFormatted) засчитан."
                    ),
                    isActive: true,
                    isTodayReached: true
                )
            }
            // Ein laufender Tag unterbricht die Serie nicht: Sie gilt bis gestern und kann heute fortgesetzt werden.
            let days = atDay.throughYesterday
            let next = days + 1
            return Streak(
                valueText: daysText(days, open: atDay.reachesHistoryStart),
                caption: PaceLocalization.text(
                    de: "Aktuelle Serie bis gestern",
                    en: "Current streak through yesterday",
                    ru: "Текущая серия по вчерашний день"
                ),
                recordText: recordText,
                hint: days > 0
                    ? PaceLocalization.text(
                        de: "Erreiche heute dein Ziel für Tag \(next.paceFormatted).",
                        en: "Reach your goal today for day \(next.paceFormatted).",
                        ru: "Достигни цели сегодня – это будет день \(next.paceFormatted)."
                    )
                    : PaceLocalization.text(
                        de: "Erreiche heute dein Ziel, um eine neue Serie zu starten.",
                        en: "Reach your goal today to start a new streak.",
                        ru: "Достигни цели сегодня, чтобы начать новую серию."
                    ),
                isActive: days > 0,
                isTodayReached: false
            )
        }

        if atDay.isTodayReached {
            let days = atDay.current
            return Streak(
                valueText: daysText(days, open: atDay.reachesHistoryStart),
                caption: PaceLocalization.text(de: "Serie an diesem Tag", en: "Streak on this day", ru: "Серия в этот день"),
                recordText: recordText,
                hint: PaceLocalization.text(
                    de: "Ziel erreicht – Tag \(days.paceFormatted) der Serie.",
                    en: "Goal reached – day \(days.paceFormatted) of the streak.",
                    ru: "Цель достигнута – день \(days.paceFormatted) серии."
                ),
                isActive: true,
                isTodayReached: true
            )
        }
        let days = atDay.current
        let hint: String
        if !hasData {
            hint = Texts.noDataForDay
        } else if days > 0 {
            hint = PaceLocalization.text(
                de: "Ziel nicht erreicht – die Serie endete an diesem Tag.",
                en: "Goal missed – the streak ended on this day.",
                ru: "Цель не достигнута – серия прервалась в этот день."
            )
        } else {
            hint = PaceLocalization.text(
                de: "Ziel nicht erreicht – an diesem Tag lief keine Serie.",
                en: "Goal missed – no streak was running on this day.",
                ru: "Цель не достигнута – серии в этот день не было."
            )
        }
        return Streak(
            valueText: daysText(days, open: atDay.reachesHistoryStart),
            caption: PaceLocalization.text(de: "Serie bis zum Vortag", en: "Streak until the day before", ru: "Серия по предыдущий день"),
            recordText: recordText,
            hint: hint,
            isActive: false,
            isTodayReached: false
        )
    }

    /// `3 Tage`; reicht die Serie bis an den Anfang des geladenen Verlaufs, `365+ Tage`.
    static func daysText(_ days: Int, open: Bool) -> String {
        guard open, days > 0 else { return ActivityTexts.days(days) }
        let word = PaceLocalization.plural(days, de: ("Tag", "Tage"), en: ("day", "days"), ru: ("день", "дня", "дней"))
        return "\(days.paceFormatted)+ \(word)"
    }

    // MARK: - Letzte 7 Tage

    private static func recentDays(_ input: Input) -> [RecentDay] {
        let formatter = input.formatter
        let calendar = input.calendar
        return calendar.days(from: calendar.adding(-6, to: input.day), through: input.day).map { date in
            let (status, progress) = CalendarMonth.status(of: date, history: input.history, goals: input.goals, today: input.today)
            let valueText: String
            if let progress {
                valueText = progress.isToday && !progress.isReached
                    ? progress.percentText(formatter: formatter)
                    : progress.stepsText(formatter: formatter)
            } else {
                valueText = "–"
            }
            let detail = progress.map { $0.accessibilityText(formatter: formatter) }
                ?? PaceLocalization.text(de: "keine Daten", en: "no data", ru: "нет данных")
            return RecentDay(
                date: date,
                weekday: formatter.weekdayShort(date),
                status: status,
                valueText: valueText,
                isSelected: date == input.day,
                accessibilityLabel: "\(formatter.dayLong(date)): \(detail)"
            )
        }
    }
}
