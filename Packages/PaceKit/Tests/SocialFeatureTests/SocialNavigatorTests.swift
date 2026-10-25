import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Navigation im Social-Tab (P0 Auftrag 4): Gruppe → Flamme → Chat → Flamme → Chat … darf den Stapel nicht wachsen
/// lassen. Jede Seite hat eine Identität; eine schon offene Seite wird nicht erneut aufgelegt.
@MainActor
struct SocialNavigatorTests {
    private let groupID = UUID(uuidString: "a4000000-0000-4000-8000-000000000001")!
    private let otherGroupID = UUID(uuidString: "a4000000-0000-4000-8000-000000000002")!
    private let groupConversationID = UUID(uuidString: "a4000000-0000-4000-8000-000000000011")!
    private let otherConversationID = UUID(uuidString: "a4000000-0000-4000-8000-000000000012")!
    private let directConversationID = UUID(uuidString: "a4000000-0000-4000-8000-000000000013")!
    private let base = Fixtures.date(2026, 10, 16, 12)

    private func makeSocial() async -> (SocialViewModel, ChatRepositoryStub) {
        let chatRepository = ChatRepositoryStub { [self] state in
            state.conversations = [
                ChatFixtures.group(id: groupConversationID, groupID: groupID, title: "Smoking red"),
                ChatFixtures.group(id: otherConversationID, groupID: otherGroupID, title: "Klasse 8b"),
                ChatFixtures.direct(id: directConversationID, peer: ChatFixtures.mia),
            ]
        }
        let chats = ChatListViewModel(
            repository: chatRepository,
            media: nil,
            calendar: Fixtures.activityCalendar,
            now: { [base] in base },
            sleep: { try await ManualTicker().sleep($0) }
        )
        let repository = SocialRepositoryStub { [self] state in
            state.groups = [
                SocialRepositoryStub.group(id: groupID, name: "Smoking red"),
                SocialRepositoryStub.group(id: otherGroupID, name: "Klasse 8b"),
            ]
        }
        let social = SocialViewModel(
            repository: repository, chats: chats, ownUsername: { "niklas" },
            calendar: Fixtures.activityCalendar, now: { [base] in base }
        )
        await social.load()
        await chats.load()
        return (social, chatRepository)
    }

    // MARK: Schleife Gruppe ↔ Flamme ↔ Chat

    @Test func fiftyRoundTripsBetweenFlameAndChatKeepThePathShort() async {
        let (social, _) = await makeSocial()
        let navigator = social.navigator

        // Gruppe öffnen (Flamme = Gruppen-Streak in den Details), dann Gruppenchat, dann im Chat wieder die Flamme …
        navigator.open(.group(groupID))
        var longest = navigator.path.count
        for _ in 0..<50 {
            navigator.openChat(.group(id: groupID, name: "Smoking red"))
            longest = max(longest, navigator.path.count)
            #expect(navigator.path == [.route(.group(groupID)), .chat(.group(id: groupID, name: "Smoking red"))])
            // Flamme im Chat-Kopf: führt zur schon offenen Gruppe zurück, legt keine zweite auf.
            navigator.open(.group(groupID))
            longest = max(longest, navigator.path.count)
            #expect(navigator.path == [.route(.group(groupID))])
        }
        #expect(longest == 2)

        // Vollständig zurück und dieselbe Gruppe erneut öffnen: gleicher, kurzer Ablauf, dieselben ViewModels.
        let detail = social.detail(groupID: groupID)
        let chat = social.chats.chat(for: .group(id: groupID, name: "Smoking red"))
        navigator.path.removeLast()
        #expect(navigator.isAtRoot)
        navigator.open(.group(groupID))
        navigator.openChat(.group(id: groupID, name: "Smoking red"))
        #expect(navigator.path.count == 2)
        #expect(social.detail(groupID: groupID) === detail)
        #expect(social.chats.chat(for: .conversation(id: groupConversationID, kind: .group, title: "Smoking red")) === chat)
    }

    @Test func enteringFromTheChatListReturnsToTheSameChat() async {
        let (social, _) = await makeSocial()
        let navigator = social.navigator
        let fromList = ChatTarget.conversation(id: groupConversationID, kind: .group, title: "Smoking red")

        navigator.openChat(fromList)
        for _ in 0..<50 {
            // Flamme bzw. Info im Chat → Gruppe; dort „Gruppenchat“ → zurück zum schon offenen Chat (andere Zielart,
            // gleiche Unterhaltung).
            navigator.open(.group(groupID))
            #expect(navigator.path == [.chat(fromList), .route(.group(groupID))])
            navigator.openChat(.group(id: groupID, name: "Smoking red"))
            #expect(navigator.path == [.chat(fromList)])
        }
    }

