import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Verträge für Spitznamen, Nachrichtenaktionen, Sprachnachrichten und Gruppenkalender (Auftrag 3).
struct NicknameRulesTests {
    @Test func normalisesAndTreatsEmptyAsRemoval() {
        #expect(NicknameRules.storedValue("  Die   Mia \n") == "Die Mia")
        #expect(NicknameRules.storedValue("   ") == nil)
        #expect(NicknameRules.storedValue("") == nil)
        #expect(NicknameRules.violation(for: "   ") == nil)
    }

    @Test func sameLimitsAsDisplayNames() {
        #expect(NicknameRules.maxLength == 30)
        #expect(NicknameRules.violation(for: String(repeating: "ä", count: 30)) == nil)
        #expect(NicknameRules.violation(for: String(repeating: "x", count: 31)) == .tooLong)
        #expect(NicknameRules.violation(for: "Mi\u{0007}a") == .invalidCharacters)
    }

    @Test func shownNamePrefersTheOwnNickname() {
        let mia = SocialProfile(publicID: UUID(), username: "mia", displayName: "Mia")
        #expect(mia.shownName == "Mia")
        #expect(mia.withNickname("Mimi").shownName == "Mimi")
        #expect(mia.withNickname("Mimi").displayName == "Mia")
        #expect(mia.withNickname("").shownName == "Mia")
        #expect(mia.withNickname(nil) == mia)

        let entry = LeaderboardEntry(rank: 1, publicUserID: UUID(), username: "mia", displayName: "Mia", competitionSteps: 1, isCurrentUser: false, nickname: "Mimi")
        #expect(entry.shownName == "Mimi")
        let invitation = GroupInvitation(
            id: UUID(), groupID: UUID(), groupName: "Runde", groupKind: .friends, memberCount: 2, inviterUsername: "mia",
            inviterDisplayName: "Mia", createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(invitation.inviterShownName == "Mia")
    }
}

struct ChatContractTests {
    private let conversationID = UUID()

    @Test func voiceDurationsAreValidatedLikeTheServer() {
        #expect(ChatRules.milliseconds(of: .seconds(18)) == 18_000)
        #expect(ChatRules.milliseconds(of: .milliseconds(1_234)) == 1_234)
        #expect(ChatRules.validVoiceMilliseconds(.seconds(300)) == 300_000)
        #expect(ChatRules.validVoiceMilliseconds(.milliseconds(300_001)) == nil)
        #expect(ChatRules.validVoiceMilliseconds(.zero) == nil)
        #expect(ChatRules.validVoiceMilliseconds(.milliseconds(1)) == 1)
        #expect(ChatRules.maximumPinnedMessages == 5)
    }

    @Test func draftsCarryReplyAndDuration() {
        let reply = UUID()
        let text = ChatMessageDraft.text("Ja", replyTo: reply)
        #expect(text.kind == .text)
        #expect(text.replyToID == reply)
        #expect(text.mediaDuration == nil)
        let voice = ChatMessageDraft.voice(mediaPath: "c/a.m4a", duration: .seconds(3))
        #expect(voice.kind == .voice)
        #expect(voice.mediaPath == "c/a.m4a")
        #expect(voice.mediaDuration == .seconds(3))
        #expect(voice.text == nil)
        #expect(ChatMessageDraft.text("Hallo").replyToID == nil)
    }

    @Test func messageHelpers() {
        let own = ChatFixtures.message(in: conversationID, from: nil, isOwn: true, text: "Hi", at: Date(timeIntervalSince1970: 0))
        #expect(own.canEdit)
        #expect(!own.isEdited)
        #expect(!own.isFavorite && !own.isPinned)
        #expect(own.withFavorite(true).isFavorite)
        #expect(own.withPinned(true).isPinned)
        #expect(own.withFavorite(true).withFavorite(false) == own)
        let foreign = ChatFixtures.message(in: conversationID, from: ChatFixtures.mia, text: "Hi", at: Date(timeIntervalSince1970: 0))
        #expect(!foreign.canEdit)
        let ownVoice = ChatFixtures.message(in: conversationID, from: nil, isOwn: true, kind: .voice, at: Date(timeIntervalSince1970: 0))
        #expect(!ownVoice.canEdit)
        let edited = ChatFixtures.message(in: conversationID, from: nil, isOwn: true, text: "Hi", at: Date(timeIntervalSince1970: 0),
                                          editedAt: Date(timeIntervalSince1970: 60))
        #expect(edited.isEdited)
    }

