import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Chat-RPCs (Migration 20261019100200): Parameter, Dekodierung, Fehler und das Löschen von Anhängen.
struct ChatRepositoryTests {
    private static let conversationID = UUID(uuidString: "dddddddd-0000-4000-8000-000000000001")!
    private static let peerID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!
    private static let messageID = UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000001")!
    private static let clientID = UUID(uuidString: "ffffffff-0000-4000-8000-000000000001")!

    private static let directJSON = #"""
    {"id":"dddddddd-0000-4000-8000-000000000001","kind":"direct","title":"Mia",
     "peer":{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":"bbbbbbbb-0000-4000-8000-000000000002/a.jpg"},
     "group_id":null,"group_image_path":null,"member_count":2,
     "last_message":{"kind":"text","text":"Hallo","sender_name":"Mia","is_own":false,"sent_at":"2026-10-19T09:00:00.123456+00:00"},
     "unread_count":3,"can_send":true,"updated_at":"2026-10-19T09:00:00.123456+00:00"}
    """#

    private static let groupJSON = #"""
    {"id":"dddddddd-0000-4000-8000-000000000002","kind":"group","title":"Laufgruppe","peer":null,
     "group_id":"cccccccc-0000-4000-8000-000000000001","group_image_path":"cccccccc-0000-4000-8000-000000000001/t.png",
     "member_count":5,"last_message":null,"unread_count":0,"can_send":true,"updated_at":"2026-10-18T09:00:00Z"}
    """#

    private static let messageJSON = #"""
    {"id":"eeeeeeee-0000-4000-8000-000000000001","conversation_id":"dddddddd-0000-4000-8000-000000000001",
     "client_id":"ffffffff-0000-4000-8000-000000000001",
     "sender":{"public_id":"9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f","username":"niklas","display_name":"Niklas","avatar_path":null},
     "is_own":true,"kind":"text","body":"Hallo Mia","media_path":null,"shared_profile":null,
     "created_at":"2026-10-19T09:01:02.654321+00:00"}
    """#

    @Test func conversationsAreDecoded() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_conversations", .json("[\(Self.directJSON),\(Self.groupJSON)]"))

        let conversations = try await harness.backend.chat.conversations()

        #expect(conversations.count == 2)
        let direct = try #require(conversations.first)
        #expect(direct.kind == .direct)
        #expect(direct.peer?.username == "mia")
        #expect(direct.image == MediaReference(bucket: .avatars, path: "bbbbbbbb-0000-4000-8000-000000000002/a.jpg"))
        #expect(direct.lastMessage?.text == "Hallo")
        #expect(direct.lastMessage?.isOwn == false)
        #expect(direct.unreadCount == 3)
        let group = try #require(conversations.last)
        #expect(group.kind == .group)
        #expect(group.peer == nil)
        #expect(group.image == MediaReference(bucket: .groupImages, path: "cccccccc-0000-4000-8000-000000000001/t.png"))
        #expect(group.memberCount == 5)
    }

    @Test func openDirectAndGroupConversation() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_open_direct", .json(Self.directJSON))
        harness.stub("POST", "/rest/v1/rpc/chat_group_conversation", .json(Self.groupJSON))
        let groupID = UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!

        let direct = try await harness.backend.chat.openDirectConversation(with: Self.peerID)
        let group = try await harness.backend.chat.groupConversation(for: groupID)

        #expect(direct.id == Self.conversationID)
        #expect(group.groupID == groupID)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_open_direct")?.jsonBody()
            == .object(["p_public_id": .string(Self.peerID.uuidString)]))
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_group_conversation")?.jsonBody()
            == .object(["p_group_id": .string(groupID.uuidString)]))
    }

    @Test func sendTextIsTrimmedAndCarriesTheClientID() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_send", .json(Self.messageJSON))

        let message = try await harness.backend.chat.send(.text("  Hallo Mia  ", clientID: Self.clientID), to: Self.conversationID)

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/chat_send"))
        #expect(try request.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString), "p_client_id": .string(Self.clientID.uuidString),
            "p_kind": .string("text"), "p_body": .string("Hallo Mia"),
        ]))
        #expect(message.id == Self.messageID)
        #expect(message.clientID == Self.clientID)
        #expect(message.isOwn)
        #expect(message.text == "Hallo Mia")
        #expect(message.sender?.username == "niklas")
    }

    @Test func sendImageAndProfile() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_send", .json(#"""
        {"id":"eeeeeeee-0000-4000-8000-000000000002","conversation_id":"dddddddd-0000-4000-8000-000000000001",
         "client_id":null,"sender":null,"is_own":false,"kind":"profile","body":null,"media_path":null,
         "shared_profile":{"public_id":"bbbbbbbb-0000-4000-8000-000000000002","username":"mia","display_name":"Mia","avatar_path":null},
         "created_at":"2026-10-19T09:01:02Z"}
        """#))
        let path = "dddddddd-0000-4000-8000-000000000001/foto.jpg"

        _ = try await harness.backend.chat.send(ChatMessageDraft(clientID: Self.clientID, kind: .image, mediaPath: path), to: Self.conversationID)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_send")?.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString), "p_client_id": .string(Self.clientID.uuidString),
            "p_kind": .string("image"), "p_media_path": .string(path),
        ]))

        let shared = try await harness.backend.chat.send(
            ChatMessageDraft(clientID: Self.clientID, kind: .profile, sharedProfileID: Self.peerID), to: Self.conversationID
        )
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_send")?.jsonBody()["p_shared_profile_id"] == .string(Self.peerID.uuidString))
        #expect(shared.sharedProfile?.username == "mia")
        #expect(shared.sender == nil)
    }

    @Test func invalidTextIsRejectedWithoutARequest() async {
        let harness = BackendTestHarness()

        await #expect(throws: SocialError.invalidMessage) {
            try await harness.backend.chat.send(.text("   "), to: Self.conversationID)
        }
        await #expect(throws: SocialError.invalidMessage) {
            try await harness.backend.chat.send(.text(String(repeating: "a", count: 2_001)), to: Self.conversationID)
        }
        #expect(harness.recorded.isEmpty)
    }

    @Test func messagesUseMicrosecondTimestampsAndClampTheLimit() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_messages", .json("[\(Self.messageJSON)]"))
        let before = Date(timeIntervalSince1970: 1_792_400_462.654321)

        let messages = try await harness.backend.chat.messages(in: Self.conversationID, before: before, limit: 500)

        let request = try #require(harness.lastRequest("POST", "/rest/v1/rpc/chat_messages"))
        #expect(try request.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString),
            "p_before": .string("2026-10-19T09:01:02.654321Z"), "p_limit": .number(100),
        ]))
        let sentAt = try #require(messages.first?.sentAt)
        #expect(abs(sentAt.timeIntervalSince(before)) < 0.000_001)

        _ = try await harness.backend.chat.messages(in: Self.conversationID, before: nil, limit: 40)
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_messages")?.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString), "p_limit": .number(40),
        ]))
    }

    @Test func markReadSendsTheTimestamp() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_mark_read", .json("null"))

        try await harness.backend.chat.markRead(Self.conversationID, through: Date(timeIntervalSince1970: 1_792_400_462.000001))

        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_mark_read")?.jsonBody() == .object([
            "p_conversation_id": .string(Self.conversationID.uuidString), "p_through": .string("2026-10-19T09:01:02.000001Z"),
        ]))
    }

    @Test func deletingAnImageMessageAlsoRemovesTheFile() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        let path = "dddddddd-0000-4000-8000-000000000001/foto.jpg"
        harness.stub("POST", "/rest/v1/rpc/chat_delete_message", .json(#"{"media_path":"\#(path)"}"#))
        harness.stub("DELETE", "/storage/v1/object/chat-media", .json(#"[{"name":"\#(path)"}]"#))

        try await harness.backend.chat.deleteMessage(Self.messageID)

        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/chat_delete_message")?.jsonBody()
            == .object(["p_message_id": .string(Self.messageID.uuidString)]))
        let remove = try #require(harness.lastRequest("DELETE", "/storage/v1/object/chat-media"))
        #expect(try remove.jsonBody() == .object(["prefixes": .array([.string(path)])]))
        #expect(remove.header("Authorization") == "Bearer \(BackendTestHarness.accessToken)")
        #expect(remove.header("apikey") == BackendTestHarness.publishableKey)
    }

    @Test func deletingATextMessageDoesNotTouchStorage() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_delete_message", .json(#"{"media_path":null}"#))

        try await harness.backend.chat.deleteMessage(Self.messageID)

        #expect(harness.requests("DELETE", pathPrefix: "/storage").isEmpty)
    }

    @Test func serverRulesAreMapped() async {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/chat_send", .postgrestError(status: 400, code: "P0001", message: "read_only"))
        harness.stub("POST", "/rest/v1/rpc/chat_open_direct", .postgrestError(status: 400, code: "P0001", message: "blocked"))
        harness.stub("POST", "/rest/v1/rpc/chat_conversations", .postgrestError(
            status: 404, code: "PGRST202", message: "Could not find the function public.chat_conversations without parameters"
        ))

        await #expect(throws: SocialError.readOnly) {
            try await harness.backend.chat.send(.text("Hallo"), to: Self.conversationID)
        }
        await #expect(throws: SocialError.blocked) {
            try await harness.backend.chat.openDirectConversation(with: Self.peerID)
        }
        await #expect(throws: SocialError.unavailable) {
            try await harness.backend.chat.conversations()
        }
    }

    /// Ohne erreichbaren Realtime-Server enden die Streams, statt ewig zu warten (die App fragt dann regelmäßig).
    @Test(.timeLimit(.minutes(1)))
    func eventStreamsEndWhenRealtimeIsUnreachable() async {
        let harness = BackendTestHarness()

        var messageEvents = 0
        for await _ in harness.backend.chat.messageEvents(in: Self.conversationID) {
            messageEvents += 1
        }
        var conversationEvents = 0
        // Ohne Sitzung ist die eigene öffentliche ID unbekannt: Der Stream endet sofort.
        for await _ in harness.backend.chat.conversationEvents() {
            conversationEvents += 1
        }

        #expect(messageEvents == 0)
        #expect(conversationEvents == 0)
    }
}