    @Test func groupSubpagesAreBoundToTheirGroup() async {
        let (social, _) = await makeSocial()
        let navigator = social.navigator

        navigator.open(.group(groupID))
        navigator.open(.groupCalendar(groupID))
        navigator.openChat(.group(id: groupID, name: "Smoking red"))
        // Eine andere Gruppe ist eine andere Seite – sie wird aufgelegt, nicht mit der ersten verwechselt.
        navigator.open(.group(otherGroupID))
        navigator.openChat(.group(id: otherGroupID, name: "Klasse 8b"))
        #expect(navigator.path.count == 5)

        // Zurück zum Kalender der ersten Gruppe: alles darüber schließt sich.
        navigator.open(.groupCalendar(groupID))
        #expect(navigator.path == [.route(.group(groupID)), .route(.groupCalendar(groupID))])
    }

    @Test func repeatedTapsDoNotStackTheSamePage() async {
        let (social, _) = await makeSocial()
        let navigator = social.navigator

        for _ in 0..<5 {
            navigator.open(.group(groupID))
        }
        for _ in 0..<5 {
            navigator.openChat(.group(id: groupID, name: "Smoking red"))
        }
        for _ in 0..<5 {
            navigator.open(.groupMembers(groupID))
        }
        #expect(navigator.path.count == 3)
    }

    @Test func profileAndDirectChatDoNotLoop() async {
        let (social, _) = await makeSocial()
        let navigator = social.navigator
        let mia = ChatFixtures.mia
        let renamed = SocialProfile(publicID: mia.publicID, username: mia.username, displayName: mia.displayName, nickname: "Mimi")

        navigator.open(.profile(mia))
        for _ in 0..<20 {
            navigator.openChat(.direct(mia))
            // Info im Privatchat (Spitzname inzwischen geändert) und `.friend` zeigen dieselbe Profilseite.
            navigator.open(.friend(renamed))
        }
        #expect(navigator.path == [.route(.profile(mia))])

        // Derselbe Privatchat über die Chatliste und über das Profil: keine zweite Ebene.
        navigator.openChat(.conversation(id: directConversationID, kind: .direct, title: "Mia"))
        navigator.openChat(.direct(mia))
        #expect(navigator.path == [.route(.profile(mia)), .chat(.conversation(id: directConversationID, kind: .direct, title: "Mia"))])
    }

    @Test func replacingAndExternalEntriesStayPredictable() async {
        let (social, _) = await makeSocial()
        let navigator = social.navigator

        // „Gruppe erstellen“ wird durch die neue Gruppe ersetzt.
        navigator.open(.createGroup)
        navigator.replaceTop(with: .group(groupID))
        #expect(navigator.path == [.route(.group(groupID))])

        // „Profil teilen“ an einen Chat, der schon darunter offen ist: zurück zu ihm statt eines zweiten.
        navigator.popToRoot()
        navigator.openChat(.direct(ChatFixtures.mia))
        navigator.open(.profile(ChatFixtures.leon))
        navigator.open(.shareProfile(ChatFixtures.leon))
        navigator.replaceTop(withChat: .conversation(id: directConversationID, kind: .direct, title: "Mia"))
        #expect(navigator.path == [.chat(.direct(ChatFixtures.mia))])

        // Home-Widget bzw. Link: genau die Gruppe über der Hauptseite, egal was vorher offen war.
        navigator.open(.group(otherGroupID))
        navigator.show(.group(groupID))
        #expect(navigator.path == [.route(.group(groupID))])
        navigator.show(.group(groupID))
        #expect(navigator.path == [.route(.group(groupID))])
    }

    @Test func requestedGroupFromHomeOpensItOnce() async {
        let (social, _) = await makeSocial()
        social.navigator.openChat(.group(id: otherGroupID, name: "Klasse 8b"))

        social.showGroup(groupID)
        // Was `SocialView` bei `requestedGroup` tut.
        if let requested = social.requestedGroup {
            social.clearRequestedGroup()
            social.navigator.show(.group(requested))
        }

        #expect(social.requestedGroup == nil)
        #expect(social.navigator.path == [.route(.group(groupID))])
    }