    @Test func conversationTitleAndSenderUseTheOwnNickname() {
        let direct = ChatFixtures.direct(peer: ChatFixtures.mia.withNickname("Mimi"))
        #expect(direct.title == "Mia")
        #expect(direct.shownTitle == "Mimi")
        #expect(!direct.canPin)
        #expect(ChatFixtures.group(title: "Laufgruppe").shownTitle == "Laufgruppe")
        let preview = ChatMessagePreview(kind: .voice, text: nil, senderName: "Mia", isOwn: false, sentAt: Date(), senderNickname: "Mimi",
                                         mediaDuration: .seconds(18))
        #expect(preview.shownSenderName == "Mimi")
        #expect(ChatMessagePreview(kind: .text, text: "x", senderName: nil, isOwn: true, sentAt: Date()).shownSenderName == nil)
    }

    @Test func audioIsOnlyAllowedForChatUploads() {
        let chat = MediaUploadTarget.chat(conversationID: conversationID)
        #expect(MediaRules.allowedContentTypes(for: chat).contains(MediaRules.voiceContentType))
        #expect(MediaRules.allowedContentTypes(for: chat).isSuperset(of: MediaRules.allowedContentTypes))
        #expect(!MediaRules.allowedContentTypes(for: .avatar).contains("audio/mp4"))
        #expect(!MediaRules.allowedContentTypes(for: .groupImage(groupID: UUID())).contains("audio/aac"))
        #expect(MediaRules.isAudio("AUDIO/MP4"))
        #expect(!MediaRules.isAudio("image/jpeg"))
    }

    @Test func defaultImplementationsReportUnavailable() async {
        struct LegacyChat: ChatRepository {
            func conversations() async throws -> [ConversationSummary] { [] }
            func openDirectConversation(with publicID: UUID) async throws -> ConversationSummary { throw SocialError.notFound }
            func groupConversation(for groupID: UUID) async throws -> ConversationSummary { throw SocialError.notFound }
            func messages(in conversationID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] { [] }
            func send(_ draft: ChatMessageDraft, to conversationID: UUID) async throws -> ChatMessage { throw SocialError.notFound }
            func markRead(_ conversationID: UUID, through: Date) async throws {}
            func deleteMessage(_ messageID: UUID) async throws {}
            func messageEvents(in conversationID: UUID) -> AsyncStream<Void> {
                AsyncStream { continuation in
                    continuation.yield()
                    continuation.finish()
                }
            }
            func conversationEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
        }
        let legacy = LegacyChat()
        await #expect(throws: SocialError.unavailable) { try await legacy.editMessage(UUID(), text: "x") }
        await #expect(throws: SocialError.unavailable) { try await legacy.setFavorite(UUID(), isFavorite: true) }
        await #expect(throws: SocialError.unavailable) { try await legacy.pins(conversationID: UUID()) }
        var events: [ChatConversationEvent] = []
        for await event in legacy.conversationActivity(in: UUID()) {
            events.append(event)
        }
        #expect(events == [.message])
    }
}

struct ChatRepositoryStubActionTests {
    @Test func stubSupportsRepliesEditsFavoritesAndPins() async throws {
        let conversationID = UUID()
        let stub = ChatRepositoryStub()
        let first = try await stub.send(.text("Treffen?"), to: conversationID)
        let reply = try await stub.send(.text("Ja", replyTo: first.id), to: conversationID)
        #expect(reply.replyPreview?.id == first.id)
        #expect(reply.replyPreview?.text == "Treffen?")
        let edited = try await stub.editMessage(first.id, text: "Treffen um 7?")
        #expect(edited.isEdited)
        try await stub.setFavorite(first.id, isFavorite: true)
        #expect(try await stub.favorites(conversationID: conversationID).map(\.id) == [first.id])
        let pins = try await stub.setPinned(reply.id, isPinned: true)
        #expect(pins.map(\.id) == [reply.id])
        #expect(try await stub.messages(in: conversationID, before: nil, limit: 10).first { $0.id == reply.id }?.isPinned == true)
        stub.state.withLock { $0.canPin = false }
        await #expect(throws: SocialError.notAllowed) { try await stub.setPinned(first.id, isPinned: true) }
    }
}

struct GroupCalendarContractTests {
    private let calendar = Fixtures.activityCalendar

