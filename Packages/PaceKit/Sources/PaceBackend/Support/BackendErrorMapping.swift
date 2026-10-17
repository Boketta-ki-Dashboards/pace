import Auth
import Foundation
import PaceCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Übersetzt Backend-Fehler in die Fehler aus PaceCore (siehe Backend-Vertrag in docs/BACKEND.md).
enum BackendErrorMapping {
    static func profileError(_ error: any Error) -> ProfileError {
        switch BackendFailure(error) {
        case .network:
            return .network
        case .unauthenticated, .permissionDenied:
            return .notAuthenticated
        case .database(let code, let message):
            switch code {
            case "23505":
                // Einzige eindeutige Spalte, die Nutzer selbst wählen, ist der Benutzername. Ein zweites Profil
                // für dieselbe ID ist dagegen kein Namenskonflikt.
                return message.contains("profiles_pkey") ? .unexpected("Profil existiert bereits.") : .usernameTaken
            case "23514":
                if message.contains("invalid_municipality") { return .invalidRegion }
                if message.contains("display_name") { return .invalidDisplayName }
                return .invalidUsername
            case "23503":
                return .invalidRegion
            case "PGRST116":
                // Kein Profil getroffen (z. B. fremde oder fehlende Zeile): wie eine fehlende Anmeldung behandeln.
                return .notAuthenticated
            default:
                return .unexpected("\(code): \(message)")
            }
        case .unknown(let description):
            return .unexpected(description)
        }
    }

    static func regionError(_ error: any Error) -> RegionError {
        switch BackendFailure(error) {
        case .network:
            return .network
        case .unauthenticated, .permissionDenied:
            return .unexpected("Nicht angemeldet.")
        case .database(let code, let message):
            return .unexpected("\(code): \(message)")
        case .unknown(let description):
            return .unexpected(description)
        }
    }

    /// - Parameter hasSession: Ob beim Senden eine Sitzung bestand. Dann bedeutet `42501`, dass der Server die
    ///   Werte abgelehnt hat (z. B. Tag außerhalb des erlaubten Fensters), nicht dass die Anmeldung fehlt.
    static func activitySyncError(_ error: any Error, hasSession: Bool) -> ActivitySyncError {
        switch BackendFailure(error) {
        case .network:
            return .network
        case .unauthenticated:
            return .notAuthenticated
        case .permissionDenied:
            return hasSession ? .rejected : .notAuthenticated
        case .database(let code, let message):
            // Verletzte Check-/Fremdschlüssel-/Not-null-Constraint bzw. ungültiges Datum oder ungültige Zahl.
            let rejectedCodes: Set<String> = ["23514", "23503", "23502", "22007", "22008", "22003"]
            return rejectedCodes.contains(code) ? .rejected : .unexpected("\(code): \(message)")
        case .unknown(let description):
            return .unexpected(description)
        }
    }

    static func leaderboardError(_ error: any Error) -> LeaderboardError {
        switch BackendFailure(error) {
        case .network:
            return .network
        case .unauthenticated, .permissionDenied:
            return .notAuthenticated
        case .database(let code, let message):
            if code == "22023", message.contains("unknown_region") {
                return .unknownRegion
            }
            return .unexpected("\(code): \(message)")
        case .unknown(let description):
            return .unexpected(description)
        }
    }

    static func authError(_ error: any Error) -> PaceCore.AuthError {
        if error is URLError {
            return .network
        }
        guard let authError = error as? Auth.AuthError else {
            return .unexpected(String(describing: error))
        }
        guard case .api(let message, let code, _, let response) = authError else {
            return .unexpected(authError.localizedDescription)
        }
        if code == .anonymousProviderDisabled {
            return .anonymousSignInDisabled
        }
        if rateLimitCodes.contains(code) || response.statusCode == 429 {
            return .rateLimited
        }
        return .unexpected("\(code.rawValue): \(message)")
    }

    private static let rateLimitCodes: Set<ErrorCode> = [
        .overRequestRateLimit, .overEmailSendRateLimit, .overSMSSendRateLimit,
    ]
}
