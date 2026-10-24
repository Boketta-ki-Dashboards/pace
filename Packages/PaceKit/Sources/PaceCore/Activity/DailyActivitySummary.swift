import Foundation

/// Aggregierte Bewegungswerte eines Kalendertags. Plattformunabhängig, enthält keine HealthKit-Rohdaten.
///
/// Optionale Werte sind `nil`, wenn für diese Kennzahl gar keine Daten lesbar sind (z. B. kein Zugriff
/// oder kein Gerät, das sie erfasst). Ist die Kennzahl grundsätzlich lesbar, an diesem Tag aber ohne Samples,
/// ist der Wert `0`.
public struct DailyActivitySummary: Equatable, Sendable {
    public let date: LocalDate
    /// Persönliche Schrittzahl laut Apple Health (inklusive manuell eingetragener Schritte).
    public let healthSteps: Int
    /// Für Wettbewerbe gültige Schritte: ohne manuell eingetragene Schritte.
    public let competitionSteps: Int
    public let walkingRunningDistanceMeters: Double?
    public let activeEnergyKilocalories: Double?
    public let flightsClimbed: Int?
    public let exerciseMinutes: Int?
    /// Von Pace geschätzte aktive Kalorien – nur, wenn Apple Health keine gemessenen liefert und die Schätzung
    /// eingeschaltet ist (``estimatingActiveEnergy(with:)``). Nie zusätzlich zu gemessenen Werten.
    public let estimatedActiveEnergyKilocalories: Double?

    public init(
        date: LocalDate,
        healthSteps: Int,
        competitionSteps: Int,
        walkingRunningDistanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        flightsClimbed: Int? = nil,
        exerciseMinutes: Int? = nil,
        estimatedActiveEnergyKilocalories: Double? = nil
    ) {
        self.date = date
        self.healthSteps = healthSteps
        self.competitionSteps = competitionSteps
        self.walkingRunningDistanceMeters = walkingRunningDistanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.flightsClimbed = flightsClimbed
        self.exerciseMinutes = exerciseMinutes
        self.estimatedActiveEnergyKilocalories = estimatedActiveEnergyKilocalories
    }

    /// `true`, wenn sich Health- und Wettbewerbsschritte unterscheiden – in der Regel wegen manuell eingetragener Schritte.
    public var hasNonCompetitionSteps: Bool {
        healthSteps != competitionSteps
    }
}
