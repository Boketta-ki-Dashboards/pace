import Auth
import Foundation
import PostgREST
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Liefert das Access Token der gespeicherten Sitzung für Anfragen an PostgREST.
struct AccessTokenProvider: Sendable {
    /// Ob lokal eine Sitzung gespeichert ist – ohne Netzwerk, die Sitzung kann abgelaufen sein.
    let hasSession: @Sendable () -> Bool
    /// Gültiges Access Token, bei Bedarf erneuert. `nil`, wenn keine Sitzung gespeichert ist. Scheitert die
    /// Erneuerung, wird der Fehler weitergereicht, statt die Anfrage ohne Anmeldung zu senden.
    let accessToken: @Sendable () async throws -> String?
}

extension AccessTokenProvider {
    init(auth: AuthClient) {
        self.init(
            hasSession: { auth.currentSession != nil },
            accessToken: {
                guard auth.currentSession != nil else { return nil }
                return try await auth.session.accessToken
            }
        )
    }
}

enum AuthorizedFetch {
    /// Fetch-Closure für PostgREST. Setzt `Authorization: Bearer <Access Token>` nur mit Sitzung – nie den
    /// Publishable Key, der ausschließlich im Header `apikey` steht.
    static func handler(session: URLSession, tokens: AccessTokenProvider) -> PostgrestClient.FetchHandler {
        { request in
            var request = request
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            if let token = try await tokens.accessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await session.data(for: request)
        }
    }
}
