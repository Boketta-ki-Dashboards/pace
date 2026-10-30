import Foundation
import PaceCore
import Testing

/// Willkommensmitteilung (Auftrag 6, Teil C 13): genau einmal je Profil, gelesen, löschen ohne Wiederkehr.
@MainActor
struct SystemMessageCenterTests {
    private let owner = "11111111-2222-3333-4444-555555555555"

    @Test func welcomeIsCreatedExactlyOnce() {
        let store = InMemorySystemMessageStore()
        let center = SystemMessageCenter(store: store, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        center.activate(owner: owner)
        #expect(center.messages.map(\.kind) == [.welcome])
        #expect(center.unreadCount == 1)
        // Erneuter Start, Tabwechsel, neue Schritte: keine zweite Kopie.
        center.activate(owner: owner)
        let restarted = SystemMessageCenter(store: store)
        restarted.activate(owner: owner)
        #expect(restarted.messages.count == 1)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(restarted.messages.first?.title == "Willkommen bei Pace! 👋")
            #expect(restarted.messages.first?.sender == "Pace Team")
        }
    }

    @Test func openingMarksReadAndDeletingNeverBringsItBack() {
        let store = InMemorySystemMessageStore()
        let center = SystemMessageCenter(store: store)
        center.activate(owner: owner)
        center.markRead(.welcome)
        #expect(center.unreadCount == 0)
        #expect(center.message(.welcome)?.isRead == true)
        // Nach dem Neustart weiter gelesen.
        let restarted = SystemMessageCenter(store: store)
        restarted.activate(owner: owner)
        #expect(restarted.unreadCount == 0)
        restarted.delete(.welcome)
        #expect(restarted.messages.isEmpty)
        let again = SystemMessageCenter(store: store)
        again.activate(owner: owner)
        #expect(again.messages.isEmpty, "Gelöschte Willkommensmitteilung kommt nicht wieder")
    }

    @Test func existingUsersGetItOnceAndOtherAccountsTheirOwn() {
        // Bestehender Nutzer ohne gespeicherten Stand (Update): einmal zugestellt.
        let store = InMemorySystemMessageStore()
        let center = SystemMessageCenter(store: store)
        center.activate(owner: owner)
        #expect(center.messages.count == 1)
        // Anderes Konto auf dem Gerät: eigene Mitteilung.
        center.activate(owner: "other")
        #expect(center.messages.count == 1)
        #expect(center.unreadCount == 1)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "pace.tests.systemMessages.\(UUID().uuidString)"))
        let store = UserDefaultsSystemMessageStore(defaults: defaults)
        let state = SystemMessageState(delivered: [.welcome], messages: [SystemMessage(kind: .welcome, createdAt: Date(timeIntervalSince1970: 10), readAt: nil)])
        store.save(state, owner: owner)
        #expect(store.load(owner: owner) == state)
        #expect(store.load(owner: "unknown") == SystemMessageState())
    }
}

/// Pace-Bot (Auftrag 6, Teil C 14–18): vorgefertigte Antworten, Stichwörter, ehrliche Antwort bei Unklarem, lokal.
@MainActor
struct PaceHelpBotTests {
    @Test func everyTopicHasAQuestionAndAnswerInAllLanguages() {
        for language in [AppLanguage.german, .english, .russian] {
            PaceLocalization.$languageOverride.withValue(language) {
                for topic in PaceHelpTopic.allCases {
                    #expect(!topic.question.isEmpty && !topic.answer.isEmpty, "\(topic) \(language)")
                }
                #expect(!PaceHelpBot.greeting.isEmpty && !PaceHelpBot.unknownAnswer.isEmpty)
            }
        }
        #expect(PaceHelpTopic.allCases.count == 15)
        // Russische Texte sind nicht die deutschen.
        let german = PaceLocalization.$languageOverride.withValue(.german) { PaceHelpTopic.flame.answer }
        let russian = PaceLocalization.$languageOverride.withValue(.russian) { PaceHelpTopic.flame.answer }
        #expect(german != russian)
    }

