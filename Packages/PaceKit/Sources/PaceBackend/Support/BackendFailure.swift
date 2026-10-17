import Auth
import Foundation
import PostgREST
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Einheitliche Einordnung von Fehlern aus PostgREST, Supabase Auth und dem Netzwerk. Die Repositories übersetzen
/// sie in die Fehler aus PaceCore (siehe `BackendErrorMapping`).
enum BackendFailure: Equatable {
    /// Keine, unterbrochene oder abgebrochene Verbindung.
    case network
    /// Keine Sitzung, oder das JWT fehlt, ist abgelaufen bzw. ungültig.
    case unauthenticated
    /// Postgres verweigert den Zugriff (`42501`, z. B. durch Row Level Security).
    case permissionDenied
    /// Anderer Fehler von Postgres bzw. PostgREST, z. B. eine verletzte Constraint.
    case database(code: String, message: String)
    case unknown(String)

    init(_ error: any Error) {
        if error is URLError {
            self = .network
        } else if let error = error as? PostgrestError {
            self = Self.classify(error)
        } else if let error = error as? HTTPError {
            let status = error.response.statusCode
            self = status == 401 || status == 403 ? .unauthenticated : .unknown("HTTP \(status)")
        } else if let error = error as? Auth.AuthError {
            self = error == .sessionMissing ? .unauthenticated : .unknown(error.localizedDescription)
        } else if error is DecodingError {
            self = .unknown("Die Antwort des Servers konnte nicht gelesen werden.")
        } else {
            self = .unknown(String(describing: error))
        }
    }

    private static func classify(_ error: PostgrestError) -> BackendFailure {
        let code = error.code ?? ""
        if code == "42501" {
            return .permissionDenied
        }
        // PGRST301–PGRST303: JWT fehlt, ist abgelaufen oder ungültig.
        if code.hasPrefix("PGRST30") {
            return .unauthenticated
        }
        return .database(code: code, message: error.message)
    }
}
