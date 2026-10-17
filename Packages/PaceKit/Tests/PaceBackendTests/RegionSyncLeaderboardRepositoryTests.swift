import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

struct RegionRepositoryTests {
    @Test func searchCallsRPCWithNormalizedQueryAndDecodesHierarchy() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/search_municipalities", .json("[\(BackendTestHarness.pfungstadtRowJSON)]"))

        let results = try await harness.backend.regions.searchMunicipalities(matching: "  Pfung  ", limit: 200)

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/search_municipalities"))
        #expect(try request.jsonBody() == .object(["p_query": .string("Pfung"), "p_limit": .number(50)]))
        let hierarchy = try #require(results.first)
        #expect(hierarchy.municipality.id == "DE:06432018")
        #expect(hierarchy.municipality.kind == .stadt)
        #expect(hierarchy.district.displayName == "Landkreis Darmstadt-Dieburg")
        #expect(hierarchy.district.municipalityCount == 23)
        #expect(hierarchy.state.id == "DE:06")
        #expect(hierarchy.country.name == "Deutschland")
        #expect(hierarchy.subtitle == "Hessen · Landkreis Darmstadt-Dieburg")
        #expect(hierarchy.leaderboardScopes.map(\.name) == ["Pfungstadt", "Darmstadt-Dieburg", "Hessen", "Deutschland"])
    }

    @Test func tooShortQueryDoesNotHitTheServer() async throws {
        let harness = BackendTestHarness()

        #expect(try await harness.backend.regions.searchMunicipalities(matching: "P", limit: 20).isEmpty)
        #expect(harness.recorded.isEmpty)
    }

    @Test func unknownKindDoesNotBreakDecoding() async throws {
        let harness = BackendTestHarness()
        let row = BackendTestHarness.pfungstadtRowJSON.replacingOccurrences(of: #""municipality_kind":"stadt""#, with: #""municipality_kind":"neue_art""#)
        harness.stub("POST", "/rest/v1/rpc/get_region_hierarchy", .json("[\(row)]"))

        let hierarchy = try await harness.backend.regions.hierarchy(forMunicipality: "DE:06432018")

        #expect(hierarchy.municipality.kind == nil)
        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/get_region_hierarchy"))
        #expect(try request.jsonBody() == .object(["p_municipality_id": .string("DE:06432018")]))
    }

    @Test func missingHierarchyIsNotFound() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/get_region_hierarchy", .json("[]"))

        await #expect(throws: RegionError.notFound) {
            try await harness.backend.regions.hierarchy(forMunicipality: "DE:99999999")
        }
    }
}

struct ActivitySyncRepositoryTests {
    private let userID = UserID(BackendTestHarness.userID)

    @Test func upsertsCompetitionStepsOnUserAndDate() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/daily_activity", .response(status: 201, headers: [:], body: Data()))

        try await harness.backend.activitySync.upsert([
            DailyCompetitionSteps(date: LocalDate(year: 2026, month: 10, day: 16), competitionSteps: 8_742),
            DailyCompetitionSteps(date: LocalDate(year: 2026, month: 10, day: 15), competitionSteps: 999_999),
        ], for: userID)

        let request = try #require(harness.lastRequest("POST", "/rest/v1/daily_activity"))
        #expect(request.query("on_conflict") == "user_id,activity_date")
        #expect(request.preferences.contains("resolution=merge-duplicates"))
        #expect(request.preferences.contains("return=minimal"))
        let body = try request.jsonBody()
        #expect(body.arrayCount == 2)
        #expect(body[0]?.objectKeys == ["user_id", "activity_date", "competition_steps"])
        #expect(body[0]?["activity_date"] == .string("2026-10-15"))
        #expect(body[0]?["competition_steps"] == .number(200_000))
        #expect(body[1]?["activity_date"] == .string("2026-10-16"))
        #expect(body[1]?["competition_steps"] == .number(8_742))
        #expect(body[1]?["user_id"] == .string(userID.description))
    }

    @Test func emptyUpsertSendsNothing() async throws {
        let harness = BackendTestHarness()

        try await harness.backend.activitySync.upsert([], for: userID)

        #expect(harness.recorded.isEmpty)
    }

    @Test func rowLevelSecurityRejectionWithSessionIsRejected() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/daily_activity", .postgrestError(
            status: 403, code: "42501", message: "new row violates row-level security policy for table \\\"daily_activity\\\""
        ))

        await #expect(throws: ActivitySyncError.rejected) {
            try await harness.backend.activitySync.upsert([
                DailyCompetitionSteps(date: LocalDate(year: 2020, month: 1, day: 1), competitionSteps: 1),
            ], for: userID)
        }
    }
}

struct LeaderboardRepositoryTests {
    private let query = LeaderboardQuery(regionID: "DE:06432", period: .daily, date: LocalDate(year: 2026, month: 10, day: 16))

    private let responseJSON = """
    {"total_participants":383,"entries":[
     {"rank":2,"public_user_id":"20000000-0000-4000-8000-000000000002","username":"flavio","display_name":"Flavio","competition_steps":17320,"is_current_user":false},
     {"rank":1,"public_user_id":"20000000-0000-4000-8000-000000000001","username":"leon","display_name":"Leon","competition_steps":18942,"is_current_user":false}
    ]}
    """

    @Test func pageCallsRPCWithClampedParamsAndSortsByRank() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/leaderboard_page", .json(responseJSON))

        let page = try await harness.backend.leaderboards.page(for: query, offset: -5, limit: 500)

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/leaderboard_page"))
        #expect(try request.jsonBody() == .object([
            "p_region_id": .string("DE:06432"),
            "p_period": .string("daily"),
            "p_date": .string("2026-10-16"),
            "p_limit": .number(100),
            "p_offset": .number(0),
        ]))
        #expect(page.totalParticipants == 383)
        #expect(page.entries.map(\.rank) == [1, 2])
        #expect(page.entries.first?.username == "leon")
        #expect(page.offset == 0)
        #expect(page.limit == 100)
    }

    @Test func neighborhoodSendsRadiusAndPeriod() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/leaderboard_neighborhood", .json(#"{"total_participants":0,"entries":[]}"#))
        let weekly = LeaderboardQuery(regionID: "DE", period: .weekly, date: LocalDate(year: 2026, month: 10, day: 16))

        let entries = try await harness.backend.leaderboards.neighborhood(for: weekly, radius: 3)

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/leaderboard_neighborhood"))
        #expect(try request.jsonBody() == .object([
            "p_region_id": .string("DE"),
            "p_period": .string("weekly"),
            "p_date": .string("2026-10-16"),
            "p_radius": .number(3),
        ]))
        #expect(entries.isEmpty)
    }

    @Test(arguments: ["unknown_region", "region_not_allowed"])
    func unknownOrForeignRegionIsMapped(message: String) async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/leaderboard_page", .postgrestError(status: 400, code: "22023", message: message))

        await #expect(throws: LeaderboardError.unknownRegion) {
            try await harness.backend.leaderboards.page(for: query, offset: 0, limit: 50)
        }
    }
}
