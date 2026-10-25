import Foundation
import PaceCore

/// Ein persönlicher Bestwert, z. B. „Bester Tag dieser Woche · 12.480 Schritte · Di., 13. Okt.“.
public struct PersonalBest: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case dayOfWeek, dayOfMonth, dayOverall, longestStreak
    }

    public let kind: Kind
    public let title: String
    public let value: String
    public let detail: String?
    /// Der betrachtete Tag ist selbst dieser Bestwert.
    public let isThisDay: Bool

    public var id: Kind { kind }
}

/// Bestwerte rund um einen Tag (persönlicher Kalender, unter den Tagesdetails): bester Tag seiner Woche und seines
/// Monats, bester Tag im geladenen Verlauf und die längste Serie. Nur aus echten Tageswerten (Wettbewerbsschritte, wie
/// Ziel und Streak), Wochen ab Montag in der Zeitzone des Geräts; Tage ohne Schritte zählen nicht als Bestwert.
public enum PersonalBests {
    public static func around(
        _ day: LocalDate,
        history: ActivityHistory,
        today: LocalDate,
        record: StepStreakRecord?,
        calendar: ActivityCalendar,
        formatter: ActivityFormatter
    ) -> [PersonalBest] {
        func best(from first: LocalDate, through last: LocalDate) -> DailyActivitySummary? {
            let upper = min(last, today)
            guard first <= upper else { return nil }
            return history.summaries(from: first, through: upper, calendar: calendar)
                .filter { $0.competitionSteps > 0 }
                .max { ($0.competitionSteps, $0.date) < ($1.competitionSteps, $1.date) }
        }
        func entry(_ kind: PersonalBest.Kind, _ title: String, _ summary: DailyActivitySummary?) -> PersonalBest? {
            summary.map {
                PersonalBest(
                    kind: kind,
                    title: title,
                    value: ActivityTexts.steps($0.competitionSteps, formatter: formatter),
                    detail: formatter.dayWithWeekdayShort($0.date),
                    isThisDay: $0.date == day
                )
            }
        }

        let weekStart = calendar.startOfWeek(containing: day)
        let weekEnd = calendar.adding(6, to: weekStart)
        let monthStart = calendar.startOfMonth(containing: day)
        let monthEnd = calendar.endOfMonth(containing: day)
        let isCurrentWeek = (weekStart...weekEnd).contains(today)
        let isCurrentMonth = (monthStart...monthEnd).contains(today)

        var result: [PersonalBest] = []
        if let week = entry(
            .dayOfWeek,
            isCurrentWeek
                ? PaceLocalization.text(de: "Bester Tag dieser Woche", en: "Best day this week", ru: "Лучший день этой недели")
                : PaceLocalization.text(de: "Bester Tag der Woche", en: "Best day of the week", ru: "Лучший день недели"),
            best(from: weekStart, through: weekEnd)
        ) {
            result.append(week)
        }
        if let month = entry(
            .dayOfMonth,
            isCurrentMonth
                ? PaceLocalization.text(de: "Bester Tag dieses Monats", en: "Best day this month", ru: "Лучший день этого месяца")
                : PaceLocalization.text(de: "Bester Tag im ", en: "Best day in ", ru: "Лучший день: ") + formatter.monthYear(monthStart),
            best(from: monthStart, through: monthEnd)
        ) {
            result.append(month)
        }
        if let overall = entry(
            .dayOverall,
            PaceLocalization.text(de: "Bester Tag insgesamt", en: "Best day overall", ru: "Лучший день за всё время"),
            best(from: history.range.lowerBound, through: history.range.upperBound)
        ) {
            result.append(overall)
        }
        if let record, record.days > 0 {
            result.append(PersonalBest(
                kind: .longestStreak,
                title: PaceLocalization.text(de: "Längste Serie", en: "Longest streak", ru: "Самая длинная серия"),
                value: ActivityTexts.days(record.days),
                detail: formatter.dayRange(record.start, record.end),
                isThisDay: (record.start...record.end).contains(day)
            ))
        }
        return result
    }
}
