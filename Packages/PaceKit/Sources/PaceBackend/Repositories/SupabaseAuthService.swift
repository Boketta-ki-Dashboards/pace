import Auth
import Foundation
import PaceCore

/// Anmeldung über Supabase Auth. In Milestone 2 nur die anonyme MVP-Identität.
struct SupabaseAuthService: AuthProviding {
    let client: AuthClient

    /// Die gespeicherte Sitzung, auch wenn das Access Token abgelaufen ist – es wird vor der nächsten Anfrage mit dem
    /// Refresh Token erneuert.
    func restoreSession() async -> AuthSession? {
        client.currentSession.map(AuthSession.init(supabaseSession:))
    }

    func signInAnonymously() async throws -> AuthSession {
        do {
            return AuthSession(supabaseSession: try await client.signInAnonymously())
        } catch {
            throw BackendErrorMapping.authError(error)
        }
    }

    /// Entfernt die lokale Sitzung (Keychain). Der Server wird nicht benötigt – z. B. nach dem Löschen des Kontos ist
    /// das Token ohnehin ungültig.
    func signOut() async {
        try? await client.signOut(scope: .local)
    }
}

extension AuthSession {
    init(supabaseSession session: Session) {
        self.init(userID: UserID(session.user.id), isAnonymous: session.user.isAnonymous)
    }
}
