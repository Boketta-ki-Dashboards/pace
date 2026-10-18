import Foundation
import PaceCore

/// Aufbereitete persönliche Serie für das Serien-Modul auf Home und das Profil. Reine Berechnung, dadurch testbar.
public struct StreakSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        public let status: StepStreakDayStatus
        /// `M`, `D`, `M`, …
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
    /// Die laufende Kalenderwoche, Montag bis Sonntag. Tage nach heute haben den Status `.future`.
    public let lastWeek: [Day]
    /// Die laufende und die drei vorherigen Kalenderwochen (28 Tage, ab Montag).
    public let lastFourWeeks: [Day]
    public let accessibilityLabel: String

    private static let letters = ["M", "D", "M", "D", "F", "S", "S"]

    public init(
        streak: StepStreak,
        record: StepStreakRecord?,
        recentDays: [(day: LocalDate, status: StepStreakDayStatus)],
        formatter: ActivityFormatter
    ) {
        currentDays = streak.current
        let count = Self.days(streak.current)
        currentText = streak.reachesHistoryStart ? "\(streak.current)+ Tage" : count
        isTodayReached = streak.isTodayReached

        switch (streak.current, streak.isTodayReached) {
        case (_, true):
            statusText = "Heute geschafft – weiter so!"
        case (0, false):
            statusText = "Erreiche heute dein Tagesziel, um eine neue Serie zu starten."
        default:
            statusText = "Erreiche heute dein Tagesziel, um deine Serie fortzusetzen."
        }

        recordText = record.flatMap { $0.days > 0 ? "Rekord: \(Self.days($0.days))" : nil }

        let calendar = formatter.calendar
        if let today = recentDays.last?.day {
            let statuses = Dictionary(recentDays.map { ($0.day, $0.status) }, uniquingKeysWith: { _, last in last })
            let weekStart = calendar.startOfWeek(containing: today)
            let days = calendar.days(from: calendar.adding(-21, to: weekStart), through: calendar.adding(6, to: weekStart)).map { day in
                let status = statuses[day] ?? (day > today ? .future : .unknown)
                let weekdayIndex = (calendar.calendar.component(.weekday, from: calendar.startOfDay(day)) + 5) % 7
                return Day(
                    date: day,
                    status: status,
                    letter: Self.letters[weekdayIndex],
                    accessibilityLabel: "\(formatter.dayLong(day)): \(Self.statusTitle(status))"
                )
            }
            lastFourWeeks = days
            lastWeek = Array(days.suffix(7))
        } else {
            lastFourWeeks = []
            lastWeek = []
        }

        var label = "Serie: \(currentText). \(statusText)"
        if let recordText { label += " \(recordText)." }
        accessibilityLabel = label
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? "1 Tag" : "\(count) Tage"
    }

    private static func statusTitle(_ status: StepStreakDayStatus) -> String {
        switch status {
        case .reached: "Ziel erreicht"
        case .missed: "Ziel nicht erreicht"
        case .pending: "heute noch offen"
        case .unknown: "keine Daten"
        case .future: "Zukunft"
        }
    }
}
