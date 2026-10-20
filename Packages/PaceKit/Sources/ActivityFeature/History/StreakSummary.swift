import Foundation
import PaceCore

/// Aufbereitete persönliche Serie für das Serien-Modul auf Home und das Profil. Reine Berechnung, dadurch testbar.
///
/// Texte folgen der App-Sprache zum Zeitpunkt der Berechnung (Views berechnen die Zusammenfassung beim Zeichnen).
public struct StreakSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        public let status: StepStreakDayStatus
        /// `M`, `D`, `M`, … bzw. `M`, `T`, `W`, … oder `П`, `В`, `С`, …
        public let letter: String
        public let accessibilityLabel: String

        public var id: LocalDate { date }
    }

    public let currentDays: Int
    /// z. B. `5 Tage`, `1 Tag`, `400+ Tage`.
    public let currentText: String
    /// Was heute zu tun ist bzw. wie es steht.
    public let statusText: String
    /// z. B. `Rekord: 12 Tage`; `nil` ohne Rekord.
    public let recordText: String?
    public let isTodayReached: Bool
    /// Serie bis einschließlich gestern (ohne den laufenden Tag), z. B. für „3 Tage – aktuelle Serie bis gestern“.
    public let daysThroughYesterday: Int
    /// Die laufende Kalenderwoche, Montag bis Sonntag. Tage nach heute haben den Status `.future`.
    public let lastWeek: [Day]
    /// Die laufende und die drei vorherigen Kalenderwochen (28 Tage, ab Montag).
    public let lastFourWeeks: [Day]
    public let accessibilityLabel: String

    public init(
        streak: StepStreak,
        record: StepStreakRecord?,
        recentDays: [(day: LocalDate, status: StepStreakDayStatus)],
        formatter: ActivityFormatter
    ) {
        currentDays = streak.current
        currentText = DayDetailsReport.daysText(streak.current, open: streak.reachesHistoryStart)
        isTodayReached = streak.isTodayReached
        daysThroughYesterday = streak.throughYesterday

        switch (streak.current, streak.isTodayReached) {
        case (_, true):
            statusText = PaceLocalization.text(
                de: "Heute geschafft – weiter so!",
                en: "Done for today – keep it up!",
                ru: "Сегодня цель достигнута – так держать!"
            )
        case (0, false):
            statusText = PaceLocalization.text(
                de: "Erreiche heute dein Tagesziel, um eine neue Serie zu starten.",
                en: "Reach your daily goal today to start a new streak.",
                ru: "Достигни цели сегодня, чтобы начать новую серию."
            )
        default:
            statusText = PaceLocalization.text(
                de: "Erreiche heute dein Tagesziel, um deine Serie fortzusetzen.",
                en: "Reach your daily goal today to keep your streak going.",
                ru: "Достигни цели сегодня, чтобы продолжить серию."
            )
        }

        recordText = record.flatMap { record in
            guard record.days > 0 else { return nil }
            let days = ActivityTexts.days(record.days)
            return PaceLocalization.text(de: "Rekord: \(days)", en: "Record: \(days)", ru: "Рекорд: \(days)")
        }

        let calendar = formatter.calendar
        if let today = recentDays.last?.day {
            let statuses = Dictionary(recentDays.map { ($0.day, $0.status) }, uniquingKeysWith: { _, last in last })
            let weekStart = calendar.startOfWeek(containing: today)
            let days = calendar.days(from: calendar.adding(-21, to: weekStart), through: calendar.adding(6, to: weekStart)).map { day in
                let status = statuses[day] ?? (day > today ? .future : .unknown)
                return Day(
                    date: day,
                    status: status,
                    letter: formatter.weekdayLetter(day),
                    accessibilityLabel: "\(formatter.dayLong(day)): \(Self.statusTitle(status))"
                )
            }
            lastFourWeeks = days
            lastWeek = Array(days.suffix(7))
        } else {
            lastFourWeeks = []
            lastWeek = []
        }

        var label = PaceLocalization.text(de: "Serie", en: "Streak", ru: "Серия") + ": \(currentText). \(statusText)"
        if let recordText { label += " \(recordText)." }
        accessibilityLabel = label
    }

    static func statusTitle(_ status: StepStreakDayStatus) -> String {
        switch status {
        case .reached: PaceLocalization.text(de: "Ziel erreicht", en: "goal reached", ru: "цель достигнута")
        case .missed: PaceLocalization.text(de: "Ziel nicht erreicht", en: "goal missed", ru: "цель не достигнута")
        case .pending: PaceLocalization.text(de: "heute noch offen", en: "still open today", ru: "сегодня ещё не закрыт")
        case .unknown: PaceLocalization.text(de: "keine Daten", en: "no data", ru: "нет данных")
        case .future: PaceLocalization.text(de: "Zukunft", en: "upcoming", ru: "ещё впереди")
        }
    }
}
