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

    // MARK: Optionale Herzwerte (nur auf ausdrücklichen Wunsch, nie ans Backend)

    /// Ob Ruhepuls und Puls beim Gehen gelesen werden können bzw. ob schon danach gefragt wurde.
    /// Standard: `.unavailable` (Quelle ohne Herzwerte).
    func heartRateAccess() async -> HeartRateAccess

    /// Fragt – getrennt von der Abfrage der Bewegungsdaten beim ersten Start – nach dem Lesezugriff auf Ruhepuls und
    /// Puls beim Gehen. Nur auf ausdrücklichen Wunsch des Nutzers aufrufen. Standard: ohne Wirkung.
    func requestHeartRateAccess() async throws

    /// Ruhepuls und durchschnittlicher Puls beim Gehen an einem Tag. Fehlende Werte sind `nil` – nie geschätzt und
    /// nie `0`. Standard: keine Werte.
    func dailyHeartRate(on day: LocalDate, calendar: ActivityCalendar) async throws -> DailyHeartRate
}

extension ActivityDataProviding {
    public func heartRateAccess() async -> HeartRateAccess {
        .unavailable
    }

    public func requestHeartRateAccess() async throws {}

    public func dailyHeartRate(on day: LocalDate, calendar: ActivityCalendar) async throws -> DailyHeartRate {
        .empty
    }
}

/// Zugriff auf die optionalen Herzwerte.
public enum HeartRateAccess: Equatable, Sendable {
    /// Die Datenquelle bietet keine Herzwerte an (z. B. ohne Apple Health) – es gibt nichts anzufragen.
    case unavailable
    /// Noch nicht gefragt: Die Tagesdetails bieten die Freigabe an.
    case notRequested
    /// Bereits gefragt. Ob zugestimmt wurde, verrät Apple Health bei Lesezugriffen nicht – ohne Zustimmung gibt es
    /// schlicht keine Werte.
    case requested
}

/// Optionale Herzwerte eines Tages. Bleiben auf dem Gerät und werden nie an das Backend übertragen.
public struct DailyHeartRate: Equatable, Sendable {
    /// Ruhepuls in Schlägen pro Minute (Durchschnitt des Tages); `nil` ohne Messwerte.
    public let restingBeatsPerMinute: Double?
    /// Durchschnittlicher Puls beim Gehen in Schlägen pro Minute; `nil` ohne Messwerte.
    public let walkingAverageBeatsPerMinute: Double?

    public init(restingBeatsPerMinute: Double?, walkingAverageBeatsPerMinute: Double?) {
        self.restingBeatsPerMinute = restingBeatsPerMinute.flatMap { $0 > 0 ? $0 : nil }
        self.walkingAverageBeatsPerMinute = walkingAverageBeatsPerMinute.flatMap { $0 > 0 ? $0 : nil }
    }

    public static let empty = DailyHeartRate(restingBeatsPerMinute: nil, walkingAverageBeatsPerMinute: nil)

    /// Ob mindestens ein Wert vorliegt.
    public var hasValues: Bool {
        restingBeatsPerMinute != nil || walkingAverageBeatsPerMinute != nil
    }
}
