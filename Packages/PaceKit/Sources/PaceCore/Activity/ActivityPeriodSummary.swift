import Foundation

/// Kennzahlen über mehrere Tage, z. B. die letzten 7 Tage.
public struct ActivityPeriodSummary: Equatable, Sendable {
    public let period: ActivityPeriod
    /// Ein Eintrag pro Kalendertag, chronologisch.
    public let days: [DailyActivitySummary]

    public init(period: ActivityPeriod, days: [DailyActivitySummary]) {
        self.period = period
        self.days = days.sorted { $0.date < $1.date }
    }

    public var totalCompetitionSteps: Int {
        days.reduce(0) { $0 + $1.competitionSteps }
    }

    public var totalHealthSteps: Int {
        days.reduce(0) { $0 + $1.healthSteps }
    }

    /// Durchschnittliche Wettbewerbsschritte pro Kalendertag des Zeitraums (gerundet). Der laufende Tag zählt mit.
    public var averageCompetitionStepsPerDay: Int {
        guard !days.isEmpty else { return 0 }
        return Int((Double(totalCompetitionSteps) / Double(days.count)).rounded())
    }

    /// Tag mit den meisten Wettbewerbsschritten. Bei Gleichstand der jüngere Tag; `nil`, wenn alle Tage 0 Schritte haben.
    public var bestDay: DailyActivitySummary? {
        days
            .filter { $0.competitionSteps > 0 }
            .max { lhs, rhs in
                (lhs.competitionSteps, lhs.date) < (rhs.competitionSteps, rhs.date)
            }
    }

    public var totalWalkingRunningDistanceMeters: Double? {
        sum(\.walkingRunningDistanceMeters)
    }

    public var totalActiveEnergyKilocalories: Double? {
        sum(\.activeEnergyKilocalories)
    }

    public var totalFlightsClimbed: Int? {
        sum(\.flightsClimbed)
    }

    public var totalExerciseMinutes: Int? {
        sum(\.exerciseMinutes)
    }

    /// `true`, wenn an mindestens einem Tag Health- und Wettbewerbsschritte abweichen.
    public var hasNonCompetitionSteps: Bool {
        days.contains { $0.hasNonCompetitionSteps }
    }

    /// Summe der vorhandenen Werte; `nil`, wenn die Kennzahl an keinem Tag verfügbar ist.
    private func sum<Value: AdditiveArithmetic>(_ keyPath: KeyPath<DailyActivitySummary, Value?>) -> Value? {
        let values = days.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(.zero, +)
    }
}
