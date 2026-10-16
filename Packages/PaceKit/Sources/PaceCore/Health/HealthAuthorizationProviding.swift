import Foundation

/// Ob der Nutzer bereits nach dem Zugriff auf Gesundheitsdaten gefragt wurde.
///
/// Für reine Lesezugriffe kann HealthKit nicht sagen, ob der Nutzer zugestimmt oder abgelehnt hat –
/// nur, ob die Abfrage schon einmal angezeigt wurde.
public enum HealthAuthorizationRequestStatus: Equatable, Sendable {
    /// Der Nutzer wurde noch nicht gefragt.
    case shouldRequest
    /// Die Abfrage wurde bereits angezeigt (Ergebnis unbekannt).
    case alreadyRequested
    /// Der Status konnte nicht ermittelt werden.
    case unknown
}

/// Fragt den Zugriff auf die für Pace benötigten Gesundheitsdaten an.
public protocol HealthAuthorizationProviding: Sendable {
    /// Ob Gesundheitsdaten auf diesem Gerät grundsätzlich verfügbar sind.
    var isHealthDataAvailable: Bool { get }

    func authorizationRequestStatus() async throws -> HealthAuthorizationRequestStatus

    /// Zeigt bei Bedarf den System-Dialog. Kehrt zurück, sobald der Nutzer ihn geschlossen hat –
    /// unabhängig davon, ob er zugestimmt hat.
    func requestAuthorization() async throws
}