    @Test func answersStateTheRealRules() {
        PaceLocalization.$languageOverride.withValue(.german) {
            // Gruppenflamme: ein Drittel, aufgerundet – nicht „alle“.
            #expect(PaceHelpTopic.groupFlame.answer.contains("mindestens ein Drittel"))
            #expect(PaceHelpTopic.groupFlame.answer.contains("aufgerundet"))
            // Rankings nur mit bestätigten Wettbewerbsschritten aus Apple Health.
            #expect(PaceHelpTopic.stepCounting.answer.contains("bestätigte Wettbewerbsschritte"))
            #expect(PaceHelpTopic.stepMismatch.answer.contains("20 Minuten"))
        }
    }

    @Test func keywordsMapOnlyWhenClear() {
        #expect(PaceHelpBot.match("Wie werden Schritte gezählt?") == .stepCounting)
        #expect(PaceHelpBot.match("meine flamme ist weg") == .flame)
        #expect(PaceHelpBot.match("Gruppenflamme") == .groupFlame)
        #expect(PaceHelpBot.match("flamme in der gruppe") == .groupFlame)
        #expect(PaceHelpBot.match("ranking") == .rankings)
        #expect(PaceHelpBot.match("How do I add a friend") == .addFriends)
        #expect(PaceHelpBot.match("как изменить язык") == .languageDesign)
        // Unklar oder unbekannt: keine erfundene Antwort.
        #expect(PaceHelpBot.match("Wetter morgen?") == nil)
        #expect(PaceHelpBot.match("hi") == nil)
    }

    @Test func conversationFlow() {
        let store = InMemoryPaceHelpHistoryStore()
        let session = PaceHelpBotSession(store: store, now: { Date(timeIntervalSince1970: 1) })
        session.start()
        #expect(session.messages.map(\.content) == [.greeting])
        // Erneutes Öffnen: keine zweite Begrüßung.
        session.start()
        #expect(session.messages.count == 1)

        session.ask(.groupFlame)
        #expect(session.messages.suffix(2).map(\.role) == [.user, .bot])
        #expect(session.messages.last?.topic == .groupFlame)

        session.send("Was kostet das Wetter?")
        #expect(session.lastAnswerWasUnknown)
        session.send("   ")
        #expect(session.messages.count == 5, "Leere Eingabe erzeugt nichts")

        // Verlauf bleibt nach Neustart (lokal) und lässt sich zurücksetzen.
        let restarted = PaceHelpBotSession(store: store)
        #expect(restarted.messages.count == 5)
        restarted.reset()
        #expect(restarted.messages.map(\.content) == [.greeting])
        // Sprache wechselt mit: gespeichert sind Themen, nicht Texte.
        restarted.ask(.flame)
        let english = PaceLocalization.$languageOverride.withValue(.english) { restarted.messages.last?.text }
        #expect(english == PaceLocalization.$languageOverride.withValue(.english) { PaceHelpTopic.flame.answer })
    }

    @Test func historyIsBounded() {
        let session = PaceHelpBotSession()
        session.start()
        for _ in 0..<50 { session.ask(.rankings) }
        #expect(session.messages.count == PaceHelpBotSession.historyLimit)
    }

    @Test func supportContactNeverInventsAnAddress() {
        #expect(PaceSupportContact(email: nil).mailURL == nil)
        #expect(PaceSupportContact(email: "").mailURL == nil)
        #expect(PaceSupportContact(email: "$(PACE_SUPPORT_EMAIL)").mailURL == nil)
        #expect(PaceSupportContact.fromInfoDictionary([:]).email == nil)
        let contact = PaceSupportContact(email: "help@example.org")
        let url = contact.mailURL?.absoluteString ?? ""
        #expect(url.hasPrefix("mailto:help@example.org?subject="))
        // Die Vorlage enthält nur Text zum Bearbeiten – keine Kennungen oder Gesundheitsdaten.
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(PaceSupportContact.subject == "Pace – Supportanfrage")
            #expect(PaceSupportContact.bodyTemplate.contains("[Hier Problem beschreiben]"))
        }
    }
}
