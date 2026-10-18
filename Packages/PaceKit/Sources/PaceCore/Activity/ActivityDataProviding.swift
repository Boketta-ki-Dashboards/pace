import Foundation

/// Bewegungskennzahlen, die Pace aus der Gesundheitsdatenquelle liest.
public enum ActivityMetric: String, CaseIterable, Hashable, Sendable {
    /// Alle Schritte (dedupliziert über alle Quellen), inklusive manuell eingetragener.
    case steps
    /// Schritte ohne manuell eingetragene Samples.
    case competitionSteps
    /// Gehen + Laufen in Metern.
    case walkingRunningDistance
    /// Aktive Energie in Kilokalorien.
    case activeEnergy
    /// Gestiegene Stockwerke.
    case flightsClimbed
    /// Trainingsminuten.
    case exerciseTime
}

/// Liest Tageswerte aus einer Gesundheitsdatenquelle (in der App: HealthKit).
public protocol ActivityDataProviding: Sendable {
    /// Summe je Kalendertag für alle Tage von `days`, dedupliziert über alle Quellen.
    /// Tage ohne lesbare Samples fehlen im Ergebnis.
    func dailyTotals(
        of metric: ActivityMetric,
        for days: ClosedRange<LocalDate>,
        calendar: ActivityCalendar
    ) async throws -> [LocalDate: Double]

    /// Summe je Stunde eines Tages (0–23, Ortszeit), dedupliziert über alle Quellen. Stunden ohne Samples fehlen.
    /// An Tagen mit Zeitumstellung fallen zwei gleich benannte Stunden zusammen bzw. eine fehlt.
    func hourlyTotals(
        of metric: ActivityMetric,
        on day: LocalDate,
        calendar: ActivityCalendar
    ) async throws -> [Int: Double]

    /// Ob für die Kennzahl überhaupt irgendein Sample lesbar ist – unabhängig vom Zeitraum.
    func hasAnySamples(of metric: ActivityMetric) async throws -> Bool

    /// Meldet, dass sich Bewegungsdaten geändert haben. Der Stream endet, wenn der konsumierende Task beendet wird.
    func activityChanges() -> AsyncStream<Void>
}
