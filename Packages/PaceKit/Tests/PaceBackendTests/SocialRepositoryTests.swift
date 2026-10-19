import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Social-RPCs: Parameternamen, Dekodierung und Fehler-Tokens (Vertrag in docs/SOCIAL.md).
struct SocialRepositoryTests {
    private static let friendID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!
    private static let groupID = UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!

    private static let groupJSON = #"""
    {"group_id":"cccccccc-0000-4000-8000-000000000001","name":"Klasse 8b","description":"Wir laufen!","kind":"class",
     "role":"owner","member_count":6,"daily_goal":8000,"next_daily_goal":9000,"time_zone":"Europe/Berlin",
     "group_today":"2026-10-16","invite_code":"K7M2Q9XA","current_streak":4,"best_streak":9,
     "today_reached_count":1,"today_required_count":2,"today_complete":false,
     "created_at":"2026-10-01T08:15:30.123456+00:00"}
    """#

    @Test func findProfileSendsTheUsernameAndDecodesTheRelationship() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/social_find_profile", .json(#"""
        {"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia",
         "relationship":"incoming_request","request_id":"dddddddd-0000-4000-8000-000000000001"}
        """#))

        let result = try #require(try await harness.backend.social.findProfile(username: "Mia"))

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_find_profile"))
        #expect(try request.jsonBody() == .object(["p_username": .string("Mia")]))
        #expect(result.profile == SocialProfile(publicID: Self.friendID, username: "mia", displayName: "Mia"))
        #expect(result.relationship == .incomingRequest)
        #expect(result.requestID != nil)
    }

    @Test func unknownUsernameIsNil() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_find_profile", .json("null"))

        #expect(try await harness.backend.social.findProfile(username: "niemand") == nil)
    }

    @Test func friendRequestOutcomesAndParameters() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_send_friend_request", .json(#"{"status":"accepted","request_id":null}"#))
        harness.stub("POST", "/rest/v1/rpc/social_respond_friend_request", .json(#"{"status":"declined"}"#))

        #expect(try await harness.backend.social.sendFriendRequest(to: Self.friendID) == .accepted)
        try await harness.backend.social.respondToFriendRequest(Self.groupID, accept: false)

        let send = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_send_friend_request"))
        #expect(try send.jsonBody() == .object(["p_public_id": .string(Self.friendID.uuidString)]))
        let respond = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_respond_friend_request"))
        #expect(try respond.jsonBody() == .object([
            "p_request_id": .string(Self.groupID.uuidString), "p_accept": .bool(false),
        ]))
    }

    @Test func friendsRequestsAndRankingAreDecoded() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_friends", .json(#"""
        [{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia",
          "friends_since":"2026-10-10T12:00:00+00:00"}]
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_friend_requests", .json(#"""
        [{"request_id":"dddddddd-0000-4000-8000-000000000001","direction":"outgoing",
          "public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia",
          "created_at":"2026-10-15T07:00:00Z"}]
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_friend_ranking", .json(#"""
        {"total_participants":2,"entries":[
          {"rank":2,"public_user_id":"bbbbbbbb-0000-4000-8000-000000000001","username":"niklas","display_name":"Niklas","competition_steps":8000,"is_current_user":true},
          {"rank":1,"public_user_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","competition_steps":9000,"is_current_user":false}]}
        """#))

        let friends = try await harness.backend.social.friends()
        let requests = try await harness.backend.social.friendRequests()
        let ranking = try await harness.backend.social.friendRanking(period: .daily, date: LocalDate(year: 2026, month: 10, day: 16))

        #expect(friends.map(\.profile.username) == ["mia"])
        #expect(requests.first?.direction == .outgoing)
        #expect(ranking.map(\.rank) == [1, 2])
        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_friend_ranking"))
        #expect(try request.jsonBody() == .object(["p_period": .string("daily"), "p_date": .string("2026-10-16")]))
    }

    @Test func groupSummaryIsDecoded() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_create_group", .json(Self.groupJSON))

        let group = try await harness.backend.social.createGroup(
            GroupDraft(
                name: "Klasse 8b", description: "Wir laufen!", kind: .schoolClass, dailyGoal: 8_000,
                privacy: .inviteOnly, inviteePublicIDs: [Self.friendID]
            ),
            timeZone: "Europe/Berlin"
        )

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_create_group"))
        #expect(try request.jsonBody() == .object([
            "p_name": .string("Klasse 8b"), "p_description": .string("Wir laufen!"), "p_kind": .string("class"),
            "p_daily_goal": .number(8_000), "p_time_zone": .string("Europe/Berlin"),
            "p_privacy": .string("invite_only"), "p_invitee_public_ids": .array([.string(Self.friendID.uuidString)]),
        ]))
        #expect(group.id == Self.groupID)
        #expect(group.kind == .schoolClass)
        #expect(group.isOwner)
        #expect(group.nextDailyGoal == 9_000)
        #expect(group.groupToday == LocalDate(year: 2026, month: 10, day: 16))
        #expect(group.todayRequiredCount == 2)
        #expect(group.currentStreak == 4)
    }

    @Test func groupRankingDaysAndInvitationsAreDecoded() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_group_ranking", .json(#"""
        {"total_participants":1,"group_today":"2026-10-16","daily_goal":8000,"entries":[
          {"rank":1,"public_user_id":"bbbbbbbb-0000-4000-8000-000000000001","username":"niklas","display_name":"Niklas",
           "competition_steps":8500,"is_current_user":true,"role":"owner","reached_goal_today":true}]}
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_group_days", .json(#"""
        [{"day":"2026-10-16","member_count":6,"required_count":2,"reached_count":1,"daily_goal":8000,"reached":false,"is_today":true}]
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_respond_group_invitation", .json(#"{"status":"accepted","group":\#(Self.groupJSON)}"#))

        let ranking = try await harness.backend.social.groupRanking(Self.groupID, period: .weekly)
        let days = try await harness.backend.social.groupDays(Self.groupID, count: 500)
        let joined = try await harness.backend.social.respondToInvitation(Self.groupID, accept: true)

        #expect(ranking.entries.first?.reachedGoalToday == true)
        #expect(ranking.entries.first?.role == .owner)
        #expect(days.first?.requiredCount == 2)
        #expect(joined?.name == "Klasse 8b")
        let daysRequest = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_group_days"))
        #expect(try daysRequest.jsonBody() == .object(["p_group_id": .string(Self.groupID.uuidString), "p_days": .number(60)]))
    }

