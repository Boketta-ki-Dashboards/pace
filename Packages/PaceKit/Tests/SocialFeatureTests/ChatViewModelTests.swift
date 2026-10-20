import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

@MainActor
struct ChatViewModelTests {
    private let base = Fixtures.date(2026, 10, 16, 18)

    private func makeList(
        _ repository: ChatRepositoryStub,
        media: MediaRepositoryStub? = nil,
        social: SocialRepositoryStub? = nil,
        ticker: ManualTicker = ManualTicker()
    ) -> ChatListViewModel {
        ChatListViewModel(
            repository: repository,
            media: media,
            social: social,
            calendar: Fixtures.activityCalendar,
            now: { [base] in base },
            sleep: { try await ticker.sleep($0) }
        )
    }

    /// Nachrichten im Minutenabstand, die letzte zur Zeit `base`.
    private func history(_ count: Int, in conversationID: UUID, from sender: SocialProfile = ChatFixtures.mia) -> [ChatMessage] {
        (0..<count).map { index in
            ChatFixtures.message(
                in: conversationID,
                from: sender,
                text: "Nachricht \(index)",
                at: base.addingTimeInterval(Double(index - count + 1) * 60)
            )
        }
    }

    private func messageCount(_ chat: ChatViewModel) -> Int {
        chat.timeline.filter { if case .entry = $0 { true } else { false } }.count
    }

    // MARK: Laden und Nachladen

    @Test func opensTheDirectChatOfAFriendAndLoadsTheNewestPage() async throws {
        let conversation = ChatFixtures.direct(peer: ChatFixtures.mia)
        let repository = ChatRepositoryStub { state in
            state.directConversations[ChatFixtures.mia.publicID] = conversation
        }
        repository.state.withLock { $0.messages[conversation.id] = history(50, in: conversation.id) }
        let list = makeList(repository)
        let chat = list.chat(for: .direct(ChatFixtures.mia))

        await chat.load()

        #expect(chat.state == .loaded)
        #expect(chat.conversation == conversation)
        #expect(chat.title == "Mia")
        #expect(chat.messages.count == ChatRules.pageSize)
        #expect(chat.messages.last?.text == "Nachricht 49")
        #expect(chat.messages.map(\.sentAt) == chat.messages.map(\.sentAt).sorted())
        #expect(chat.hasOlderMessages)
        #expect(chat.canSend)
        #expect(chat.readOnlyMessage == nil)
    }