    @Test func monthGridStartsOnMondayAndFitsOneRequest() {
        // Oktober 2026: Donnerstag, 1. bis Samstag, 31. → Montag, 28. September bis Sonntag, 1. November.
        let october = GroupCalendarRules.monthGrid(containing: Fixtures.day(2026, 10, 16), calendar: calendar)
        #expect(october.lowerBound == Fixtures.day(2026, 9, 28))
        #expect(october.upperBound == Fixtures.day(2026, 11, 1))
        // Mai 2027 beginnt an einem Samstag und hat 31 Tage: 6 Wochen = 42 Tage.
        let may = GroupCalendarRules.monthGrid(containing: Fixtures.day(2027, 5, 10), calendar: calendar)
        #expect(calendar.days(from: may.lowerBound, through: may.upperBound).count == GroupCalendarRules.maximumDays)
        // Februar 2027 beginnt an einem Montag: genau 4 Wochen.
        let february = GroupCalendarRules.monthGrid(containing: Fixtures.day(2027, 2, 14), calendar: calendar)
        #expect(calendar.days(from: february.lowerBound, through: february.upperBound).count == 28)
    }

    @Test func dayStatesAreHonest() {
        let entry = GroupCalendarEntry(rank: 1, profile: ChatFixtures.mia, competitionSteps: 9_000, reached: true, isCurrentUser: false)
        let zero = GroupCalendarEntry(rank: 1, profile: ChatFixtures.leon, competitionSteps: 0, reached: false, isCurrentUser: true)
        func day(_ d: Int, secured: Bool, hasData: Bool, isToday: Bool = false, ranking: [GroupCalendarEntry] = []) -> GroupCalendarDay {
            GroupCalendarDay(day: Fixtures.day(2026, 10, d), dailyGoal: 8_000, memberCount: 3, requiredCount: 1,
                             reachedCount: secured ? 1 : 0, secured: secured, hasData: hasData, isToday: isToday, ranking: ranking)
        }
        let groupCalendar = GroupCalendar(
            groupID: UUID(), timeZone: "Europe/Berlin", groupToday: Fixtures.day(2026, 10, 16), firstGroupDay: Fixtures.day(2026, 10, 10),
            days: [day(12, secured: true, hasData: true, ranking: [entry]), day(13, secured: false, hasData: true),
                   day(14, secured: false, hasData: false, ranking: [zero]), day(16, secured: false, hasData: true, isToday: true)]
        )
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 9)) == .beforeGroup)
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 11)) == .notLoaded)
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 12)) == .secured)
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 13)) == .missed)
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 14)) == .noData)
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 16)) == .open)
        #expect(groupCalendar.state(of: Fixtures.day(2026, 10, 17)) == .future)
        #expect(groupCalendar.day(Fixtures.day(2026, 10, 12))?.best == entry)
        #expect(groupCalendar.day(Fixtures.day(2026, 10, 14))?.best == nil)
        #expect(groupCalendar.day(Fixtures.day(2026, 10, 14))?.currentUserEntry == zero)
    }

    @Test func socialStubFiltersTheCalendarAndSetsNicknames() async throws {
        let groupID = UUID()
        let mia = ChatFixtures.mia
        let stub = SocialRepositoryStub { state in
            state.friends = [Friend(profile: mia, friendsSince: Date(timeIntervalSince1970: 0))]
            state.calendars[groupID] = GroupCalendar(
                groupID: groupID, timeZone: "Europe/Berlin", groupToday: Fixtures.day(2026, 10, 16), firstGroupDay: Fixtures.day(2026, 10, 1),
                days: (1...16).map { d in
                    GroupCalendarDay(day: Fixtures.day(2026, 10, d), dailyGoal: 8_000, memberCount: 2, requiredCount: 1, reachedCount: 0,
                                     secured: false, hasData: false, isToday: d == 16, ranking: [])
                }
            )
        }
        let window = try await stub.groupCalendar(groupID: groupID, from: Fixtures.day(2026, 10, 10), to: Fixtures.day(2026, 10, 20))
        #expect(window.days.map(\.day.day) == Array(10...16))
        let named = try await stub.setFriendNickname(publicID: mia.publicID, nickname: " Mimi ")
        #expect(named.nickname == "Mimi")
        #expect(try await stub.friends().first?.profile.shownName == "Mimi")
        await #expect(throws: SocialError.notFound) { try await stub.setFriendNickname(publicID: UUID(), nickname: "X") }
        await #expect(throws: SocialError.invalidNickname) {
            try await stub.setFriendNickname(publicID: mia.publicID, nickname: String(repeating: "x", count: 31))
        }
    }
}
