import Foundation
import PaceCore

/// Aufbereitete Statistiken für die Detailansicht. Reine Berechnung aus einer `ActivityOverview`.
public struct ActivityStatsViewModel: Equatable, Sendable {
    public struct Metric: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case steps, distance, activeEnergy, flights, exercise
        }

        public let kind: Kind
        public let title: String
        public let value: String

        public var id: Kind { kind }
    }

    public struct ChartDay: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        public let weekday: String
        public let competitionSteps: Int
        public let isToday: Bool

        public var id: LocalDate { date }
    }

    public struct Highlight: Equatable, Sendable {
        public let title: String
        public let value: String
        public let detail: String?
    }

    /// Hinweis, wenn Health- und Wettbewerbsschritte abweichen.
    public static let manualStepsNote = "Manuell eingetragene Schritte zählen nicht für Rankings."

    public let todayTitle: String
    /// Wettbewerbsschritte heute – der wichtigste Wert.
    public let todaySteps: String
    /// Weitere verfügbare Tageswerte. Nicht verfügbare Kennzahlen fehlen, statt als 0 zu erscheinen.
    public let todayMetrics: [Metric]
    /// Schrittzahl laut Apple Health, nur wenn sie von den Wettbewerbsschritten abweicht.
    public let todayHealthSteps: String?

    public let chartDays: [ChartDay]
    /// Tagesdurchschnitt der Wettbewerbsschritte für die Linie im Diagramm.
    public let chartAverage: Int
    public let weekHighlights: [Highlight]
    public let weekTotals: [Metric]
    public let manualStepsNote: String?

    public init(overview: ActivityOverview, formatter: ActivityFormatter) {
        let today = overview.today
        let week = overview.lastSevenDays

        todayTitle = formatter.dayLong(today.date)
        todaySteps = formatter.steps(today.competitionSteps)
        todayMetrics = Self.metrics(
            distance: today.walkingRunningDistanceMeters,
            energy: today.activeEnergyKilocalories,
            flights: today.flightsClimbed,
            exercise: today.exerciseMinutes,
            formatter: formatter
        )
        todayHealthSteps = today.hasNonCompetitionSteps ? formatter.steps(today.healthSteps) : nil

        chartDays = week.days.map { day in
            ChartDay(
                date: day.date,
                weekday: formatter.weekdayShort(day.date),
                competitionSteps: day.competitionSteps,
                isToday: day.date == today.date
            )
        }

        chartAverage = week.averageCompetitionStepsPerDay

        var highlights = [
            Highlight(title: "Tagesdurchschnitt", value: formatter.steps(week.averageCompetitionStepsPerDay), detail: nil),
        ]
        if let best = week.bestDay {
            highlights.append(Highlight(
                title: "Bester Tag",
                value: formatter.steps(best.competitionSteps),
                detail: best.date == today.date ? "Heute" : formatter.dayShort(best.date)
            ))
        }
        weekHighlights = highlights

        var totals = [Metric(kind: .steps, title: "Schritte gesamt", value: formatter.steps(week.totalCompetitionSteps))]
        if let distance = week.totalWalkingRunningDistanceMeters {
            totals.append(Metric(kind: .distance, title: "Distanz gesamt", value: formatter.distance(meters: distance)))
        }
        if let energy = week.totalActiveEnergyKilocalories {
            totals.append(Metric(kind: .activeEnergy, title: "Aktive Kalorien", value: formatter.energy(kilocalories: energy)))
        }
        weekTotals = totals

        manualStepsNote = week.hasNonCompetitionSteps ? Self.manualStepsNote : nil
    }

    /// Höchster Tageswert im Diagramm, mindestens 1 (für die Achsenskalierung).
    public var chartMaximum: Int {
        max(chartDays.map(\.competitionSteps).max() ?? 0, 1)
    }

    private static func metrics(
        distance: Double?,
        energy: Double?,
        flights: Int?,
        exercise: Int?,
        formatter: ActivityFormatter
    ) -> [Metric] {
        var result: [Metric] = []
        if let distance {
            result.append(Metric(kind: .distance, title: "Distanz", value: formatter.distance(meters: distance)))
        }
        if let energy {
            result.append(Metric(kind: .activeEnergy, title: "Aktive Kalorien", value: formatter.energy(kilocalories: energy)))
        }
        if let flights {
            result.append(Metric(kind: .flights, title: "Stockwerke", value: formatter.flights(flights)))
        }
        if let exercise {
            result.append(Metric(kind: .exercise, title: "Trainingsminuten", value: formatter.exerciseMinutes(exercise)))
        }
        return result
    }
}
