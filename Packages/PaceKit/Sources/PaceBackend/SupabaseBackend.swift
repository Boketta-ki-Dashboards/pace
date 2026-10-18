import Auth
import Foundation
import PaceCore
import PostgREST
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supabase-Anbindung von Pace. Wird einmal im Composition Root der App erzeugt; Features sehen nur die Protokolle
/// aus PaceCore.
///
/// - Auth und PostgREST werden direkt verwendet (ohne `SupabaseClient`), damit der Publishable Key nur im Header
///   `apikey` steht und `Authorization` ausschließlich das Access Token einer Sitzung trägt.
/// - Automatische Wiederholungen von PostgREST sind aus: Die App wiederholt selbst (nächster Sync-Anlass,
///   „Erneut versuchen“, Pull-to-Refresh), statt offline mehrere Sekunden zu warten.
public final class SupabaseBackend: Sendable {
    public let configuration: BackendConfiguration
    public let auth: any AuthProviding
    public let profiles: any ProfileRepository
    public let regions: any RegionRepository
    public let activitySync: any ActivitySyncRepository
    public let leaderboards: any LeaderboardRepository
    public let social: any SocialRepository

    /// - Parameters:
    ///   - localStorage: Speicher der Sitzung (in der App die Keychain, in Tests `InMemoryAuthStorage`).
    ///   - session: Für alle Anfragen an Auth und PostgREST.
    public init(
        configuration: BackendConfiguration,
        localStorage: any AuthLocalStorage,
        session: URLSession = .shared
    ) {
        let apiKeyHeader = ["apikey": configuration.publishableKey]
        let authClient = AuthClient(
            url: configuration.authURL,
            headers: apiKeyHeader,
            storageKey: configuration.authStorageKey,
            localStorage: localStorage,
            fetch: { try await session.data(for: $0) },
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
        let tokens = AccessTokenProvider(auth: authClient)
        let database = PostgrestClient(
            url: configuration.restURL,
            schema: "public",
            headers: apiKeyHeader,
            fetch: AuthorizedFetch.handler(session: session, tokens: tokens),
            retryEnabled: false
        )

        self.configuration = configuration
        auth = SupabaseAuthService(client: authClient)
        profiles = SupabaseProfileRepository(client: database)
        regions = SupabaseRegionRepository(client: database)
        activitySync = SupabaseActivitySyncRepository(client: database, tokens: tokens)
        leaderboards = SupabaseLeaderboardRepository(client: database)
        social = SupabaseSocialRepository(client: database)
    }

    #if !os(Linux) && !os(Windows) && !os(Android)
    /// Für die App: Die Sitzung liegt in der Keychain (lesbar nach dem ersten Entsperren, auch im Hintergrund).
    public convenience init(configuration: BackendConfiguration) {
        self.init(configuration: configuration, localStorage: KeychainLocalStorage(service: "app.pace.auth"))
    }
    #endif
}