    // MARK: Ressourcen

    /// Wie im `NavigationStack`: Nur die oberste Seite ist sichtbar und hält ihren Chat per `observe()` aktuell;
    /// verdeckte oder geschlossene Seiten beenden ihre Aufgabe. Nach 50 Wechseln ist höchstens ein Echtzeit-Abo offen
    /// und es gibt genau ein ViewModel je Chat bzw. Gruppe.
    @Test func roundTripsDoNotMultiplySubscriptionsOrViewModels() async throws {
        let (social, repository) = await makeSocial()
        let navigator = social.navigator
        var visible: (item: SocialPathItem, task: Task<Void, Never>)?

        func settle() async throws {
            let top = navigator.path.last
            if visible?.item != top {
                if let visible {
                    visible.task.cancel()
                    await visible.task.value
                }
                visible = nil
                if case .chat(let target) = top {
                    let chat = social.chats.chat(for: target)
                    visible = (top!, Task { await chat.observe() })
                    try await waitUntil { repository.liveSubscriberCount(conversationID: groupConversationID) == 1 }
                } else if let top {
                    visible = (top, Task {})
                }
            }
            #expect(repository.liveSubscriberCount(conversationID: groupConversationID) <= 1)
        }

        navigator.open(.group(groupID))
        try await settle()
        for _ in 0..<50 {
            navigator.openChat(.group(id: groupID, name: "Smoking red"))
            try await settle()
            navigator.open(.group(groupID))
            try await settle()
        }
        navigator.popToRoot()
        try await settle()

        #expect(repository.liveSubscriberCount(conversationID: groupConversationID) == 0)
        #expect(social.chats.cachedChatCount == 1)
        #expect(social.detail(groupID: groupID) === social.detail(groupID: groupID))
    }
}

/// Speicher: Geschlossene Chats werden nach dem Prinzip „am längsten unbenutzt zuerst“ freigegeben; offene, im Pfad
/// liegende und Chats mit Entwurf bleiben.
@MainActor
struct ChatCacheTrimmingTests {
    private func makeChats(_ count: Int) async -> (ChatListViewModel, SocialViewModel, [ConversationSummary]) {
        let conversations = (0..<count).map { index in
            ChatFixtures.group(id: UUID(), groupID: UUID(), title: "Gruppe \(index)")
        }
        let repository = ChatRepositoryStub { $0.conversations = conversations }
        let chats = ChatListViewModel(
            repository: repository, media: nil, calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) }, sleep: { try await ManualTicker().sleep($0) }
        )
        await chats.load()
        let social = SocialViewModel(repository: SocialRepositoryStub(), chats: chats, calendar: Fixtures.activityCalendar)
        return (chats, social, conversations)
    }

    /// Wie die Ziel-Ansicht im `NavigationStack`: Chat öffnen erzeugt bzw. holt sein ViewModel.
    private func open(_ conversation: ConversationSummary, in social: SocialViewModel) -> ChatViewModel {
        social.navigator.openChat(ChatTarget(conversation))
        return social.chats.chat(for: ChatTarget(conversation))
    }

    @Test func oldestIdleChatsAreReleasedFirst() async {
        let (chats, social, conversations) = await makeChats(14)
        var models: [ChatViewModel] = []
        for conversation in conversations {
            models.append(open(conversation, in: social))
            social.navigator.popToRoot()
        }
        // Höchstens 8 nicht offene Chats bleiben – die zuletzt benutzten.
        #expect(chats.cachedChatCount == ChatListViewModel.maximumIdleChats)
        #expect(chats.chat(for: ChatTarget(conversations[13])) === models[13])
        #expect(chats.chat(for: ChatTarget(conversations[6])) === models[6])
        // Der älteste wurde freigegeben und kommt beim nächsten Öffnen neu.
        #expect(chats.chat(for: ChatTarget(conversations[0])) !== models[0])
    }

    @Test func draftsAndChatsInThePathStay() async {
        let (chats, social, conversations) = await makeChats(14)
        let navigator = social.navigator
        let draft = chats.chat(for: ChatTarget(conversations[0]))
        draft.draftText = "Bis gleich"
        // Chat 1 liegt verdeckt im Pfad (darüber ein Profil).
        let covered = open(conversations[1], in: social)
        navigator.open(.profile(ChatFixtures.mia))
        for conversation in conversations.dropFirst(2) {
            _ = open(conversation, in: social)
            navigator.open(.profile(ChatFixtures.mia)) // geht zurück zum Profil, der Chat darüber schließt sich
        }
        #expect(chats.chat(for: ChatTarget(conversations[0])) === draft)
        #expect(chats.chat(for: ChatTarget(conversations[1])) === covered)
        #expect(chats.cachedChatCount <= ChatListViewModel.maximumIdleChats + 2)
    }

    @Test func theBackGestureAlsoReleasesChats() async {
        let (chats, social, conversations) = await makeChats(12)
        let navigator = social.navigator
        for conversation in conversations.prefix(11) {
            _ = open(conversation, in: social)
            // Zurück-Geste des Systems: schreibt den Pfad direkt.
            navigator.path.removeLast()
        }
        #expect(chats.cachedChatCount == ChatListViewModel.maximumIdleChats)
    }

    @Test func aDuplicateViewModelNeverReplacesTheOpenOne() async {
        let (chats, _, conversations) = await makeChats(1)
        let group = conversations[0]
        // Früh über die Gruppe geöffnet (noch ohne geladene Unterhaltung) und später über die Liste.
        let fromList = chats.chat(for: ChatTarget(group))
        let first = chats.chat(for: ChatTarget(group))
        let again = chats.chat(for: ChatTarget(group))
        #expect(first === fromList)
        #expect(again === fromList)
    }
}

