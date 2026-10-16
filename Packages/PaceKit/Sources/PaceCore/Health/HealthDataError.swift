import Foundation

/// Fehler beim Zugriff auf Gesundheitsdaten, unabhängig von der konkreten Datenquelle.
public enum HealthDataError: Error, Equatable, Sendable {
    /// Das Gerät unterstützt keine Gesundheitsdaten (oder sie sind per Richtlinie gesperrt).
    case healthDataUnavailable
    /// Die Daten sind geschützt, solange das Gerät gesperrt ist.
    case protectedDataUnavailable
    /// Die Zugriffsanfrage ist fehlgeschlagen (z. B. fehlendes Entitlement).
    case authorizationRequestFailed(reason: String)
    /// Eine Abfrage ist aus anderem Grund fehlgeschlagen.
    case queryFailed(reason: String)
}
