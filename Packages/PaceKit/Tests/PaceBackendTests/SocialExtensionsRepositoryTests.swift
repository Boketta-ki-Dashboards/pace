import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Präfixsuche, öffentliches Profil, Gruppendetails, Gruppenbild, Blockieren und Melden (Migrationen 20261019100000
/// und 20261019100100): Parameter, Dekodierung und Fehler.
struct SocialExtensionsRepositoryTests {
    private static let personID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!
    private static let groupID = UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!

    private static let groupJSON = #"""
    {"group_id":"cccccccc-0000-4000-8000-000000000001","name":"Abendrunde","description":"","kind":"work",
     "role":"owner","member_count":2,"daily_goal":9000,"next_daily_goal":null,"time_zone":"Europe/Berlin",
     "group_today":"2026-10-19","invite_code":"K7M2Q9XA","current_streak":3,"best_streak":5,
     "today_reached_count":1,"today_required_count":1,"today_complete":true,
     "created_at":"2026-10-01T08:15:30.123456+00:00",
     "image_path":"cccccccc-0000-4000-8000-000000000001/titel.jpg","privacy":"invite_only"}
    """#

    @Test func searchSendsTheTrimmedQueryAndDecodesAvatars() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_search_profiles", .json(#"""
        [{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia",
          "avatar_path":"bbbbbbbb-0000-4000-8000-000000000002/a.jpg","relationship":"friend","request_id":null}]
        """#))

        let results = try await harness.backend.social.searchProfiles(query: "  @mia ")

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_search_profiles"))
        #expect(try request.jsonBody() == .object(["p_query": .string("mia")]))
        #expect(results.map(\.relationship) == [.friend])
        #expect(results.first?.profile.avatar == MediaReference(bucket: .avatars, path: "bbbbbbbb-0000-4000-8000-000000000002/a.jpg"))
    }

    @Test func shortQueriesDoNotReachTheServer() async throws {
        let harness = BackendTestHarness()

        #expect(try await harness.backend.social.searchProfiles(query: "@mi").isEmpty)
        #expect(harness.recorded.isEmpty)
    }

    @Test func publicProfileOfAFriendAndOfAStranger() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_public_profile", .json(#"""
        {"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,
         "relationship":"friend","request_id":null,"friends_since":"2026-10-10T12:00:00+00:00","steps_today":7000,
         "steps_week":21000,"is_blocked_by_me":false}
        """#))

        let friend = try await harness.backend.social.publicProfile(Self.personID, date: LocalDate(year: 2026, month: 10, day: 19))

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_public_profile"))
        #expect(try request.jsonBody() == .object([
            "p_public_id": .string(Self.personID.uuidString), "p_date": .string("2026-10-19"),
        ]))
        #expect(friend.relationship == .friend)
        #expect(friend.stepsToday == 7_000)
        #expect(friend.stepsWeek == 21_000)
        #expect(friend.friendsSince != nil)
        #expect(!friend.isBlockedByMe)

        harness.stub("POST", "/rest/v1/rpc/social_public_profile", .json(#"""
        {"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,
         "relationship":"none","request_id":null,"friends_since":null,"steps_today":null,"steps_week":null,
         "is_blocked_by_me":true}
        """#))
        let stranger = try await harness.backend.social.publicProfile(Self.personID, date: LocalDate(year: 2026, month: 10, day: 19))
        #expect(stranger.relationship == .none)
        #expect(stranger.stepsToday == nil)
        #expect(stranger.friendsSince == nil)
        #expect(stranger.isBlockedByMe)
    }

    @Test func groupDetailsAndImage() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_update_group_details", .json(Self.groupJSON))
        harness.stub("POST", "/rest/v1/rpc/social_set_group_image", .json(Self.groupJSON))

        let updated = try await harness.backend.social.updateGroupDetails(
            Self.groupID, name: "Abendrunde", description: "", kind: .work, privacy: .inviteOnly
        )
        _ = try await harness.backend.social.setGroupImage(Self.groupID, path: nil)

        let details = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_update_group_details"))
        #expect(try details.jsonBody() == .object([
            "p_group_id": .string(Self.groupID.uuidString), "p_name": .string("Abendrunde"), "p_description": .string(""),
            "p_kind": .string("work"), "p_privacy": .string("invite_only"),
        ]))
        let image = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_set_group_image"))
        #expect(try image.jsonBody() == .object(["p_group_id": .string(Self.groupID.uuidString), "p_path": .null]))
        #expect(updated.privacy == .inviteOnly)
        #expect(updated.image == MediaReference(bucket: .groupImages, path: "cccccccc-0000-4000-8000-000000000001/titel.jpg"))
    }

    @Test func groupsWithoutTheNewFieldsUseTheCodeDefault() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_group", .json(#"""
        {"group_id":"cccccccc-0000-4000-8000-000000000001","name":"Alt","description":"","kind":"club","role":"member",
         "member_count":2,"daily_goal":9000,"next_daily_goal":null,"time_zone":"Europe/Berlin","group_today":"2026-10-19",
         "invite_code":"K7M2Q9XA","current_streak":0,"best_streak":0,"today_reached_count":0,"today_required_count":1,
         "today_complete":false,"created_at":"2026-10-01T08:15:30Z"}
        """#))

        let group = try await harness.backend.social.group(Self.groupID)

        #expect(group.privacy == .code)
        #expect(group.imagePath == nil)
    }

    @Test func createGroupFallsBackOnlyWhenTheOldFunctionGivesTheSameResult() async throws {
        let harness = BackendTestHarness()
        // Server ohne Migration 20261019100100: Die Fassung mit p_privacy fehlt, die alte gibt es.
        harness.stub("POST", "/rest/v1/rpc/social_create_group") { request in
            if (try? request.jsonBody())?["p_privacy"] != nil {
                return .postgrestError(status: 404, code: "PGRST202", message: "Could not find the function public.social_create_group")
            }
            return .json(Self.groupJSON)
        }

        _ = try await harness.backend.social.createGroup(GroupDraft(name: "Lauftreff", privacy: .code), timeZone: "Europe/Berlin")
        #expect(harness.requests("POST", pathPrefix: "/rest/v1/rpc/social_create_group").count == 2)
        let legacy = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_create_group"))
        #expect(try legacy.jsonBody().objectKeys == ["p_name", "p_description", "p_kind", "p_daily_goal", "p_time_zone"])

        await #expect(throws: SocialError.unavailable) {
            try await harness.backend.social.createGroup(GroupDraft(name: "Privat", privacy: .inviteOnly), timeZone: "Europe/Berlin")
        }
        await #expect(throws: SocialError.unavailable) {
            try await harness.backend.social.createGroup(
                GroupDraft(name: "Mit Einladung", privacy: .code, inviteePublicIDs: [Self.personID]), timeZone: "Europe/Berlin"
            )
        }
        #expect(harness.requests("POST", pathPrefix: "/rest/v1/rpc/social_create_group").count == 4)
    }

    @Test func blockUnblockAndBlockedUsers() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_block_user", .json("null"))
        harness.stub("POST", "/rest/v1/rpc/social_unblock_user", .json("null"))
        harness.stub("POST", "/rest/v1/rpc/social_blocked_users", .json(#"""
        [{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,
          "blocked_at":"2026-10-19T10:00:00Z"}]
        """#))

        try await harness.backend.social.block(Self.personID)
        try await harness.backend.social.unblock(Self.personID)
        let blocked = try await harness.backend.social.blockedUsers()

        for function in ["social_block_user", "social_unblock_user"] {
            let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/\(function)"))
            #expect(try request.jsonBody() == .object(["p_public_id": .string(Self.personID.uuidString)]))
        }
        #expect(blocked == [SocialProfile(publicID: Self.personID, username: "mia", displayName: "Mia")])
    }

    @Test func reportsSendTargetReasonAndTrimmedDetails() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_report", .json("null"))
        let messageID = UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000001")!

        try await harness.backend.social.report(.user(publicID: Self.personID), reason: .impersonation, details: "  Fake  ")
        let user = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_report"))
        #expect(try user.jsonBody() == .object([
            "p_target_type": .string("user"), "p_target_id": .string(Self.personID.uuidString),
            "p_reason": .string("impersonation"), "p_details": .string("Fake"),
        ]))

        try await harness.backend.social.report(.message(id: messageID), reason: .spam, details: "   ")
        let message = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_report"))
        #expect(try message.jsonBody() == .object([
            "p_target_type": .string("message"), "p_target_id": .string(messageID.uuidString), "p_reason": .string("spam"),
        ]))

        try await harness.backend.social.report(.group(id: Self.groupID), reason: .other, details: nil)
        let group = try #require(harness.lastRequest("POST", "/rest/v1/rpc/social_report"))
        #expect(try group.jsonBody()["p_target_type"] == .string("group"))
    }

    struct TokenCase: Sendable, CustomTestStringConvertible {
        let token: String
        let expected: SocialError
        var testDescription: String { token }
    }

    @Test(arguments: [
        TokenCase(token: "blocked", expected: .blocked),
        TokenCase(token: "read_only", expected: .readOnly),
        TokenCase(token: "invalid_message", expected: .invalidMessage),
        TokenCase(token: "invalid_input", expected: .invalidInput),
        TokenCase(token: "invalid_privacy", expected: .invalidInput),
        TokenCase(token: "invalid_image_path", expected: .invalidInput),
    ])
    func newErrorTokensAreMapped(_ testCase: TokenCase) async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_block_user", .postgrestError(status: 400, code: "P0001", message: testCase.token))

        await #expect(throws: testCase.expected) {
            try await harness.backend.social.block(Self.personID)
        }
    }
}
