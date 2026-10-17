import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PaceBackend
import PaceCore
import PaceTestSupport

/// Ein `SupabaseBackend` gegen den URLProtocol-Stub. Jede Instanz hat einen eigenen Host.
final class BackendTestHarness: Sendable {
    static let publishableKey = "sb_publishable_testkey"
    static let userID = UUID(uuidString: "6f1c2a8e-1b2c-4d5e-8f90-0123456789ab")!

    let host: String
    let backend: SupabaseBackend
    private let requests = Locked<[RecordedRequest]>([])
    private let routes = Locked<[(method: String, path: String, outcome: StubOutcome)]>([])

    init() {
        host = "\(UUID().uuidString.lowercased().prefix(12)).supabase.test"
        let configuration = BackendConfiguration(
            supabaseURL: URL(string: "https://\(host)")!,
            publishableKey: Self.publishableKey,
            projectRef: String(host.prefix(12))
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        backend = SupabaseBackend(
            configuration: configuration,
            localStorage: InMemoryAuthStorage(),
            session: URLSession(configuration: sessionConfiguration)
        )

        let requests = self.requests
        let routes = self.routes
        StubRegistry.register(host: host) { request in
            requests.withLock { $0.append(request) }
            let match = routes.withLock { routes in
                routes.last { $0.method == request.method && $0.path == request.path }
            }
            return match?.outcome ?? .json(#"{"code":"PGRST000","details":null,"hint":null,"message":"no stub"}"#, status: 500)
        }
    }

    deinit {
        StubRegistry.unregister(host: host)
    }

    /// Antwort für Methode + Pfad (der zuletzt registrierte Eintrag gewinnt).
    func stub(_ method: String, _ path: String, _ outcome: StubOutcome) {
        routes.withLock { $0.append((method, path, outcome)) }
    }

    var recorded: [RecordedRequest] {
        requests.current
    }

    func lastRequest(_ method: String, _ path: String) -> RecordedRequest? {
        recorded.last { $0.method == method && $0.path == path }
    }

    /// Meldet anonym an, damit Folgeanfragen ein Access Token tragen.
    @discardableResult
    func signIn() async throws -> AuthSession {
        stub("POST", "/auth/v1/signup", .json(Self.sessionJSON()))
        return try await backend.auth.signInAnonymously()
    }

    /// Unsigniertes, syntaktisch gültiges JWT (nur für Tests).
    static var accessToken: String {
        func base64URL(_ string: String) -> String {
            Data(string.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(#"{"alg":"HS256","typ":"JWT"}"#)
        let exp = Int(Date().timeIntervalSince1970) + 3_600
        let payload = base64URL(#"{"sub":"\#(userID.uuidString.lowercased())","role":"authenticated","is_anonymous":true,"exp":\#(exp)}"#)
        return "\(header).\(payload).test"
    }

    /// Antwort von GoTrue auf `POST /auth/v1/signup` für eine anonyme Anmeldung.
    static func sessionJSON() -> String {
        let now = Int(Date().timeIntervalSince1970)
        return """
        {"access_token":"\(accessToken)","token_type":"bearer","expires_in":3600,"expires_at":\(now + 3_600),
         "refresh_token":"refresh-token","user":{"id":"\(userID.uuidString.lowercased())","aud":"authenticated",
         "role":"authenticated","email":"","phone":"","app_metadata":{"provider":"anonymous","providers":["anonymous"]},
         "user_metadata":{},"identities":[],"created_at":"2026-10-16T10:00:00.123456Z",
         "updated_at":"2026-10-16T10:00:00.123456Z","is_anonymous":true}}
        """
    }

    /// Profilzeile, wie PostgREST sie liefert.
    static func profileJSON(municipalityID: String? = "DE:06432018", optIn: Bool = false) -> String {
        let municipality = municipalityID.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(userID.uuidString.lowercased())","public_id":"9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f",
         "username":"Niklas_76","display_name":"Niklas","municipality_id":\(municipality),
         "regional_leaderboard_enabled":\(optIn),"created_at":"2026-10-16T12:34:56.123456+00:00",
         "updated_at":"2026-10-16T12:35:00+00:00"}
        """
    }

    /// Hierarchie-Zeile für Pfungstadt, wie `search_municipalities` sie liefert.
    static let pfungstadtRowJSON = """
    {"municipality_id":"DE:06432018","municipality_code":"06432018","municipality_name":"Pfungstadt",
     "municipality_kind":"stadt","district_id":"DE:06432","district_code":"06432","district_name":"Darmstadt-Dieburg",
     "district_kind":"landkreis","district_municipality_count":23,"state_id":"DE:06","state_code":"06",
     "state_name":"Hessen","state_municipality_count":421,"country_id":"DE","country_code":"DE",
     "country_name":"Deutschland","country_municipality_count":10749}
    """
}
