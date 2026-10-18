import Foundation
import PaceCore

/// Zeitraum der Statistik.
public enum StatisticsPeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case day
    /// ISO-Woche (Montag bis Sonntag).
    case week
    /// Kalendermonat.
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        }
    }
}

/// Kennzahl im Diagramm der Statistik.
public enum StatisticsMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Wettbewerbsschritte (ohne manuell eingetragene Schritte) – dieselben Werte wie Ziel, Streak und Rankings.
    case steps
    case distance
    case activeEnergy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .steps: "Schritte"
        case .distance: "Distanz"
        case .activeEnergy: "Kalorien"
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "shoeprints.fill"
        case .activeEnergy: "flame.fill"
        }
    }

    /// Einheit hinter der großen Zahl.
    public var unit: String {
        switch self {
        case .steps: "Schritte"
        case .distance: "km"
        case .activeEnergy: "kcal"
        }
    }

    /// HealthKit-Kennzahl für Stundenwerte.
    public var activityMetric: ActivityMetric {
        switch self {
        case .steps: .competitionSteps
        case .distance: .walkingRunningDistance
        case .activeEnergy: .activeEnergy
        }
    }

    /// Tageswert in der Rohheit der Gesundheitsdaten (Schritte, Meter, kcal); `nil`, wenn nicht lesbar.
    public func value(of day: DailyActivitySummary) -> Double? {
        switch self {
        case .steps: Double(day.competitionSteps)
        case .distance: day.walkingRunningDistanceMeters
        case .activeEnergy: day.activeEnergyKilocalories
        }
    }

    /// Zahl ohne Einheit, z. B. `8.742`, `6,4` (km) oder `382`.
    public func format(_ value: Double, formatter: ActivityFormatter) -> String {
        switch self {
        case .steps: formatter.steps(Int(value.rounded()))
        case .distance: formatter.kilometers(meters: value)
        case .activeEnergy: formatter.kilocalories(value)
        }
    }

    /// Zahl mit Einheit, z. B. `8.742 Schritte`, `6,4 km`.
    public func formatWithUnit(_ value: Double, formatter: ActivityFormatter) -> String {
        "\(format(value, formatter: formatter)) \(unit)"
    }

    /// Wert für die Diagrammachse (Schritte, km, kcal).
    public func chartValue(_ value: Double) -> Double {
        self == .distance ? value / 1_000 : value
    }
}
