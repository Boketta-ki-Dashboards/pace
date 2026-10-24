import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Spitznamen, Nachrichtenaktionen, Sprachnachrichten und Gruppenkalender (Migrationen 20261023100000–100200):
/// Request-Körper, Dekodierung (auch ohne die neuen Felder älterer Server) und Fehler-Tokens.
struct MessageActionsNicknameCalendarTests {
    private static let conversationID = UUID(uuidString: "dddddddd-0000-4000-8000-000000000001")!
    private static let messageID = UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000001")!
    private static let replyID = UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000009")!
    private static let clientID = UUID(uuidString: "ffffffff-0000-4000-8000-000000000001")!
    private static let friendID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!
    private static let groupID = UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!

    private static let voiceMessageJSON = #"""
    {"id":"eeeeeeee-0000-4000-8000-000000000001","conversation_id":"dddddddd-0000-4000-8000-000000000001",
     "client_id":"ffffffff-0000-4000-8000-000000000001",
     "sender":{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,"nickname":"Mimi"},
     "is_own":false,"kind":"voice","body":null,"media_path":"dddddddd-0000-4000-8000-000000000001/a.m4a",
     "media_duration_ms":18400,"shared_profile":null,
     "reply_to":{"id":"eeeeeeee-0000-4000-8000-000000000009",
                 "sender":{"public_id":"9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f","username":"niklas","display_name":"Niklas","avatar_path":null,"nickname":null},
                 "kind":"text","text":"Wann treffen wir uns?","media_duration_ms":null,"is_deleted":false},
     "edited_at":null,"is_favorite":true,"is_pinned":true,
     "created_at":"2026-10-23T09:01:02.654321+00:00"}
    """#

    private static let editedTextJSON = #"""
    {"id":"eeeeeeee-0000-4000-8000-000000000001","conversation_id":"dddddddd-0000-4000-8000-000000000001",
     "client_id":"ffffffff-0000-4000-8000-000000000001",
     "sender":{"public_id":"9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f","username":"niklas","display_name":"Niklas","avatar_path":null,"nickname":null},
     "is_own":true,"kind":"text","body":"Bis später","media_path":null,"media_duration_ms":null,"shared_profile":null,
     "reply_to":{"id":"eeeeeeee-0000-4000-8000-000000000009","sender":null,"kind":"image","text":null,"media_duration_ms":null,"is_deleted":true},
     "edited_at":"2026-10-23T09:05:00.000001+00:00","is_favorite":false,"is_pinned":false,
     "created_at":"2026-10-23T09:01:02Z"}
    """#

    // MARK: Spitznamen

    @Test func profilesRankingsAndInvitationsCarryTheOwnNickname() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_friends", .json(#"""
        [{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,
          "nickname":"Mimi","friends_since":"2026-10-01T10:00:00Z"},
         {"public_id":"bbbbbbbb-0000-4000-8000-000000000003","username":"leon","display_name":"Leon","avatar_path":null,
          "friends_since":"2026-10-02T10:00:00Z"}]
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_friend_ranking", .json(#"""
        {"total_participants":1,"entries":[{"rank":1,"public_user_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia",
          "display_name":"Mia","competition_steps":9000,"is_current_user":false,"avatar_path":null,"nickname":"Mimi"}]}
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_group_ranking", .json(#"""
        {"total_participants":1,"group_today":"2026-10-23","daily_goal":8000,"entries":[{"rank":1,
          "public_user_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","competition_steps":9000,
          "is_current_user":false,"role":"member","reached_goal_today":true,"avatar_path":null,"nickname":"Mimi"}]}
        """#))
        harness.stub("POST", "/rest/v1/rpc/social_group_invitations", .json(#"""
        [{"invitation_id":"aaaaaaaa-0000-4000-8000-000000000001","group_id":"cccccccc-0000-4000-8000-000000000001",
          "group_name":"Abendrunde","group_kind":"friends","group_image_path":null,"group_privacy":"code","member_count":3,
          "inviter_public_id":"bbbbbbbb-0000-4000-8000-000000000002","inviter_username":"mia","inviter_display_name":"Mia",
          "inviter_avatar_path":null,"inviter_nickname":"Mimi","created_at":"2026-10-23T08:00:00Z"}]
        """#))

        let friends = try await harness.backend.social.friends()
        #expect(friends.map(\.profile.shownName) == ["Mimi", "Leon"])
        #expect(friends.map(\.profile.nickname) == ["Mimi", nil])
        #expect(friends.first?.profile.displayName == "Mia")
        let ranking = try await harness.backend.social.friendRanking(period: .daily, date: LocalDate(year: 2026, month: 10, day: 23))
        #expect(ranking.first?.nickname == "Mimi")
        #expect(ranking.first?.shownName == "Mimi")
        let groupRanking = try await harness.backend.social.groupRanking(Self.groupID, period: .daily)
        #expect(groupRanking.entries.first?.profile.shownName == "Mimi")
        let invitation = try #require(try await harness.backend.social.groupInvitations().first)
        #expect(invitation.inviterNickname == "Mimi")
        #expect(invitation.inviterShownName == "Mimi")
        #expect(invitation.inviterDisplayName == "Mia")
    }

    @Test func setFriendNicknameNormalisesAndSendsNullToRemove() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_set_friend_nickname", respond: { request in
            let nickname = (try? request.jsonBody()["p_nickname"]).flatMap { value -> String? in
                if case .string(let text) = value { return text }
                return nil
            }
            let field = nickname.map { "\"\($0)\"" } ?? "null"
            return .json(#"{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,"nickname":\#(field)}"#)
        })

        let named = try await harness.backend.social.setFriendNickname(publicID: Self.friendID, nickname: "  Die   Mia ")
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/social_set_friend_nickname")?.jsonBody() == .object([
            "p_public_id": .string(Self.friendID.uuidString), "p_nickname": .string("Die Mia"),
        ]))
        #expect(named.nickname == "Die Mia")
        #expect(named.shownName == "Die Mia")

        let removed = try await harness.backend.social.setFriendNickname(publicID: Self.friendID, nickname: "   ")
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/social_set_friend_nickname")?.jsonBody() == .object([
            "p_public_id": .string(Self.friendID.uuidString), "p_nickname": .null,
        ]))
        #expect(removed.nickname == nil)
        #expect(removed.shownName == "Mia")

        _ = try await harness.backend.social.setFriendNickname(publicID: Self.friendID, nickname: nil)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/social_set_friend_nickname")?.jsonBody()["p_nickname"] == .null)
    }

    @Test func tooLongNicknamesAreRejectedWithoutARequest() async {
        let harness = BackendTestHarness()

        await #expect(throws: SocialError.invalidNickname) {
            try await harness.backend.social.setFriendNickname(publicID: Self.friendID, nickname: String(repeating: "x", count: 31))
        }
        #expect(harness.recorded.isEmpty)
    }

    @Test func profilesFromOlderServersHaveNoNickname() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_blocked_users", .json(#"""
        [{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,"blocked_at":"2026-10-01T10:00:00Z"}]
        """#))

        let blocked = try await harness.backend.social.blockedUsers()
        #expect(blocked.first?.nickname == nil)
        #expect(blocked.first?.shownName == "Mia")
    }

    // MARK: Nachrichten

    @Test func messagesDecodeReplyDurationEditFavoriteAndPin() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_messages", .json("[\(Self.voiceMessageJSON),\(Self.editedTextJSON)]"))

        let messages = try await harness.backend.chat.messages(in: Self.conversationID, before: nil, limit: 40)

        let voice = try #require(messages.first)
        #expect(voice.kind == .voice)
        #expect(voice.media == MediaReference(bucket: .chatMedia, path: "dddddddd-0000-4000-8000-000000000001/a.m4a"))
        #expect(voice.mediaDuration == .milliseconds(18_400))
        #expect(voice.sender?.shownName == "Mimi")
        #expect(voice.isFavorite)
        #expect(voice.isPinned)
        #expect(!voice.isEdited)
        #expect(!voice.canEdit)
        let reply = try #require(voice.replyPreview)
        #expect(reply.id == Self.replyID)
        #expect(reply.kind == .text)
        #expect(reply.text == "Wann treffen wir uns?")
        #expect(reply.sender?.username == "niklas")
        #expect(!reply.isDeleted)

        let edited = try #require(messages.last)
        #expect(edited.isEdited)
        #expect(edited.canEdit)
        #expect(edited.editedAt.map { abs($0.timeIntervalSince1970 - 1_792_746_300.000001) < 0.000_01 } == true)
        #expect(edited.replyPreview?.isDeleted == true)
        #expect(edited.replyPreview?.sender == nil)
        #expect(edited.replyPreview?.kind == .image)
    }

    @Test func messagesFromOlderServersUseDefaults() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_messages", .json(#"""
        [{"id":"eeeeeeee-0000-4000-8000-000000000001","conversation_id":"dddddddd-0000-4000-8000-000000000001","client_id":null,
          "sender":null,"is_own":false,"kind":"text","body":"Hallo","media_path":null,"shared_profile":null,
          "created_at":"2026-10-19T09:01:02Z"}]
        """#))
        harness.stub("POST", "/rest/v1/rpc/chat_conversations", .json(#"""
        [{"id":"dddddddd-0000-4000-8000-000000000001","kind":"direct","title":"Mia",
          "peer":{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null},
          "group_id":null,"group_image_path":null,"member_count":2,
          "last_message":{"kind":"text","text":"Hallo","sender_name":"Mia","is_own":false,"sent_at":"2026-10-19T09:00:00Z"},
          "unread_count":0,"can_send":true,"updated_at":"2026-10-19T09:00:00Z"}]
        """#))

        let message = try #require(try await harness.backend.chat.messages(in: Self.conversationID, before: nil, limit: 40).first)
        #expect(message.replyPreview == nil)
        #expect(message.editedAt == nil)
        #expect(message.mediaDuration == nil)
        #expect(!message.isFavorite)
        #expect(!message.isPinned)
        let conversation = try #require(try await harness.backend.chat.conversations().first)
        #expect(!conversation.canPin)
        #expect(conversation.shownTitle == "Mia")
        #expect(conversation.lastMessage?.senderNickname == nil)
        #expect(conversation.lastMessage?.shownSenderName == "Mia")
    }

    @Test func conversationsCarryCanPinNicknameAndVoiceDuration() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_conversations", .json(#"""
        [{"id":"dddddddd-0000-4000-8000-000000000001","kind":"direct","title":"Mia",
          "peer":{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,"nickname":"Mimi"},
          "group_id":null,"group_image_path":null,"member_count":2,
          "last_message":{"kind":"voice","text":null,"sender_name":"Mia","sender_nickname":"Mimi","media_duration_ms":18000,
                          "is_own":false,"sent_at":"2026-10-23T09:00:00Z"},
          "unread_count":1,"can_send":true,"can_pin":true,"updated_at":"2026-10-23T09:00:00Z"}]
        """#))

        let conversation = try #require(try await harness.backend.chat.conversations().first)
        #expect(conversation.canPin)
        #expect(conversation.title == "Mia")
        #expect(conversation.shownTitle == "Mimi")
        #expect(conversation.lastMessage?.kind == .voice)
        #expect(conversation.lastMessage?.mediaDuration == .seconds(18))
        #expect(conversation.lastMessage?.shownSenderName == "Mimi")
    }

    @Test func sendingAReplyAndAVoiceMessage() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_send", .json(Self.voiceMessageJSON))
        let path = "dddddddd-0000-4000-8000-000000000001/a.m4a"

        _ = try await harness.backend.chat.send(.text("Ja!", clientID: Self.clientID, replyTo: Self.replyID), to: Self.conversationID)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_send")?.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString), "p_client_id": .string(Self.clientID.uuidString),
            "p_kind": .string("text"), "p_body": .string("Ja!"), "p_reply_to_id": .string(Self.replyID.uuidString),
        ]))

        let voice = try await harness.backend.chat.send(
            .voice(mediaPath: path, duration: .milliseconds(18_400), clientID: Self.clientID), to: Self.conversationID
        )
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_send")?.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString), "p_client_id": .string(Self.clientID.uuidString),
            "p_kind": .string("voice"), "p_media_path": .string(path), "p_media_duration_ms": .number(18_400),
        ]))
        #expect(voice.kind == .voice)
    }

    @Test func invalidVoiceMessagesAreRejectedWithoutARequest() async {
        let harness = BackendTestHarness()
        let path = "dddddddd-0000-4000-8000-000000000001/a.m4a"

        await #expect(throws: SocialError.invalidInput) {
            try await harness.backend.chat.send(.voice(mediaPath: path, duration: .seconds(301)), to: Self.conversationID)
        }
        await #expect(throws: SocialError.invalidInput) {
            try await harness.backend.chat.send(.voice(mediaPath: path, duration: .zero), to: Self.conversationID)
        }
        await #expect(throws: SocialError.invalidInput) {
            try await harness.backend.chat.send(ChatMessageDraft(kind: .voice, mediaDuration: .seconds(3)), to: Self.conversationID)
        }
        #expect(harness.recorded.isEmpty)
    }

    @Test func editFavoriteAndPinRequests() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_edit_message", .json(Self.editedTextJSON))
        harness.stub("POST", "/rest/v1/rpc/chat_set_favorite", .json("null"))
        harness.stub("POST", "/rest/v1/rpc/chat_favorites", .json("[\(Self.voiceMessageJSON)]"))
        let pinsJSON = #"""
        [{"message":\#(Self.voiceMessageJSON),
          "pinned_by":{"public_id":"9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f","username":"niklas","display_name":"Niklas","avatar_path":null,"nickname":null},
          "pinned_at":"2026-10-23T09:10:00.5+00:00"}]
        """#
        harness.stub("POST", "/rest/v1/rpc/chat_set_pinned", .json(pinsJSON))
        harness.stub("POST", "/rest/v1/rpc/chat_pins", .json(pinsJSON))

        let edited = try await harness.backend.chat.editMessage(Self.messageID, text: "  Bis später ")
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_edit_message")?.jsonBody() == .object([
            "p_message_id": .string(Self.messageID.uuidString), "p_text": .string("Bis später"),
        ]))
        #expect(edited.isEdited)

        try await harness.backend.chat.setFavorite(Self.messageID, isFavorite: true)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_set_favorite")?.jsonBody() == .object([
            "p_message_id": .string(Self.messageID.uuidString), "p_favorite": .bool(true),
        ]))
        try await harness.backend.chat.setFavorite(Self.messageID, isFavorite: false)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_set_favorite")?.jsonBody()["p_favorite"] == .bool(false))

        let favorites = try await harness.backend.chat.favorites(conversationID: Self.conversationID)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_favorites")?.jsonBody()
            == .object(["p_conversation_id": .string(Self.conversationID.uuidString)]))
        #expect(favorites.map(\.id) == [Self.messageID])

        let pins = try await harness.backend.chat.setPinned(Self.messageID, isPinned: true)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_set_pinned")?.jsonBody() == .object([
            "p_message_id": .string(Self.messageID.uuidString), "p_pinned": .bool(true),
        ]))
        let pin = try #require(pins.first)
        #expect(pin.id == Self.messageID)
        #expect(pin.message.kind == .voice)
        #expect(pin.pinnedBy?.username == "niklas")
        #expect(abs(pin.pinnedAt.timeIntervalSince1970 - 1_792_746_600.5) < 0.001)
        #expect(try await harness.backend.chat.pins(conversationID: Self.conversationID) == pins)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_pins")?.jsonBody()
            == .object(["p_conversation_id": .string(Self.conversationID.uuidString)]))
    }

    /// Verborgene Pins (gelöscht bzw. Absender blockiert) bekommt nur, wer anpinnen darf – als Platzhalter zum Lösen.
    @Test func hiddenPinsDecodeAsPlaceholders() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_pins", .json(#"""
        [{"message":\#(Self.voiceMessageJSON),"pinned_by":null,"pinned_at":"2026-10-23T09:11:00Z"},
         {"message":{"id":"eeeeeeee-0000-4000-8000-000000000009","conversation_id":"dddddddd-0000-4000-8000-000000000001",
                     "client_id":null,"sender":null,"is_own":false,"kind":"image","body":null,"media_path":null,
                     "media_duration_ms":null,"shared_profile":null,"reply_to":null,"edited_at":null,"is_favorite":false,
                     "is_pinned":true,"created_at":"2026-10-23T08:00:00Z","is_deleted":true},
          "pinned_by":null,"pinned_at":"2026-10-23T09:10:00Z"}]
        """#))

        let pins = try await harness.backend.chat.pins(conversationID: Self.conversationID)

        #expect(pins.map(\.isHidden) == [false, true])
        let hidden = try #require(pins.last)
        #expect(hidden.id == Self.replyID)
        #expect(hidden.message.conversationID == Self.conversationID)
        #expect(hidden.message.kind == .image)
        #expect(hidden.message.sender == nil)
        #expect(hidden.message.text == nil)
        #expect(hidden.message.media == nil)
        #expect(hidden.pinnedBy == nil)
    }

    @Test func invalidEditTextIsRejectedWithoutARequest() async {
        let harness = BackendTestHarness()

        await #expect(throws: SocialError.invalidMessage) {
            try await harness.backend.chat.editMessage(Self.messageID, text: "  ")
        }
        #expect(harness.recorded.isEmpty)
    }

    struct TokenCase: Sendable, CustomTestStringConvertible {
        let function: String
        let token: String
        let error: SocialError
        var testDescription: String { "\(function): \(token)" }
    }

    @Test(arguments: [
        TokenCase(function: "chat_set_pinned", token: "pin_limit_reached", error: .pinLimitReached),
        TokenCase(function: "chat_set_pinned", token: "not_allowed", error: .notAllowed),
        TokenCase(function: "chat_set_pinned", token: "read_only", error: .readOnly),
        TokenCase(function: "chat_set_pinned", token: "not_found", error: .notFound),
    ])
    func pinErrorTokensAreMapped(_ testCase: TokenCase) async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/\(testCase.function)", .postgrestError(status: 400, code: "P0001", message: testCase.token))

        await #expect(throws: testCase.error) {
            try await harness.backend.chat.setPinned(Self.messageID, isPinned: true)
        }
    }

    @Test(arguments: [
        TokenCase(function: "chat_set_favorite", token: "favorite_limit_reached", error: .favoriteLimitReached),
        TokenCase(function: "chat_set_favorite", token: "limit_reached", error: .limitReached),
        TokenCase(function: "chat_set_favorite", token: "rate_limited", error: .rateLimited),
        TokenCase(function: "chat_set_favorite", token: "not_found", error: .notFound),
    ])
    func favoriteErrorTokensAreMapped(_ testCase: TokenCase) async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/\(testCase.function)", .postgrestError(status: 400, code: "P0001", message: testCase.token))

        await #expect(throws: testCase.error) {
            try await harness.backend.chat.setFavorite(Self.messageID, isFavorite: true)
        }
    }

    @Test func nicknameAndEditErrorsAreMapped() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_set_friend_nickname", .postgrestError(status: 400, code: "P0001", message: "invalid_nickname"))
        harness.stub("POST", "/rest/v1/rpc/chat_edit_message", .postgrestError(status: 400, code: "P0001", message: "read_only"))
        harness.stub("POST", "/rest/v1/rpc/chat_favorites", .postgrestError(
            status: 404, code: "PGRST202", message: "Could not find the function public.chat_favorites(p_conversation_id)"
        ))

        await #expect(throws: SocialError.invalidNickname) {
            try await harness.backend.social.setFriendNickname(publicID: Self.friendID, nickname: "Mi\u{200B}a")
        }
        await #expect(throws: SocialError.readOnly) {
            try await harness.backend.chat.editMessage(Self.messageID, text: "Neu")
        }
        await #expect(throws: SocialError.unavailable) {
            try await harness.backend.chat.favorites(conversationID: Self.conversationID)
        }
    }

    /// Ohne erreichbaren Realtime-Server endet auch der Stream mit Ereignisarten sofort.
    @Test(.timeLimit(.minutes(1)))
    func activityStreamEndsWhenRealtimeIsUnreachable() async {
        let harness = BackendTestHarness()

        var events: [ChatConversationEvent] = []
        for await event in harness.backend.chat.conversationActivity(in: Self.conversationID) {
            events.append(event)
        }

        #expect(events.isEmpty)
    }

    // MARK: Sprachnachrichten-Upload

    @Test func voiceUploadsGoIntoTheConversationFolderAsM4A() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", pathPrefix: "/storage/v1/object/", .json(#"{"Key":"k","Id":"5d8f6a0e-0000-4000-8000-000000000001"}"#))

        let voice = try await harness.backend.media.upload(Data([1, 2]), contentType: MediaRules.voiceContentType, to: .chat(conversationID: Self.conversationID))
        let aac = try await harness.backend.media.upload(Data([1]), contentType: "audio/aac", to: .chat(conversationID: Self.conversationID))

        #expect(voice.bucket == .chatMedia)
        #expect(voice.path.range(of: #"^dddddddd-0000-4000-8000-000000000001/[0-9a-f-]{36}\.m4a$"#, options: .regularExpression) != nil)
        #expect(aac.path.hasSuffix(".aac"))
        let upload = try #require(harness.requests("POST", pathPrefix: "/storage/v1/object/chat-media/").first)
        #expect(String(decoding: try #require(upload.body), as: UTF8.self).contains("audio/mp4"))
    }

    @Test func audioIsOnlyAllowedForChats() async {
        let harness = BackendTestHarness()

        await #expect(throws: MediaError.unsupportedType) {
            try await harness.backend.media.upload(Data([1]), contentType: "audio/mp4", to: .groupImage(groupID: Self.groupID))
        }
        await #expect(throws: MediaError.unsupportedType) {
            try await harness.backend.media.upload(Data([1]), contentType: "audio/mpeg", to: .chat(conversationID: Self.conversationID))
        }
        #expect(harness.recorded.isEmpty)
    }

    // MARK: Gruppenkalender

    @Test func groupCalendarRequestAndDecoding() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_group_calendar", .json(#"""
        {"group_id":"cccccccc-0000-4000-8000-000000000001","time_zone":"Europe/Berlin","group_today":"2026-10-23",
         "first_group_day":"2026-10-13",
         "days":[
          {"day":"2026-10-23","daily_goal":8000,"member_count":3,"required_count":1,"reached_count":1,"secured":true,
           "has_data":true,"is_today":true,"ranking":[
             {"public_id":"bbbbbbbb-0000-4000-8000-000000000003","username":"leon","display_name":"Leon","avatar_path":null,
              "nickname":null,"rank":2,"competition_steps":0,"reached":false,"is_current_user":true},
             {"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null,
              "nickname":"Mimi","rank":1,"competition_steps":9000,"reached":true,"is_current_user":false}]},
          {"day":"2026-10-22","daily_goal":8000,"member_count":1,"required_count":1,"reached_count":0,"secured":false,
           "has_data":false,"is_today":false,"ranking":[
             {"public_id":null,"username":null,"display_name":null,"avatar_path":null,"nickname":null,
              "rank":1,"competition_steps":0,"reached":false,"is_current_user":false}]}
         ]}
        """#))
        let from = LocalDate(year: 2026, month: 9, day: 28)
        let to = LocalDate(year: 2026, month: 11, day: 8)

        let calendar = try await harness.backend.social.groupCalendar(groupID: Self.groupID, from: from, to: to)

        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/social_group_calendar")?.jsonBody() == .object([
            "p_group_id": .string(Self.groupID.uuidString), "p_first_day": .string("2026-09-28"), "p_last_day": .string("2026-11-08"),
        ]))
        #expect(calendar.groupToday == LocalDate(year: 2026, month: 10, day: 23))
        #expect(calendar.firstGroupDay == LocalDate(year: 2026, month: 10, day: 13))
        #expect(calendar.days.map(\.day) == [LocalDate(year: 2026, month: 10, day: 22), LocalDate(year: 2026, month: 10, day: 23)])
        let today = try #require(calendar.day(LocalDate(year: 2026, month: 10, day: 23)))
        #expect(today.ranking.map(\.rank) == [1, 2])
        #expect(today.best?.profile?.shownName == "Mimi")
        #expect(today.currentUserEntry?.profile?.username == "leon")
        #expect(today.secured && today.isToday && today.hasData)
        // Ehemaliges Mitglied, das mich blockiert hat: Zeile ohne Profil.
        let hidden = try #require(calendar.day(LocalDate(year: 2026, month: 10, day: 22))?.ranking.first)
        #expect(hidden.profile == nil)
        #expect(hidden.isHidden)
        #expect(hidden.id == 1)
        #expect(today.ranking.map(\.isHidden) == [false, false])
        #expect(calendar.state(of: LocalDate(year: 2026, month: 10, day: 23)) == .secured)
        #expect(calendar.state(of: LocalDate(year: 2026, month: 10, day: 22)) == .noData)
        #expect(calendar.state(of: LocalDate(year: 2026, month: 10, day: 12)) == .beforeGroup)
        #expect(calendar.state(of: LocalDate(year: 2026, month: 10, day: 24)) == .future)
        #expect(calendar.state(of: LocalDate(year: 2026, month: 10, day: 20)) == .notLoaded)
    }

    /// 1. September bis 13. Oktober sind 43 Tage – einer zu viel.
    @Test func groupCalendarRangesAreCheckedBeforeTheRequest() async {
        let harness = BackendTestHarness()

        await #expect(throws: SocialError.invalidInput) {
            try await harness.backend.social.groupCalendar(
                groupID: Self.groupID, from: LocalDate(year: 2026, month: 9, day: 1), to: LocalDate(year: 2026, month: 10, day: 13)
            )
        }
        await #expect(throws: SocialError.invalidInput) {
            try await harness.backend.social.groupCalendar(
                groupID: Self.groupID, from: LocalDate(year: 2026, month: 10, day: 2), to: LocalDate(year: 2026, month: 10, day: 1)
            )
        }
        #expect(harness.recorded.isEmpty)
    }

    @Test func groupCalendarDateErrorsAreMapped() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/social_group_calendar", .postgrestError(status: 400, code: "P0001", message: "not_found"))

        await #expect(throws: SocialError.notFound) {
            try await harness.backend.social.groupCalendar(
                groupID: Self.groupID, from: LocalDate(year: 2026, month: 10, day: 1), to: LocalDate(year: 2026, month: 10, day: 31)
            )
        }
    }
}
