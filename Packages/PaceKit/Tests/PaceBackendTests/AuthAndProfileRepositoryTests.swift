import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

struct AuthServiceTests {
    @Test func noStoredSessionBeforeSignIn() async {
        let harness = BackendTestHarness()

        #expect(await harness.backend.auth.restoreSession() == nil)
    }

    @Test func anonymousSignInStoresSessionAndSendsOnlyAPIKey() async throws {
        let harness = BackendTestHarness()

        let session = try await harness.signIn()

        #expect(session.userID == UserID(BackendTestHarness.userID))
        #expect(session.isAnonymous)
        #expect(await harness.backend.auth.restoreSession() == session)
        let request = try #require(harness.lastRequest("POST", "/auth/v1/signup"))
        #expect(request.header("apikey") == BackendTestHarness.publishableKey)
        #expect(request.header("Authorization")?.contains(BackendTestHarness.publishableKey) != true)
    }

    @Test func disabledAnonymousSignInIsMapped() async {
        let harness = BackendTestHarness()
        // Format aktueller GoTrue-Versionen (API-Version 2024-01-01).
        harness.stub("POST", "/auth/v1/signup", .json(
            #"{"code":"anonymous_provider_disabled","message":"Anonymous sign-ins are disabled"}"#,
            status: 422,
            headers: ["X-Supabase-Api-Version": "2024-01-01"]
        ))

        await #expect(throws: PaceCore.AuthError.anonymousSignInDisabled) {
            try await harness.backend.auth.signInAnonymously()
        }
    }

    @Test func networkFailureDuringSignInIsMapped() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/auth/v1/signup", .failure(URLError(.notConnectedToInternet)))

        await #expect(throws: PaceCore.AuthError.network) {
            try await harness.backend.auth.signInAnonymously()
        }
    }
}

struct ProfileRepositoryTests {
    private let userID = UserID(BackendTestHarness.userID)

    @Test func fetchSelectsContractColumnsWithSessionToken() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles", .json(BackendTestHarness.profileJSON()))

        let profile = try #require(try await harness.backend.profiles.fetchProfile(for: userID))

        let request = try #require(harness.lastRequest("GET", "/rest/v1/profiles"))
        #expect(request.query("select") == "id,public_id,username,display_name,municipality_id,regional_leaderboard_enabled,created_at,updated_at")
        #expect(request.query("id") == "eq.\(userID.description)")
        #expect(request.header("apikey") == BackendTestHarness.publishableKey)
        #expect(request.header("Authorization") == "Bearer \(BackendTestHarness.accessToken)")
        #expect(profile.username == "Niklas_76")
        #expect(profile.municipalityID == "DE:06432018")
        #expect(!profile.regionalLeaderboardEnabled)
        #expect(abs(profile.createdAt.timeIntervalSince1970 - 1_792_154_096.123456) < 0.000_01)
    }

    @Test func requestsWithoutSessionCarryNoAuthorizationHeader() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/is_username_available", .json("true"))

        _ = try await harness.backend.profiles.isUsernameAvailable("niklas")

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/is_username_available"))
        #expect(request.header("Authorization") == nil)
        #expect(request.header("apikey") == BackendTestHarness.publishableKey)
        #expect(try request.jsonBody() == .object(["p_username": .string("niklas")]))
    }

    @Test func missingProfileIsNil() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles", .postgrestError(
            status: 406, code: "PGRST116",
            message: "JSON object requested, multiple (or no) rows returned",
            details: "The result contains 0 rows"
        ))

        #expect(try await harness.backend.profiles.fetchProfile(for: userID) == nil)
    }

    @Test func createSendsNormalizedNamesOnly() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/profiles", .json(BackendTestHarness.profileJSON(municipalityID: nil), status: 201))

        let profile = try await harness.backend.profiles.createProfile(
            NewProfile(username: "  Niklas_76 ", displayName: "  Niklas   Z "),
            for: userID
        )

        let request = try #require(harness.lastRequest("POST", "/rest/v1/profiles"))
        let body = try request.jsonBody()
        #expect(body.objectKeys == ["id", "username", "display_name"])
        #expect(body["username"] == .string("Niklas_76"))
        #expect(body["display_name"] == .string("Niklas Z"))
        #expect(body["id"] == .string(userID.description))
        #expect(profile.municipalityID == nil)
    }

    @Test func updateRegionSendsOnlyMunicipalityIDAndConsent() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("PATCH", "/rest/v1/profiles", .json(BackendTestHarness.profileJSON(optIn: true)))

        let profile = try await harness.backend.profiles.updateRegion(
            municipalityID: "DE:06432018",
            regionalLeaderboardEnabled: true,
            for: userID
        )

        let request = try #require(harness.lastRequest("PATCH", "/rest/v1/profiles"))
        #expect(try request.jsonBody() == .object([
            "municipality_id": .string("DE:06432018"),
            "regional_leaderboard_enabled": .bool(true),
        ]))
        #expect(request.query("id") == "eq.\(userID.description)")
        #expect(profile.regionalLeaderboardEnabled)
    }

    @Test(arguments: [
        ("23505", "duplicate key value violates unique constraint \\\"profiles_username_lower_key\\\"", ProfileError.usernameTaken),
        ("23514", "new row for relation \\\"profiles\\\" violates check constraint \\\"profiles_username_format\\\"", .invalidUsername),
        ("23514", "new row for relation \\\"profiles\\\" violates check constraint \\\"profiles_display_name_valid\\\"", .invalidDisplayName),
        ("23514", "invalid_municipality", .invalidRegion),
        ("23503", "insert or update on table \\\"profiles\\\" violates foreign key constraint", .invalidRegion),
        ("23503", "insert or update on table \\\"profiles\\\" violates foreign key constraint \\\"profiles_id_fkey\\\"", .notAuthenticated),
        ("42501", "new row violates row-level security policy for table \\\"profiles\\\"", .notAuthenticated),
    ])
    func databaseErrorsAreMapped(code: String, message: String, expected: ProfileError) async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/profiles", .postgrestError(status: 409, code: code, message: message))

        await #expect(throws: expected) {
            try await harness.backend.profiles.createProfile(NewProfile(username: "niklas", displayName: "Niklas"), for: userID)
        }
    }

    @Test func networkErrorIsMapped() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles", .failure(URLError(.timedOut)))

        await #expect(throws: ProfileError.network) {
            try await harness.backend.profiles.fetchProfile(for: userID)
        }
    }
}
