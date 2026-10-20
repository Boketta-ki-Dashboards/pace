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
        case .day: PaceLocalization.text(de: "Tag", en: "Day", ru: "День")
        case .week: PaceLocalization.text(de: "Woche", en: "Week", ru: "Неделя")
        case .month: PaceLocalization.text(de: "Monat", en: "Month", ru: "Месяц")
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
        case .steps: PaceLocalization.text(de: "Schritte", en: "Steps", ru: "Шаги")
        case .distance: PaceLocalization.text(de: "Distanz", en: "Distance", ru: "Дистанция")
        case .activeEnergy: PaceLocalization.text(de: "Kalorien", en: "Calories", ru: "Калории")
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "shoeprints.fill"
        case .activeEnergy: "flame.fill"
        }
    }

    /// Einheit hinter der großen Zahl (für Schritte in der Mehrzahl, siehe ``unit(for:)``).
    public var unit: String {
        unit(for: 5)
    }

    /// Einheit passend zum Wert, z. B. `1 Schritt`, `2 шага`, `5 шагов`.
    public func unit(for value: Double) -> String {
        switch self {
        case .steps:
            PaceLocalization.plural(
                Int(value.rounded()),
                de: ("Schritt", "Schritte"),
                en: ("step", "steps"),
                ru: ("шаг", "шага", "шагов")
            )
        case .distance: PaceLocalization.text(de: "km", en: "km", ru: "км")
        case .activeEnergy: PaceLocalization.text(de: "kcal", en: "kcal", ru: "ккал")
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
        "\(format(value, formatter: formatter)) \(unit(for: value))"
    }

    /// Wert für die Diagrammachse (Schritte, km, kcal).
    public func chartValue(_ value: Double) -> Double {
        self == .distance ? value / 1_000 : value
    }
}