    @Test func loadsOlderMessagesWhenScrollingUp() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = history(50, in: conversation.id) }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.loadOlder()

        #expect(chat.messages.count == 50)
        #expect(chat.messages.first?.text == "Nachricht 0")
        #expect(!chat.hasOlderMessages)
        #expect(chat.olderError == nil)

        // Neu laden behält die älteren Nachrichten.
        await chat.refresh()
        #expect(chat.messages.count == 50)

        // Keine weiteren Abfragen, wenn nichts Älteres mehr da ist.
        let calls = repository.callCount("messages")
        await chat.loadOlder()
        #expect(repository.callCount("messages") == calls)
    }

    @Test func olderMessagesErrorIsVisibleAndRecoverable() async {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = history(45, in: conversation.id) }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        repository.state.withLock { $0.error = .network }
        await chat.loadOlder()
        #expect(chat.olderError == ChatTexts.olderFailed)
        #expect(chat.messages.count == 40)

        repository.state.withLock { $0.error = nil }
        await chat.loadOlder()
        #expect(chat.olderError == nil)
        #expect(chat.messages.count == 45)
    }

    @Test func unknownConversationIsShownAsGone() async {
        let list = makeList(ChatRepositoryStub())
        let chat = list.chat(for: .conversation(id: UUID(), kind: .direct, title: "Mia"))

        await chat.load()

        #expect(chat.state == .failed(ChatTexts.conversationGone))
        #expect(!chat.canSend)
    }

    @Test func networkErrorOnOpenCanBeRetried() async {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { state in
            state.directConversations[ChatFixtures.mia.publicID] = conversation
            state.error = .network
        }
        let chat = makeList(repository).chat(for: .direct(ChatFixtures.mia))

        await chat.load()
        #expect(chat.state == .failed(SocialError.network.message))

        repository.state.withLock { $0.error = nil }
        await chat.loadIfNeeded()
        #expect(chat.state == .loaded)
    }

    @Test func refreshRemovesMessagesDeletedElsewhere() async {
        let conversation = ChatFixtures.direct()
        let messages = history(3, in: conversation.id)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = messages }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        repository.state.withLock { state in _ = state.messages[conversation.id]?.removeFirst() }
        await chat.refresh()

        #expect(chat.messages.map(\.id) == Array(messages.dropFirst()).map(\.id))
    }

    // MARK: Senden

    @Test func sendingShowsTheMessageImmediatelyAndReplacesItAfterwards() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        repository.gate.close("send")

        chat.draftText = "  Ich komme mit.  "
        #expect(chat.canSubmitText)
        let sending = Task { await chat.sendText() }
        try await waitUntil { repository.gate.waitingCount("send") == 1 }

        #expect(chat.draftText.isEmpty)
        #expect(chat.pending.count == 1)
        #expect(chat.pending.first?.text == "Ich komme mit.")
        #expect(chat.pending.first?.status == .sending)

        repository.gate.open("send")
        await sending.value

        #expect(chat.pending.isEmpty)
        #expect(chat.messages.count == 1)
        #expect(chat.messages.first?.isOwn == true)
        #expect(chat.messages.first?.text == "Ich komme mit.")
    }

    @Test func emptyOrTooLongTextIsNotSent() async {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        chat.draftText = "   \n "
        #expect(!chat.canSubmitText)
        await chat.sendText()

        chat.draftText = String(repeating: "a", count: ChatRules.maximumTextLength + 1)
        #expect(chat.isDraftTooLong)
        #expect(chat.remainingCharacters == -1)
        await chat.sendText()

        #expect(repository.callCount("send") == 0)
        #expect(chat.notice == ChatNotice(text: ChatTexts.tooLong, isError: true))
        #expect(chat.draftText.count == ChatRules.maximumTextLength + 1)
    }

    @Test func failedMessageCanBeRetriedWithTheSameClientID() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.sendError = .network
        }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        chat.draftText = "Passt, bis gleich!"
        await chat.sendText()

        let failed = try #require(chat.pending.first)
        #expect(failed.status == .failed(SocialError.network.message))
        #expect(chat.messages.isEmpty)

        repository.state.withLock { $0.sendError = nil }
        await chat.retry(failed.clientID)

        #expect(chat.pending.isEmpty)
        #expect(chat.messages.count == 1)
        #expect(chat.messages.first?.clientID == failed.clientID)
        let drafts = repository.state.withLock { $0.sentDrafts.map(\.0.clientID) }
        #expect(drafts == [failed.clientID, failed.clientID])
    }

    @Test func failedMessageCanBeDiscarded() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.sendError = .rateLimited
        }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        chat.draftText = "Hallo"
        await chat.sendText()

        let failed = try #require(chat.pending.first)
        chat.discard(failed.clientID)

        #expect(chat.pending.isEmpty)
    }

    @Test func realtimeEventAndReloadNeverDuplicateAMessage() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        let observing = Task { await chat.observe() }
        try await waitUntil { chat.state == .loaded && repository.subscriberCount(conversationID: conversation.id) == 1 }

        // Der Server hat die Nachricht schon gespeichert, die Antwort aufs Senden steht aber noch aus.
        repository.gate.close("send")
        chat.draftText = "Wer läuft mit?"
        let sending = Task { await chat.sendText() }
        try await waitUntil { repository.gate.waitingCount("send") == 1 }
        let clientID = try #require(chat.pending.first?.clientID)
        let saved = ChatFixtures.message(in: conversation.id, from: ChatFixtures.mia, isOwn: true, text: "Wer läuft mit?", clientID: clientID, at: base)
        repository.receive(saved)
        try await waitUntil { chat.messages.count == 1 }
        #expect(chat.pending.isEmpty)
        #expect(messageCount(chat) == 1)

        // Die Antwort aufs Senden (gleiche clientID) ersetzt nichts doppelt.
        repository.gate.open("send")
        await sending.value
        await chat.refresh()

        #expect(chat.messages.count == 1)
        #expect(messageCount(chat) == 1)
        observing.cancel()
        await observing.value
    }

    @Test func incomingMessagesArriveByRealtimeAndAreMarkedRead() async throws {
        let conversation = ChatFixtures.group(unread: 2)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = history(2, in: conversation.id) }
        let list = makeList(repository)
        await list.load()
        #expect(list.unreadCount == 2)
        let chat = list.chat(for: ChatTarget(conversation))

        let observing = Task { await chat.observe() }
        try await waitUntil { repository.subscriberCount(conversationID: conversation.id) == 1 }

        // Beim Öffnen gelesen.
        #expect(repository.state.withLock { $0.readMarks.map(\.1) } == [base])
        #expect(list.unreadCount == 0)

        let incoming = ChatFixtures.message(in: conversation.id, from: ChatFixtures.leon, text: "Bin dabei", at: base.addingTimeInterval(30))
        repository.receive(incoming)
        try await waitUntil { chat.messages.last?.id == incoming.id }
        try await waitUntil { repository.state.withLock { $0.readMarks.count } == 2 }
        #expect(repository.state.withLock { $0.readMarks.last?.1 } == incoming.sentAt)

        observing.cancel()
        await observing.value

        // Nicht sichtbar: neue Nachrichten werden nicht als gelesen gemeldet.
        repository.store(ChatFixtures.message(in: conversation.id, from: ChatFixtures.leon, text: "Später", at: base.addingTimeInterval(90)))
        await chat.refresh()
        #expect(chat.messages.count == 4)
        #expect(repository.state.withLock { $0.readMarks.count } == 2)
    }

    @Test func overlappingObserversKeepTheChatVisible() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = history(1, in: conversation.id) }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        let first = Task { await chat.observe() }
        try await waitUntil { repository.subscriberCount(conversationID: conversation.id) == 1 }
        let second = Task { await chat.observe() }
        try await waitUntil { repository.subscriberCount(conversationID: conversation.id) == 2 }

        first.cancel()
        await first.value
        repository.receive(ChatFixtures.message(in: conversation.id, from: ChatFixtures.mia, text: "Noch da?", at: base.addingTimeInterval(60)))

        try await waitUntil { repository.state.withLock { $0.readMarks.count } == 2 }
        second.cancel()
        await second.value
    }

    @Test func pollingFallbackLoadsNewMessagesWithoutRealtime() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.realtimeAvailable = false
        }
        let ticker = ManualTicker()
        let list = makeList(repository, ticker: ticker)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        let observing = Task { await chat.observe() }
        try await waitUntil { chat.state == .loaded && ticker.waitingCount == 1 }

        repository.store(ChatFixtures.message(in: conversation.id, from: ChatFixtures.mia, text: "Hallo?", at: base))
        ticker.tick()

        try await waitUntil { chat.messages.count == 1 }
        observing.cancel()
        await observing.value
    }

    @Test func readOnlyConversationReplacesTheInputWithAnExplanation() async {
        let conversation = ChatFixtures.direct(canSend: false)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        chat.draftText = "Hallo"
        await chat.sendText()

        #expect(!chat.canSend)
        #expect(!chat.canSubmitText)
        #expect(chat.readOnlyMessage == ChatTexts.readOnly(kind: .direct, peerName: "Mia", blockedByMe: false))
        #expect(repository.callCount("send") == 0)
    }

    @Test func serverRefusalMakesTheChatReadOnly() async {
        let conversation = ChatFixtures.group()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.sendError = .readOnly
        }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        chat.draftText = "Hallo"
        await chat.sendText()

        #expect(!chat.canSend)
        #expect(chat.pending.first?.status == .failed(SocialError.readOnly.message))
    }

    // MARK: Bilder und GIFs

    @Test func photoIsUploadedThenSent() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let media = MediaRepositoryStub()
        let list = makeList(repository, media: media)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        let photo = Data(repeating: 1, count: 1_024)

        await chat.sendMedia(photo, contentType: "image/jpeg")

        #expect(media.state.withLock { $0.uploads } == [.chat(conversationID: conversation.id)])
        let draft = try #require(repository.state.withLock { $0.sentDrafts.first?.0 })
        #expect(draft.kind == .image)
        let path = try #require(draft.mediaPath)
        let message = try #require(chat.messages.first)
        let reference = try #require(message.media)
        #expect(reference == MediaReference(bucket: .chatMedia, path: path))
        #expect(chat.uploadedData(for: reference) == photo)
        #expect(chat.pending.isEmpty)
    }

    @Test func gifIsSentAsGif() async throws {
        let conversation = ChatFixtures.group()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let list = makeList(repository, media: MediaRepositoryStub())
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.sendMedia(Data("GIF89a".utf8), contentType: "image/gif")

        #expect(chat.messages.first?.kind == .gif)
    }

    @Test func uploadErrorIsShownAndRetryUploadsOnlyOnce() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let media = MediaRepositoryStub { $0.error = .network }
        let list = makeList(repository, media: media)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.sendMedia(Data(repeating: 2, count: 64), contentType: "image/jpeg")
        let failed = try #require(chat.pending.first)
        #expect(failed.status == .failed(SocialError.network.message))
        #expect(failed.localMedia != nil)
        #expect(repository.callCount("send") == 0)

        // Hochladen klappt, Senden nicht: beim nächsten Versuch nicht noch einmal hochladen.
        media.state.withLock { $0.error = nil }
        repository.state.withLock { $0.sendError = .network }
        await chat.retry(failed.clientID)
        #expect(chat.pending.first?.mediaPath != nil)
        #expect(chat.pending.first?.isFailed == true)

        repository.state.withLock { $0.sendError = nil }
        await chat.retry(failed.clientID)

        #expect(chat.pending.isEmpty)
        #expect(chat.messages.count == 1)
        #expect(media.state.withLock { $0.uploads.count } == 1)
    }

    @Test func unsupportedOrTooLargeImagesAreRejectedBeforeUploading() async {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let media = MediaRepositoryStub()
        let list = makeList(repository, media: media)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.sendMedia(Data(repeating: 0, count: 10), contentType: "video/mp4")
        #expect(chat.notice == ChatNotice(text: ChatTexts.media(.unsupportedType), isError: true))

        await chat.sendMedia(Data(count: MediaRules.maximumBytes(for: .chat(conversationID: conversation.id)) + 1), contentType: "image/jpeg")
        #expect(chat.notice == ChatNotice(text: ChatTexts.media(.tooLarge), isError: true))

        #expect(media.state.withLock { $0.uploads.isEmpty })
        #expect(chat.pending.isEmpty)
    }

    @Test func imagesWithoutMediaBackendFailHonestly() async throws {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let list = makeList(repository, media: nil)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.sendMedia(Data(repeating: 1, count: 16), contentType: "image/png")

        #expect(chat.pending.first?.status == .failed(ChatTexts.mediaUnavailable))
        #expect(repository.callCount("send") == 0)
    }

    // MARK: Gruppe, Blockieren, Melden, Löschen

    @Test func groupChatLoadsStreakMembersAndCollapsesBlockedPeople() async throws {
        let groupID = UUID()
        let conversation = ChatFixtures.group(groupID: groupID, memberCount: 3)
        let group = SocialRepositoryStub.group(id: groupID, name: "Smoking red", memberCount: 3, currentStreak: 12, reached: 2)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let fromBlocked = ChatFixtures.message(in: conversation.id, from: ChatFixtures.gotscha, text: "Spam", at: base)
        repository.state.withLock { state in
            state.messages[conversation.id] = [
                ChatFixtures.message(in: conversation.id, from: ChatFixtures.leon, text: "Hallo", at: base.addingTimeInterval(-60)),
                fromBlocked,
            ]
        }
        let social = SocialRepositoryStub { state in
            state.groups = [group]
            state.blocked = [ChatFixtures.gotscha]
            state.groupRankings[groupID] = GroupRanking(
                totalParticipants: 3,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: [ChatFixtures.leon, ChatFixtures.marie, ChatFixtures.gotscha].enumerated().map { index, profile in
                    GroupRankingEntry(rank: index + 1, profile: profile, competitionSteps: 1_000, isCurrentUser: false, role: .member, reachedGoalToday: false)
                }
            )
        }
        let list = makeList(repository, social: social)
        await list.load()
        let chat = list.chat(for: .group(id: groupID, name: "Smoking red"))
        await chat.load()

        #expect(chat.group?.currentStreak == 12)
        #expect(chat.memberPreview.map(\.username) == ["leon", "marie", "gotscha"])
        #expect(chat.memberCount == 3)
        #expect(chat.canInvite)
        let blockedEntry = chat.timeline.compactMap { item -> ChatTimelineEntry? in
            if case .entry(let entry) = item, entry.sender == ChatFixtures.gotscha { return entry }
            return nil
        }.first
        #expect(blockedEntry?.content == .blocked(fromBlocked))

        chat.reveal(fromBlocked.id)
        let revealed = chat.timeline.contains { item in
            if case .entry(let entry) = item, case .message(let message) = entry.content { return message.id == fromBlocked.id }
            return false
        }
        #expect(revealed)
    }

    @Test func blockingThePeerEndsTheDirectChat() async {
        let conversation = ChatFixtures.direct(peer: ChatFixtures.mia)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let social = SocialRepositoryStub()
        let list = makeList(repository, social: social)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.block(ChatFixtures.mia)

        #expect(social.state.withLock { $0.blocked.map(\.publicID) } == [ChatFixtures.mia.publicID])
        #expect(!chat.canSend)
        #expect(chat.readOnlyMessage == ChatTexts.readOnly(kind: .direct, peerName: "Mia", blockedByMe: true))
        #expect(chat.notice == ChatNotice(text: ChatTexts.blocked("Mia"), isError: false))
    }

    @Test func reportingAMessageCreatesAReport() async throws {
        let conversation = ChatFixtures.group()
        let message = ChatFixtures.message(in: conversation.id, from: ChatFixtures.leon, text: "…", at: base)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = [message] }
        let social = SocialRepositoryStub()
        let list = makeList(repository, social: social)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.report(message, reason: .harassment)
        await chat.reportConversation(reason: .spam)

        let groupID = try #require(conversation.groupID)
        let reports = social.state.withLock { $0.reports }
        #expect(reports.count == 2)
        #expect(reports.first?.0 == .message(id: message.id))
        #expect(reports.first?.1 == .harassment)
        #expect(reports.last?.0 == .group(id: groupID))
        #expect(chat.notice == ChatNotice(text: ChatTexts.reported, isError: false))
    }

    @Test func reportingWithoutSocialBackendIsHonest() async {
        let conversation = ChatFixtures.direct()
        let message = ChatFixtures.message(in: conversation.id, from: ChatFixtures.mia, text: "…", at: base)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = [message] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.report(message, reason: .spam)

        #expect(chat.notice == ChatNotice(text: SocialError.unavailable.message, isError: true))
    }

    @Test func deletingAnOwnMessageRemovesIt() async {
        let conversation = ChatFixtures.direct()
        let own = ChatFixtures.message(in: conversation.id, from: nil, isOwn: true, text: "Ups", at: base)
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        repository.state.withLock { $0.messages[conversation.id] = [own] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.delete(own)

        #expect(chat.messages.isEmpty)
        #expect(repository.state.withLock { $0.deleted } == [own.id])
        #expect(chat.notice == ChatNotice(text: ChatTexts.messageDeleted, isError: false))
    }

    @Test func deleteErrorKeepsTheMessage() async {
        let conversation = ChatFixtures.direct()
        let own = ChatFixtures.message(in: conversation.id, from: nil, isOwn: true, text: "Ups", at: base)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.deleteError = .network
        }
        repository.state.withLock { $0.messages[conversation.id] = [own] }
        let list = makeList(repository)
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()

        await chat.delete(own)

        #expect(chat.messages.count == 1)
        #expect(chat.notice == ChatNotice(text: SocialError.network.message, isError: true))
    }
}