/// Abschlüsse nach dem Warten auf den Server wirken nur auf ihre eigene Seite; Verlassen einer Gruppe schließt nur deren
/// Seiten.
@MainActor
struct SocialNavigatorCompletionTests {
    private let groupID = UUID(uuidString: "a5000000-0000-4000-8000-000000000001")!
    private let otherGroupID = UUID(uuidString: "a5000000-0000-4000-8000-000000000002")!

    @Test func replaceOnlyActsWhenItsPageIsStillOnTop() {
        let navigator = SocialNavigator()
        navigator.open(.groups)
        navigator.open(.createGroup)
        navigator.replace(.createGroup, with: .group(groupID))
        #expect(navigator.path == [.route(.groups), .route(.group(groupID))])

        // Inzwischen zurückgegangen: Die neue Gruppe wird geöffnet, „Meine Gruppen“ bleibt.
        navigator.popToRoot()
        navigator.open(.groups)
        navigator.open(.createGroup)
        navigator.path.removeLast()
        navigator.replace(.createGroup, with: .group(otherGroupID))
        #expect(navigator.path == [.route(.groups), .route(.group(otherGroupID))])

        navigator.popToRoot()
        navigator.open(.profile(ChatFixtures.leon))
        navigator.open(.shareProfile(ChatFixtures.leon))
        navigator.replace(.shareProfile(ChatFixtures.leon), withChat: .direct(ChatFixtures.mia))
        #expect(navigator.path == [.route(.profile(ChatFixtures.leon)), .chat(.direct(ChatFixtures.mia))])
    }

    @Test func leavingAGroupClosesOnlyItsPages() {
        let navigator = SocialNavigator()
        navigator.open(.group(otherGroupID))
        navigator.open(.profile(ChatFixtures.mia))
        navigator.open(.group(groupID))
        navigator.openChat(.group(id: groupID, name: "Smoking red"))
        navigator.open(.groupSettings(groupID))

        navigator.closeGroup(groupID)

        #expect(navigator.path == [.route(.group(otherGroupID)), .route(.profile(ChatFixtures.mia))])
    }
}

/// Mediendaten je Chat: nach Bytes begrenzt, älteste zuerst entfernt.
struct ChatMediaDataCacheTests {
    @Test func oldestEntriesLeaveFirst() {
        var cache = ChatMediaDataCache(byteLimit: 10)
        cache["a"] = Data(count: 4)
        cache["b"] = Data(count: 4)
        cache["c"] = Data(count: 4)
        #expect(cache["a"] == nil)
        #expect(cache["b"]?.count == 4)
        #expect(cache["c"]?.count == 4)
        #expect(cache.totalBytes == 8)
        // Ein großer Eintrag bleibt allein erhalten.
        cache["big"] = Data(count: 20)
        #expect(cache.count == 1)
        #expect(cache["big"]?.count == 20)
        cache["big"] = nil
        #expect(cache.totalBytes == 0)
    }
}
