import Foundation
import PaceCore

/// Schritte eines Tages im Verhältnis zum damals geltenden Tagesziel – gemeinsame Grundlage für die Karte unter dem
/// Kalender, die große Karte der Tagesdetails und die Übersicht der letzten 7 Tage.
///
/// Schritte sind immer Wettbewerbsschritte (ohne manuell eingetragene) – wie Streak, Statistik und Rankings.
public struct DayGoalProgress: Equatable, Sendable {
    public let day: LocalDate
    public let steps: Int
    /// Ziel, das an diesem Tag galt (Zielverlauf), nicht das heutige.
    public let goal: Int
    public let isToday: Bool

    public init(day: LocalDate, steps: Int, goal: Int, isToday: Bool) {
        self.day = day
        self.steps = max(steps, 0)
        self.goal = max(goal, 1)
        self.isToday = isToday
    }

    /// Aus einem gemessenen Tag; `nil` ohne Daten.
    public init?(summary: DailyActivitySummary?, goals: StepGoalHistory, today: LocalDate) {
        guard let summary else { return nil }
        self.init(day: summary.date, steps: summary.competitionSteps, goal: goals.goal(on: summary.date), isToday: summary.date == today)
    }

    /// Anteil am Ziel; kann über 1 liegen.
    public var fraction: Double {
        Double(steps) / Double(goal)
    }

    /// Gleiche Regel wie ``StepStreakCalculator/isReached(_:goals:)``.
    public var isReached: Bool {
        steps >= goal
    }

    public var remaining: Int {
        max(goal - steps, 0)
    }

    /// `84%` (Ring); 99,6 % erscheinen nicht als 100 %, solange das Ziel nicht erreicht ist.
    public func percentText(formatter: ActivityFormatter) -> String {
        formatter.compactPercent(fraction)
    }

    /// `8.432`
    public func stepsText(formatter: ActivityFormatter) -> String {
        formatter.steps(steps)
    }

    /// `Schritte`, `steps`, `шага` – passend zur Zahl.
    public var stepsUnit: String {
        ActivityTexts.stepsWord(steps)
    }

    /// `Tagesziel 10.000` (Karte unter dem Kalender).
    public func goalText(formatter: ActivityFormatter) -> String {
        let goal = formatter.steps(goal)
        return PaceLocalization.text(de: "Tagesziel \(goal)", en: "Daily goal \(goal)", ru: "Цель на день: \(goal)")
    }

    /// `Tagesziel an diesem Tag: 10.000` (Tagesdetails).
    public func goalOnDayText(formatter: ActivityFormatter) -> String {
        let goal = formatter.steps(goal)
        return PaceLocalization.text(
            de: "Tagesziel an diesem Tag: \(goal)",
            en: "Goal on this day: \(goal)",
            ru: "Цель в этот день: \(goal)"
        )
    }

    /// `Noch 1.568 Schritte`, `Ziel erreicht` oder für vergangene Tage `1.568 Schritte haben gefehlt`.
    public func remainingText(formatter: ActivityFormatter) -> String {
        if isReached {
            return PaceLocalization.text(de: "Ziel erreicht", en: "Goal reached", ru: "Цель достигнута")
        }
        let steps = ActivityTexts.steps(remaining, formatter: formatter)
        if isToday {
            return PaceLocalization.text(de: "Noch \(steps)", en: "\(steps) to go", ru: "Ещё \(steps)")
        }
        return PaceLocalization.text(
            de: "\(steps) haben gefehlt",
            en: "\(steps) short of the goal",
            ru: "До цели не хватило: \(steps)"
        )
    }

    /// Für VoiceOver, z. B. `8.432 Schritte, 84 % des Tagesziels` bzw. `10.520 Schritte, Ziel erreicht`.
    public func accessibilityText(formatter: ActivityFormatter) -> String {
        let steps = ActivityTexts.steps(steps, formatter: formatter)
        if isReached {
            return "\(steps), " + PaceLocalization.text(de: "Ziel erreicht", en: "goal reached", ru: "цель достигнута")
        }
        let percent = formatter.percent(fraction)
        return "\(steps), " + PaceLocalization.text(
            de: "\(percent) des Tagesziels",
            en: "\(percent) of the daily goal",
            ru: "\(percent) от цели"
        )
    }
}
