import Auth
import Foundation
import PaceCore
import Storage
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
                // Profilbild außerhalb des eigenen Ordners, nicht hochgeladen oder mit ungültigem Namen.
                if message.contains("avatar") { return .unexpected("Ungültiges Profilbild.") }
                return .invalidUsername
            case "23503":
                // Ungültige Gemeinden fängt schon ein Trigger ab (23514). Ein Fremdschlüsselfehler auf die Auth-ID
                // bedeutet, dass der Nutzer serverseitig nicht mehr existiert.
                return message.contains("profiles_id_fkey") ? .notAuthenticated : .invalidRegion
            case "PGRST116":
                // Kein Profil getroffen (z. B. fremde oder fehlende Zeile): wie eine fehlende Anmeldung behandeln.
                return .notAuthenticated
            case "PGRST204":
                // Spalte unbekannt (z. B. `is_discoverable`): Migration 20261019100000 ist auf dem Server noch nicht
                // eingespielt.
                return .unavailable
            default:
                // Benutzername zu oft geändert bzw. zu viele Verfügbarkeitsprüfungen (Migration 20261019100000).
                if message.contains("rate_limited") { return .rateLimited }
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
            // `region_not_allowed`: Die Region gehört nicht (mehr) zur eigenen Gemeinde, z. B. nach einem
            // Regionswechsel auf einem anderen Weg.
            if code == "22023", message.contains("unknown_region") || message.contains("region_not_allowed") {
                return .unknownRegion
            }
            return .unexpected("\(code): \(message)")
        case .unknown(let description):
            return .unexpected(description)
        }
    }

    /// Fehler der Social-RPCs: stabile Tokens in der Meldung (siehe docs/SOCIAL.md).
    static func socialError(_ error: any Error) -> SocialError {
        switch BackendFailure(error) {
        case .network:
            return .network
        case .unauthenticated, .permissionDenied:
            return .notAuthenticated
        case .database(let code, let message):
            // PGRST202: Funktion unbekannt – die Social-Migration ist auf dem Server noch nicht eingespielt.
            if code == "PGRST202" || code == "42883" {
                return .unavailable
            }
            return socialTokens.first { message.contains($0.token) }?.error ?? .unexpected("\(code): \(message)")
        case .unknown(let description):
            return .unexpected(description)
        }
    }

    /// Reihenfolge wichtig: spezifische Tokens vor allgemeineren.
    private static let socialTokens: [(token: String, error: SocialError)] = [
        ("invalid_invite_code", .invalidInviteCode),
        ("invalid_name", .invalidName),
        ("invalid_description", .invalidDescription),
        ("invalid_goal", .invalidGoal),
        ("invalid_kind", .invalidInput),
        ("invalid_privacy", .invalidInput),
        ("invalid_image_path", .invalidInput),
        ("invalid_time_zone", .invalidInput),
        ("invalid_period", .invalidInput),
        ("invalid_date", .invalidInput),
        ("invalid_message", .invalidMessage),
        ("invalid_nickname", .invalidNickname),
        ("invalid_input", .invalidInput),
        ("read_only", .readOnly),
        ("blocked", .blocked),
        ("self_request", .selfRequest),
        ("rate_limited", .rateLimited),
        ("cooldown", .cooldown),
        ("pin_limit_reached", .pinLimitReached),
        ("limit_reached", .limitReached),
        ("not_allowed", .notAllowed),
        ("not_found", .notFound),
        ("profile_required", .notAuthenticated),
        ("not_authenticated", .notAuthenticated),
    ]

    /// Fehler von Supabase Storage (eigenes Fehlerformat mit `statusCode` als Text) und der Größen-/Typprüfung.
    static func mediaError(_ error: any Error) -> MediaError {
        if let error = error as? MediaError {
            return error
        }
        if error is URLError {
            return .network
        }
        if let error = error as? StorageError {
            return mediaError(status: error.statusCode.flatMap { Int($0) }, text: "\(error.error ?? "") \(error.message)")
        }
        if let error = error as? HTTPError {
            return mediaError(status: error.response.statusCode, text: String(decoding: error.data, as: UTF8.self))
        }
        return .unexpected(String(describing: error))
    }

    private static func mediaError(status: Int?, text: String) -> MediaError {
        let lowered = text.lowercased()
        if lowered.contains("bucket not found") {
            // Buckets fehlen: Migration 20261019100300 ist auf dem Server noch nicht eingespielt.
            return .unavailable
        }
        if status == 413 || lowered.contains("maximum allowed size") || lowered.contains("too large") {
            return .tooLarge
        }
        if status == 415 || lowered.contains("mime") {
            return .unsupportedType
        }
        if status == 404 || lowered.contains("not found") {
            return .notFound
        }
        if status == 401 || status == 403 || lowered.contains("row-level security") || lowered.contains("unauthorized") {
            return .notAllowed
        }
        return .unexpected("\(status.map(String.init) ?? "–"): \(text)")
    }

    /// Fehler der Datenschutz-RPCs (`account_*`, `submit_feedback`).
    static func accountError(_ error: any Error) -> AccountError {
        switch BackendFailure(error) {
        case .network:
            return .network
        case .unauthenticated, .permissionDenied:
            return .notAuthenticated
        case .database(let code, let message):
            if code == "PGRST202" || code == "42883" {
                return .unavailable
            }
            if message.contains("rate_limited") { return .rateLimited }
            if message.contains("invalid_input") { return .invalidInput }
            if message.contains("profile_required") || message.contains("not_authenticated") { return .notAuthenticated }
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
