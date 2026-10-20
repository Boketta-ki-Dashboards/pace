import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Namen, Profilbild und Auffindbarkeit (Migration 20261019100000) sowie tolerantes Lesen ohne die neuen Spalten.
struct ProfileExtensionsRepositoryTests {
    private let userID = UserID(BackendTestHarness.userID)

    private static func profileJSON(avatar: String? = nil, discoverable: Bool = true) -> String {
        let avatarJSON = avatar.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(BackendTestHarness.userID.uuidString.lowercased())","public_id":"9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f",
         "username":"Niklas_76","display_name":"Niklas","municipality_id":"DE:06432018",
         "regional_leaderboard_enabled":false,"created_at":"2026-10-16T12:34:56.123456+00:00",
         "updated_at":"2026-10-16T12:35:00+00:00","avatar_path":\(avatarJSON),"is_discoverable":\(discoverable)}
        """
    }

    @Test func newFieldsAreDecoded() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles", .json(Self.profileJSON(avatar: "9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f/a.jpg", discoverable: false)))

        let profile = try #require(try await harness.backend.profiles.fetchProfile(for: userID))

        #expect(profile.avatarPath == "9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f/a.jpg")
        #expect(!profile.isDiscoverable)
    }

    @Test func missingColumnsBeforeTheMigrationFallBackToTheOldColumnList() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles") { request in
            if request.query("select")?.contains("avatar_path") == true {
                return .postgrestError(status: 400, code: "42703", message: "column profiles.avatar_path does not exist")
            }
            return .json(BackendTestHarness.profileJSON())
        }

        let profile = try #require(try await harness.backend.profiles.fetchProfile(for: userID))

        #expect(harness.requests("GET", pathPrefix: "/rest/v1/profiles").count == 2)
        #expect(harness.lastRequest("GET", "/rest/v1/profiles")?.query("select")?.contains("avatar_path") == false)
        #expect(profile.avatarPath == nil)
        #expect(profile.isDiscoverable)
    }

    @Test func updateNamesSendsOnlyTheChangedNormalizedValues() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("PATCH", "/rest/v1/profiles", .json(Self.profileJSON()))

        _ = try await harness.backend.profiles.updateNames(username: nil, displayName: "  Niklas B. ", for: userID)

        let request = try #require(harness.lastRequest("PATCH", "/rest/v1/profiles"))
        #expect(try request.jsonBody() == .object(["display_name": .string("Niklas B.")]))
        #expect(request.query("id") == "eq.\(userID.description)")

        _ = try await harness.backend.profiles.updateNames(username: " Niklas_77 ", displayName: nil, for: userID)
        #expect(try harness.lastRequest("PATCH", "/rest/v1/profiles")?.jsonBody() == .object(["username": .string("Niklas_77")]))
    }

    @Test func updateNamesWithoutChangesOnlyLoadsTheProfile() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles", .json(Self.profileJSON()))

        let profile = try await harness.backend.profiles.updateNames(username: nil, displayName: nil, for: userID)

        #expect(profile.username == "Niklas_76")
        #expect(harness.lastRequest("PATCH", "/rest/v1/profiles") == nil)
    }

    @Test func avatarAndDiscoverabilityUpdates() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("PATCH", "/rest/v1/profiles", .json(Self.profileJSON()))

        _ = try await harness.backend.profiles.updateAvatar(path: nil, for: userID)
        #expect(try harness.lastRequest("PATCH", "/rest/v1/profiles")?.jsonBody() == .object(["avatar_path": .null]))

        _ = try await harness.backend.profiles.updateAvatar(path: "9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f/b.png", for: userID)
        #expect(try harness.lastRequest("PATCH", "/rest/v1/profiles")?.jsonBody()
            == .object(["avatar_path": .string("9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f/b.png")]))

        _ = try await harness.backend.profiles.updateDiscoverable(false, for: userID)
        #expect(try harness.lastRequest("PATCH", "/rest/v1/profiles")?.jsonBody() == .object(["is_discoverable": .bool(false)]))
    }

    @Test func serverErrorsOfTheNewRulesAreMapped() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()

        harness.stub("PATCH", "/rest/v1/profiles", .postgrestError(status: 400, code: "P0001", message: "rate_limited"))
        await #expect(throws: ProfileError.rateLimited) {
            try await harness.backend.profiles.updateNames(username: "Neu_Name", displayName: nil, for: userID)
        }

        harness.stub("PATCH", "/rest/v1/profiles", .postgrestError(status: 400, code: "23514", message: "invalid_avatar_path"))
        await #expect(throws: ProfileError.unexpected("Ungültiges Profilbild.")) {
            try await harness.backend.profiles.updateAvatar(path: "x/y.jpg", for: userID)
        }

        harness.stub("POST", "/rest/v1/rpc/is_username_available", .postgrestError(status: 400, code: "P0001", message: "rate_limited"))
        await #expect(throws: ProfileError.rateLimited) {
            try await harness.backend.profiles.isUsernameAvailable("someone")
        }

        // Ohne Migration 20261019100000 kennt der Server `is_discoverable` nicht.
        harness.stub("PATCH", "/rest/v1/profiles", .postgrestError(
            status: 400,
            code: "PGRST204",
            message: "Could not find the 'is_discoverable' column of 'profiles' in the schema cache"
        ))
        await #expect(throws: ProfileError.unavailable) {
            try await harness.backend.profiles.updateDiscoverable(false, for: userID)
        }
    }
}
