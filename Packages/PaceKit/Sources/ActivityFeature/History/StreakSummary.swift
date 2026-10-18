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
    /// Die letzten 7 Tage (älteste zuerst).
    public let lastWeek: [Day]
    /// Die letzten 28 Tage (älteste zuerst).
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
        let days = recentDays.map { entry in
            let weekdayIndex = (calendar.calendar.component(.weekday, from: calendar.startOfDay(entry.day)) + 5) % 7
            return Day(
                date: entry.day,
                status: entry.status,
                letter: Self.letters[weekdayIndex],
                accessibilityLabel: "\(formatter.dayLong(entry.day)): \(Self.statusTitle(entry.status))"
            )
        }
        lastFourWeeks = Array(days.suffix(28))
        lastWeek = Array(days.suffix(7))

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
