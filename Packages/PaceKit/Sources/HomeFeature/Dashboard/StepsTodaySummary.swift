import ActivityFeature
import Foundation
import PaceCore

/// Inhalte der Karte „Deine Schritte heute“. Ohne SwiftUI, dadurch testbar.
public struct StepsTodaySummary: Equatable, Sendable {
    /// Wettbewerbsschritte heute, z. B. `8.432`.
    public let stepsText: String
    public let steps: Int
    /// z. B. `von 10.000 Schritten`
    public let goalText: String
    /// 0…1 (kann über 1 liegen, wenn das Ziel übertroffen ist).
    public let progress: Double
    /// z. B. `84%`
    public let percentText: String
    /// z. B. `Noch 1.568 bis zu deinem Ziel` oder `Tagesziel erreicht!`
    public let remainingText: String
    public let isGoalReached: Bool
    /// `nil`, wenn die Kennzahl nicht lesbar ist – dann wird sie nicht angezeigt (keine falsche 0).
    public let distanceText: String?
    public let energyText: String?
    /// Für die große Schrittkarte; `nil`, wenn nicht lesbar.
    public let flightsText: String?
    public let exerciseText: String?
    /// Hinweis, wenn heute Schritte in Apple Health nicht für Rankings zählen.
    public let manualStepsNote: String?

    public init(today: DailyActivitySummary, goal: Int, formatter: ActivityFormatter) {
        let goal = max(goal, 1)
        steps = today.competitionSteps
        stepsText = formatter.steps(today.competitionSteps)
        goalText = "von \(formatter.steps(goal)) Schritten"
        progress = Double(today.competitionSteps) / Double(goal)
        percentText = "\(Int((progress * 100).rounded(.down)))%"
        isGoalReached = today.competitionSteps >= goal
        remainingText = isGoalReached
            ? "Tagesziel erreicht!"
            : "Noch \(formatter.steps(goal - today.competitionSteps)) bis zu deinem Ziel"
        distanceText = today.walkingRunningDistanceMeters.map { formatter.distance(meters: $0) }
        energyText = today.activeEnergyKilocalories.map { formatter.energy(kilocalories: $0) }
        flightsText = today.flightsClimbed.map { "\(formatter.flights($0)) \($0 == 1 ? "Stockwerk" : "Stockwerke")" }
        exerciseText = today.exerciseMinutes.map { formatter.exerciseMinutes($0) }
        manualStepsNote = today.hasNonCompetitionSteps ? ActivityTexts.manualStepsNote : nil
    }
}

/// Wochenübersicht Montag bis Sonntag der aktuellen Woche.
public struct WeekOverview: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        /// `M`, `D`, `M`, `D`, `F`, `S`, `S`
        public let letter: String
        /// `nil` für Tage in der Zukunft.
        public let steps: Int?
        /// Höhe relativ zum besten Tag bzw. Tagesziel, 0…1.
        public let level: Double
        public let isToday: Bool
        /// Ziel des Tages erreicht (Ziel laut Zielverlauf).
        public let reachedGoal: Bool
        /// Für VoiceOver, z. B. `Montag, 12. Oktober: 8.432 Schritte`.
        public let accessibilityLabel: String

        public var id: LocalDate { date }
        public var isFuture: Bool { steps == nil }
    }

    public let days: [Day]
    /// z. B. `41.230`
    public let totalText: String
    /// z. B. `Ø 6.872 pro Tag`
    public let averageText: String
    /// z. B. `3 von 4 Tagen Ziel erreicht`. Heute zählt mit, sobald das Ziel erreicht ist.
    public let goalDaysText: String
    /// Für VoiceOver, z. B. `Diese Woche 41.230 Schritte`.
    public let accessibilitySummary: String

    private static let letters = ["M", "D", "M", "D", "F", "S", "S"]

    public init(overview: ActivityOverview, goals: StepGoalHistory, calendar: ActivityCalendar, formatter: ActivityFormatter) {
        let today = overview.today.date
        let monday = calendar.startOfWeek(containing: today)
        let stepsByDay = Dictionary(uniqueKeysWithValues: overview.currentWeek.days.map { ($0.date, $0.competitionSteps) })
        let scale = Double(max(goals.goal(on: today), stepsByDay.values.max() ?? 0, 1))

        days = (0..<7).map { offset in
            let date = calendar.adding(offset, to: monday)
            let isFuture = date > today
            let steps = isFuture ? nil : (stepsByDay[date] ?? 0)
            return Day(
                date: date,
                letter: Self.letters[offset],
                steps: steps,
                level: steps.map { min(Double($0) / scale, 1) } ?? 0,
                isToday: date == today,
                reachedGoal: steps.map { $0 >= goals.goal(on: date) } ?? false,
                accessibilityLabel: "\(formatter.dayLong(date)): \(formatter.steps(steps ?? 0)) Schritte"
            )
        }
        let elapsed = days.filter { !$0.isFuture }
        let total = elapsed.compactMap(\.steps).reduce(0, +)
        totalText = formatter.steps(total)
        averageText = "Ø \(formatter.steps(elapsed.isEmpty ? 0 : Int((Double(total) / Double(elapsed.count)).rounded()))) pro Tag"
        let counted = elapsed.filter { !$0.isToday || $0.reachedGoal }
        let reached = counted.filter(\.reachedGoal).count
        goalDaysText = "\(reached) von \(counted.count) \(counted.count == 1 ? "Tag" : "Tagen") Ziel erreicht"
        accessibilitySummary = "Diese Woche \(formatter.steps(total)) Schritte"
    }
}
