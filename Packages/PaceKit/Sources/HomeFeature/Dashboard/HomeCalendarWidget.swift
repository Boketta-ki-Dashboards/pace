import ActivityFeature
import Foundation
import PaceCore

/// Inhalt des Kalender-Widgets: ein kompakter Wochen- oder Monatsausschnitt nach den Regeln des Kalenders.
///
/// - Ziel nicht erreicht: Ring mit dem erreichten Anteil um die Tagesnummer, neutraler Hintergrund.
/// - Ziel erreicht: volle grüne Fläche, kein Ring.
/// - Heute: eigene dezente Markierung, unabhängig vom Ziel.
/// - Zukunft: neutral, ohne Werte.
///
/// Bewertet wird jeder Tag mit dem damals geltenden Tagesziel (Zielverlauf) – wie bei der persönlichen Streak.
public struct HomeCalendarWidget: Equatable, Sendable {
    public enum DayState: Equatable, Sendable {
        case reached
        /// Tag mit Werten, Ziel nicht erreicht (heute: noch nicht erreicht).
        case notReached
        /// Vergangener Tag ohne Werte (z. B. außerhalb des geladenen Verlaufs).
        case noData
        case future
    }

    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        public let steps: Int?
        public let goal: Int
        public let state: DayState
        public let isToday: Bool
        /// Gehört zum gezeigten Monat (Monatsansicht); Randtage anderer Monate bleiben leer.
        public let isInPeriod: Bool
        public let accessibilityLabel: String

        public var id: LocalDate { date }

        /// Anteil am Tagesziel, 0…1.
        public var progress: Double {
            guard let steps, goal > 0 else { return 0 }
            return min(Double(steps) / Double(goal), 1)
        }

        public var numberText: String {
            HomeFormat.dayNumber(date)
        }

        /// Schritte kompakt, z. B. `8,4k` bzw. `8,4 Tsd.`; `nil` für Zukunft und Tage ohne Werte.
        public var compactStepsText: String? {
            steps.map { $0.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(PaceLocalization.shared.locale)) }
        }
    }

    /// Zeilen Montag bis Sonntag.
    public let weeks: [[Day]]
    public let weekdayLetters: [String]
    /// z. B. `Oktober 2026` bzw. `12.–18. Okt.`.
    public let periodTitle: String
    /// Erreichte Tage im Ausschnitt bis heute.
    public let reachedCount: Int
    /// Vergangene Tage und heute im Ausschnitt.
    public let elapsedCount: Int

    /// - Parameters:
    ///   - size: Klein = laufende Woche, Mittel = zwei Wochen, Groß/Max = laufender Monat.
    ///   - daySteps: Wettbewerbsschritte eines Tages; `nil` ohne Werte.
    public init(
        size: HomeModuleSize,
        today: LocalDate,
        goals: StepGoalHistory,
        formatter: ActivityFormatter,
        daySteps: (LocalDate) -> Int?
    ) {
        let calendar = formatter.calendar
        let first: LocalDate
        let last: LocalDate
        let periodStart: LocalDate
        let periodEnd: LocalDate
        switch size {
        case .small:
            first = calendar.startOfWeek(containing: today)
            last = calendar.adding(6, to: first)
            periodStart = first
            periodEnd = last
            periodTitle = formatter.dayRange(first, last)
        case .medium:
            first = calendar.adding(-7, to: calendar.startOfWeek(containing: today))
            last = calendar.adding(13, to: first)
            periodStart = first
            periodEnd = last
            periodTitle = formatter.dayRange(first, last)
        case .large, .max:
            periodStart = calendar.startOfMonth(containing: today)
            periodEnd = calendar.endOfMonth(containing: today)
            first = calendar.startOfWeek(containing: periodStart)
            last = calendar.endOfWeek(containing: periodEnd)
            periodTitle = formatter.monthYear(today)
        }

        let days = calendar.days(from: first, through: last).map { date -> Day in
            let isInPeriod = date >= periodStart && date <= periodEnd
            let goal = goals.goal(on: date)
            let steps = date > today ? nil : daySteps(date)
            let state: DayState
            if date > today {
                state = .future
            } else if let steps {
                state = steps >= goal ? .reached : .notReached
            } else {
                state = date == today ? .notReached : .noData
            }
            return Day(
                date: date,
                steps: steps,
                goal: goal,
                state: state,
                isToday: date == today,
                isInPeriod: isInPeriod,
                accessibilityLabel: Self.accessibilityLabel(date: date, steps: steps, state: state, isToday: date == today, formatter: formatter)
            )
        }
        weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        weekdayLetters = (days.prefix(7)).map { HomeFormat.weekdayLetter($0.date, formatter: formatter) }
        let counted = days.filter { $0.isInPeriod && $0.date <= today }
        elapsedCount = counted.count
        reachedCount = counted.filter { $0.state == .reached }.count
    }

    /// z. B. `12 von 16 Tagen erreicht`.
    public var summaryText: String {
        let reached = reachedCount.paceFormatted
        let elapsed = elapsedCount.paceFormatted
        return PaceLocalization.text(
            de: "\(reached) von \(elapsed) \(elapsedCount == 1 ? "Tag" : "Tagen") erreicht",
            en: "Reached on \(reached) of \(elapsed) \(elapsedCount == 1 ? "day" : "days")",
            ru: "Выполнено в \(reached) из \(elapsed) "
                + PaceLocalization.plural(elapsedCount, de: ("", ""), en: ("", ""), ru: ("дня", "дней", "дней"))
        )
    }

    private static func accessibilityLabel(
        date: LocalDate,
        steps: Int?,
        state: DayState,
        isToday: Bool,
        formatter: ActivityFormatter
    ) -> String {
        var parts = [formatter.dayLong(date)]
        if isToday {
            parts.append(PaceLocalization.text(de: "heute", en: "today", ru: "сегодня"))
        }
        switch state {
        case .reached:
            parts.append(PaceLocalization.text(de: "Ziel erreicht", en: "goal reached", ru: "цель выполнена"))
        case .notReached:
            parts.append(PaceLocalization.text(de: "Ziel nicht erreicht", en: "goal not reached", ru: "цель не выполнена"))
        case .noData:
            parts.append(PaceLocalization.text(de: "keine Daten", en: "no data", ru: "нет данных"))
        case .future:
            break
        }
        if let steps {
            parts.append(PaceLocalization.steps(steps))
        }
        return parts.joined(separator: ", ")
    }
}
