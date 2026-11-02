import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Pace-Bot als gewöhnlicher Chat (Auftrag 7, Teil B 2): sortiert nach der letzten eigenen Frage, unbenutzt unten,
/// nur echte Nutzerfragen verschieben ihn, keine doppelten Einträge.
@MainActor
struct HelpBotChatListTests {
    private let group = ChatFixtures.group(id: UUID(), groupID: UUID(), title: "Smoking red", updatedAt: Date(timeIntervalSince1970: 1_800_000_200))
    private let direct = ChatFixtures.direct(id: UUID(), updatedAt: Date(timeIntervalSince1970: 1_800_000_100))

    private func list(_ conversations: [ConversationSummary]) async -> ChatListViewModel {
        let list = ChatListViewModel(repository: ChatRepositoryStub { $0.conversations = conversations }, media: nil)
        await list.load()
        return list
    }

    private func names(_ entries: [ChatListViewModel.ListEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .conversation(let conversation): conversation.title
            case .helpBot: "bot"
            }
        }
    }

    @Test func unusedBotStaysAtTheEndAndOnlyRealQuestionsMoveIt() async {
        let list = await list([direct, group])
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let session = PaceHelpBotSession(now: { [clock] in clock })
        // Begrüßung (Öffnen) ist keine Aktivität.
        session.start()
        #expect(session.lastUserActivity == nil)
        #expect(names(list.entries(showsHelpBot: true, helpBotActivity: session.lastUserActivity)).last == "bot")

        // Eigene Frage nach allen Chats: Der Bot steigt nach oben.
        clock = Date(timeIntervalSince1970: 1_800_000_300)
        let asking = PaceHelpBotSession(now: { [clock] in clock })
        asking.ask(.groupFlame)
        #expect(names(list.entries(showsHelpBot: true, helpBotActivity: asking.lastUserActivity)).first == "bot")

        // Eigene Frage zwischen den beiden Chats: genau dazwischen.
        let between = Date(timeIntervalSince1970: 1_800_000_150)
        #expect(names(list.entries(showsHelpBot: true, helpBotActivity: between)) == ["Smoking red", "bot", direct.title])
    }

    @Test func newChatMessageMovesTheChatAboveTheBot() async {
        let botActivity = Date(timeIntervalSince1970: 1_800_000_300)
        let before = await list([direct, group])
        #expect(names(before.entries(showsHelpBot: true, helpBotActivity: botActivity)).first == "bot")
        // Neue Nachricht im Gruppenchat (später als die letzte Bot-Frage).
        let newer = ChatFixtures.group(id: group.id, groupID: UUID(), title: "Smoking red", updatedAt: Date(timeIntervalSince1970: 1_800_000_400))
        let after = await list([direct, newer])
        #expect(names(after.entries(showsHelpBot: true, helpBotActivity: botActivity)) == ["Smoking red", "bot", direct.title])
    }

    @Test func botOnlyUnderAllExactlyOnceAndWithoutUnread() async {
        let list = await list([direct, group])
        let all = list.entries(showsHelpBot: true, helpBotActivity: nil)
        #expect(all.filter { $0 == .helpBot }.count == 1)
        list.filter = .friends
        #expect(!list.entries(showsHelpBot: true, helpBotActivity: nil).contains(.helpBot))
        list.filter = .groups
        #expect(!list.entries(showsHelpBot: true, helpBotActivity: nil).contains(.helpBot))
        list.filter = .all
        // Nicht verdrahtet: kein Eintrag. Der Bot zählt nie zu den ungelesenen Nachrichten.
        #expect(!list.entries(showsHelpBot: false, helpBotActivity: nil).contains(.helpBot))
        #expect(list.unreadCount == 0)
        // Ohne Chats: nur der Bot.
        let empty = await self.list([])
        #expect(empty.entries(showsHelpBot: true, helpBotActivity: nil) == [.helpBot])
    }

    @Test func restartLanguageChangeAndResetDoNotFakeActivity() {
        let store = InMemoryPaceHelpHistoryStore()
        let session = PaceHelpBotSession(store: store, now: { Date(timeIntervalSince1970: 1_800_000_500) })
        session.start()
        session.ask(.rankings)
        let asked = session.lastUserActivity
        #expect(asked == Date(timeIntervalSince1970: 1_800_000_500))
        // Neustart (neue Sitzung aus dem Speicher) und erneutes Öffnen ändern nichts.
        let restarted = PaceHelpBotSession(store: store, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        restarted.start()
        #expect(restarted.lastUserActivity == asked)
        // Sprachwechsel: Zeitpunkt und Vorschau folgen der Sprache, die Position nicht.
        let german = PaceLocalization.$languageOverride.withValue(.german) { restarted.listPreview }
        let english = PaceLocalization.$languageOverride.withValue(.english) { restarted.listPreview }
        #expect(german != english)
        #expect(restarted.lastUserActivity == asked)
        // Zurücksetzen: wieder unbenutzt (unten).
        restarted.reset()
        #expect(restarted.lastUserActivity == nil)
        #expect(restarted.listPreview == PaceHelpBot.subtitle)
    }

    @Test func searchFindsTheBot() {
        for query in ["Pace-Bot", "pace bot", "bot", "Hilfe", "help", "бот"] {
            #expect(PaceHelpBot.matchesSearch(query), "\(query)")
        }
        for query in ["Mia", "x", "Smoking red"] {
            #expect(!PaceHelpBot.matchesSearch(query), "\(query)")
        }
    }
}
