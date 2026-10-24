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