    struct TokenCase: Sendable, CustomTestStringConvertible {
        let token: String
        let expected: SocialError
        var testDescription: String { token }
    }

    @Test(arguments: [
        TokenCase(token: "invalid_invite_code", expected: .invalidInviteCode),
        TokenCase(token: "rate_limited", expected: .rateLimited),
        TokenCase(token: "limit_reached", expected: .limitReached),
        TokenCase(token: "not_found", expected: .notFound),
        TokenCase(token: "not_allowed", expected: .notAllowed),
        TokenCase(token: "cooldown", expected: .cooldown),
        TokenCase(token: "self_request", expected: .selfRequest),
        TokenCase(token: "invalid_name", expected: .invalidName),
    ])
    func errorTokensAreMapped(_ testCase: TokenCase) async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_join_group", .postgrestError(status: 400, code: "P0001", message: testCase.token))

        await #expect(throws: testCase.expected) {
            try await harness.backend.social.joinGroup(inviteCode: "abcd-1234")
        }
    }

    @Test func missingMigrationIsReportedAsUnavailable() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_my_groups", .postgrestError(
            status: 404, code: "PGRST202", message: "Could not find the function public.social_my_groups without parameters in the schema cache"
        ))

        await #expect(throws: SocialError.unavailable) {
            try await harness.backend.social.myGroups()
        }
    }

    @Test func networkErrorsAreMapped() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_friends", .failure(URLError(.notConnectedToInternet)))

        await #expect(throws: SocialError.network) {
            try await harness.backend.social.friends()
        }
    }
}
