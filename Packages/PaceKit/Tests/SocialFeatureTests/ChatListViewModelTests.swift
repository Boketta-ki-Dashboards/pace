import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

@MainActor
struct ChatListViewModelTests {
    private let base = Fixtures.date(2026, 10, 16, 12)

    private func makeList(
        _ repository: ChatRepositoryStub?,
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
            pollInterval: .seconds(25),
            sleep: { try await ticker.sleep($0) }
        )
    }

    private func preview(_ text: String, from sender: String?, own: Bool = false, at date: Date) -> ChatMessagePreview {
        ChatMessagePreview(kind: .text, text: text, senderName: sender, isOwn: own, sentAt: date)
    }

    // MARK: Zustände

    @Test func withoutBackendChatsAreHonestlyUnavailable() async {
        let list = makeList(nil)

        await list.load()

        #expect(!list.isAvailable)
        #expect(list.state == .unavailable(ChatTexts.unavailable))
        #expect(list.conversations.isEmpty)
        await #expect(throws: SocialError.unavailable) {
            try await list.shareProfile(ChatFixtures.mia, with: [.direct(ChatFixtures.mia)])
        }
        let chat = list.chat(for: .direct(ChatFixtures.mia))
        #expect(chat.state == .unavailable(ChatTexts.unavailable))
        #expect(!chat.canSend)
    }

    @Test func missingServerSetupIsShownAsUnavailable() async {
        let list = makeList(ChatRepositoryStub { $0.error = .unavailable })

        await list.load()

        #expect(list.state == .unavailable(SocialError.unavailable.message))
        #expect(!list.isAvailable)
    }

    @Test func loadingErrorCanBeRetriedAndRefreshErrorKeepsChats() async {
        let repository = ChatRepositoryStub { state in
            state.error = .network
            state.conversations = [ChatFixtures.direct()]
        }
        let list = makeList(repository)

        await list.load()
        #expect(list.state == .failed(SocialError.network.message))

        repository.state.withLock { $0.error = nil }
        await list.load()
        #expect(list.state == .loaded)
        #expect(list.conversations.count == 1)

        repository.state.withLock { $0.error = .network }
        await list.load()
        #expect(list.state == .loaded)
        #expect(list.conversations.count == 1)
        #expect(list.refreshError == SocialError.network.message)
    }

    @Test func emptyListIsLoadedWithoutConversations() async {
        let list = makeList(ChatRepositoryStub())

        await list.load()

        #expect(list.state == .loaded)
        #expect(list.filteredConversations.isEmpty)
        #expect(list.unreadCount == 0)
    }

    // MARK: Filter, Sortierung, Ungelesen

    @Test func sortsByLastActivityAndSumsUnreadMessages() async {
        let older = ChatFixtures.direct(peer: ChatFixtures.mia, unread: 2, updatedAt: base.addingTimeInterval(-3_600))
        let newest = ChatFixtures.group(title: "Klassengruppe", unread: 5, updatedAt: base)
        let oldest = ChatFixtures.direct(peer: ChatFixtures.leon, unread: 0, updatedAt: base.addingTimeInterval(-86_400))
        let list = makeList(ChatRepositoryStub { $0.conversations = [oldest, older, newest] })

        await list.load()

        #expect(list.conversations.map(\.id) == [newest.id, older.id, oldest.id])
        #expect(list.unreadCount == 7)
    }

    @Test func filterSeparatesFriendsAndGroups() async {
        let direct = ChatFixtures.direct()
        let group = ChatFixtures.group()
        let list = makeList(ChatRepositoryStub { $0.conversations = [direct, group] })
        await list.load()

        list.filter = .friends
        #expect(list.filteredConversations.map(\.id) == [direct.id])
        list.filter = .groups
        #expect(list.filteredConversations.map(\.id) == [group.id])
        list.filter = .all
        #expect(Set(list.filteredConversations.map(\.id)) == [direct.id, group.id])
    }

    @Test func filterTitlesAreTranslated() {
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatListViewModel.Filter.allCases.map(\.title) == ["All", "Friends", "Groups"])
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatListViewModel.Filter.allCases.map(\.title) == ["Все", "Друзья", "Группы"])
        }
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatListViewModel.Filter.allCases.map(\.title) == ["Alle", "Freunde", "Gruppen"])
        }
    }

    @Test func localSearchMatchesTitleAndUsername() async {
        let mia = ChatFixtures.direct(peer: ChatFixtures.mia)
        let group = ChatFixtures.group(title: "Läufer Köln")
        let list = makeList(ChatRepositoryStub { $0.conversations = [mia, group] })
        await list.load()

        #expect(list.conversations(matching: "  ").count == 2)
        #expect(list.conversations(matching: "@mi").map(\.id) == [mia.id])
        #expect(list.conversations(matching: "laufer").map(\.id) == [group.id])
        #expect(list.conversations(matching: "xyz").isEmpty)
        list.filter = .groups
        #expect(list.displayedConversations(searchText: "m").isEmpty)
    }

    @Test func readingAChatResetsItsUnreadCount() async {
        let direct = ChatFixtures.direct(unread: 3)
        let list = makeList(ChatRepositoryStub { $0.conversations = [direct] })
        await list.load()

        list.didMarkRead(direct.id)

        #expect(list.unreadCount == 0)
    }

    // MARK: Laden ohne Doppelungen, Echtzeit, Polling

    @Test func concurrentLoadsAreCoalesced() async throws {
        let repository = ChatRepositoryStub { $0.conversations = [ChatFixtures.direct()] }
        repository.gate.close("conversations")
        let list = makeList(repository)

        let first = Task { await list.load() }
        try await waitUntil { repository.gate.waitingCount("conversations") == 1 }
        let second = Task { await list.load() }
        let third = Task { await list.load() }
        let fourth = Task { await list.loadIfNeeded() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(repository.gate.waitingCount("conversations") == 1)

        repository.gate.open("conversations")
        await first.value
        await second.value
        await third.value
        await fourth.value

        // Ein Ladevorgang plus genau ein frischer danach – nie parallel.
        #expect(repository.callCount("conversations") == 2)
        #expect(list.state == .loaded)
    }

    @Test func loadIfNeededSkipsFreshData() async {
        let repository = ChatRepositoryStub { $0.conversations = [ChatFixtures.direct()] }
        let list = makeList(repository)

        await list.loadIfNeeded()
        await list.loadIfNeeded()

        #expect(repository.callCount("conversations") == 1)
    }

    @Test func realtimeEventReloadsTheList() async throws {
        let conversationID = UUID()
        let repository = ChatRepositoryStub { $0.conversations = [ChatFixtures.direct(id: conversationID)] }
        let list = makeList(repository)
        let observing = Task { await list.observe() }
        try await waitUntil { list.state == .loaded && repository.subscriberCount() == 1 }

        repository.state.withLock { state in
            state.conversations = [ChatFixtures.direct(id: conversationID, unread: 1, updatedAt: base.addingTimeInterval(60))]
        }
        repository.receive(ChatFixtures.message(in: conversationID, from: ChatFixtures.mia, text: "Hallo", at: base.addingTimeInterval(60)))

        try await waitUntil { list.unreadCount == 1 }
        observing.cancel()
        await observing.value
    }

    @Test func pollingFallbackRefreshesWithoutRealtime() async throws {
        let repository = ChatRepositoryStub { state in
            state.realtimeAvailable = false
            state.conversations = []
        }
        let ticker = ManualTicker()
        let list = makeList(repository, ticker: ticker)
        let observing = Task { await list.observe() }
        try await waitUntil { list.state == .loaded && ticker.waitingCount == 1 }
        #expect(list.conversations.isEmpty)

        repository.state.withLock { $0.conversations = [ChatFixtures.group(unread: 2)] }
        ticker.tick()

        try await waitUntil { list.unreadCount == 2 }
        try await waitUntil { ticker.waitingCount == 1 }
        #expect(repository.callCount("conversations") == 2)
        observing.cancel()
        await observing.value
        #expect(ticker.waitingCount == 0)
    }

    // MARK: Chats

    @Test func sameConversationAlwaysGetsTheSameChat() async {
        let direct = ChatFixtures.direct(peer: ChatFixtures.mia)
        let groupID = UUID()
        let group = ChatFixtures.group(groupID: groupID)
        let list = makeList(ChatRepositoryStub { $0.conversations = [direct, group] })
        await list.load()

        let fromList = list.chat(for: ChatTarget(direct))
        let fromProfile = list.chat(for: .direct(ChatFixtures.mia))
        let fromGroup = list.chat(for: .group(id: groupID, name: "Smoking red"))
        let groupFromList = list.chat(for: ChatTarget(group))

        #expect(fromList === fromProfile)
        #expect(fromGroup === groupFromList)
        #expect(fromList !== fromGroup)
        #expect(fromList.conversation == direct)
    }

    @Test func draftsSurviveNavigatingBack() async {
        let direct = ChatFixtures.direct()
        let list = makeList(ChatRepositoryStub { $0.conversations = [direct] })
        await list.load()

        list.chat(for: ChatTarget(direct)).draftText = "Bis gleich"

        #expect(list.chat(for: ChatTarget(direct)).draftText == "Bis gleich")
    }

    // MARK: Profil teilen

    @Test func sharingAProfileSendsAProfileMessageToEveryTarget() async throws {
        let known = ChatFixtures.direct(peer: ChatFixtures.leon)
        let newDirect = ChatFixtures.direct(peer: ChatFixtures.marie)
        let groupID = UUID()
        let groupChat = ChatFixtures.group(groupID: groupID)
        let repository = ChatRepositoryStub { state in
            state.conversations = [known]
            state.directConversations[ChatFixtures.marie.publicID] = newDirect
            state.groupConversations[groupID] = groupChat
        }
        let list = makeList(repository)
        await list.load()

        try await list.shareProfile(ChatFixtures.gotscha, with: [
            .direct(ChatFixtures.leon),
            .direct(ChatFixtures.marie),
            .group(id: groupID, name: "Smoking red"),
            .direct(ChatFixtures.leon),
        ])

        let sent = repository.state.withLock { $0.sentDrafts }
        #expect(sent.count == 3)
        #expect(sent.map(\.1) == [known.id, newDirect.id, groupChat.id])
        #expect(sent.allSatisfy { $0.0.kind == .profile && $0.0.sharedProfileID == ChatFixtures.gotscha.publicID })
        #expect(repository.callCount("openDirectConversation") == 1)
        #expect(repository.callCount("groupConversation") == 1)
    }

    @Test func sharingReportsFailuresPerTarget() async throws {
        let known = ChatFixtures.direct(peer: ChatFixtures.leon)
        let repository = ChatRepositoryStub { $0.conversations = [known] }
        let list = makeList(repository)
        await list.load()

        do {
            try await list.shareProfile(ChatFixtures.gotscha, with: [.direct(ChatFixtures.leon), .direct(ChatFixtures.marie)])
            Issue.record("Teilen hätte teilweise fehlschlagen müssen")
        } catch let error as ProfileShareError {
            #expect(error.sharedCount == 1)
            #expect(error.failures.map(\.target) == [.direct(ChatFixtures.marie)])
            PaceLocalization.$languageOverride.withValue(.english) {
                #expect(error.message.hasPrefix("Sent to 1 chat."))
                #expect(error.message.contains("Marie"))
            }
        }
        #expect(repository.state.withLock { $0.sentDrafts.count } == 1)
    }

    @Test func sharingWithNobodyDoesNothing() async throws {
        let repository = ChatRepositoryStub()
        let list = makeList(repository)

        try await list.shareProfile(ChatFixtures.gotscha, with: [])

        #expect(repository.state.withLock { $0.sentDrafts.isEmpty })
    }
}
