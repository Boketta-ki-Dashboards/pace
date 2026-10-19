import Foundation
import PaceBackend
import PaceCore
import Testing

/// Zwei (und mehr) echte Nutzer gegen den lokalen Stack, über genau die Schicht, die auch die App verwendet:
/// Präfixsuche, Freundschaft, Privatchat, Gruppe mit Einladung, Gruppenchat, Gruppen-Streak, Austritt, Blockieren
/// (Migrationen ab 20261019100000). Jeder Test legt eigene Nutzer an und hängt nicht von anderen Läufen ab.
@Suite(.enabled(if: IntegrationEnvironment.configuration != nil, "PACE_SUPABASE_URL/PACE_SUPABASE_PUBLISHABLE_KEY fehlen"))
struct CommunityIntegrationTests {
    @Test func twoUsersFromFriendRequestToBlocking() async throws {
        let anna = try await IntegrationUser.make("Anna", steps: 9_000)
        let ben = try await IntegrationUser.make("Ben", steps: 4_000)

        // 1. Ben findet Anna über die Präfixsuche (eindeutiger Anfang des Benutzernamens).
        let hits = try await ben.social.searchProfiles(query: String(anna.username.dropLast(2)))
        let annaHit = try #require(hits.first { $0.profile.publicID == anna.publicID })
        #expect(annaHit.relationship == .none)
        #expect(annaHit.profile.displayName == "Anna")

        // 2. Anfrage → Anna sieht sie → nimmt an.
        #expect(try await ben.social.sendFriendRequest(to: anna.publicID) == .requested)
        let request = try #require(try await anna.social.friendRequests().first { $0.direction == .incoming })
        #expect(request.profile.publicID == ben.publicID)
        try await anna.social.respondToFriendRequest(request.id, accept: true)

        // 3. Status bei beiden: Freunde, Schritte sichtbar.
        #expect(try await anna.social.friends().map(\.profile.publicID) == [ben.publicID])
        #expect(try await ben.social.friends().map(\.profile.publicID) == [anna.publicID])
        let annaSeenByBen = try await ben.social.publicProfile(anna.publicID, date: IntegrationUser.today)
        #expect(annaSeenByBen.relationship == .friend)
        #expect(annaSeenByBen.stepsToday == 9_000)
        #expect(annaSeenByBen.friendsSince != nil)
        #expect(!annaSeenByBen.isBlockedByMe)

        // 4. Privatchat: Anna schreibt, Ben empfängt (ungelesen), antwortet; Verlauf aufsteigend bei beiden.
        let direct = try await anna.chat.openDirectConversation(with: ben.publicID)
        #expect(direct.kind == .direct)
        #expect(direct.peer?.publicID == ben.publicID)
        #expect(direct.canSend)
        let hello = ChatMessageDraft.text("Hallo Ben! 👋")
        let sent = try await anna.chat.send(hello, to: direct.id)
        #expect(sent.isOwn)
        #expect(sent.text == "Hallo Ben! 👋")
        // Wiederholen mit derselben client_id legt keine zweite Nachricht an.
        #expect(try await anna.chat.send(hello, to: direct.id).id == sent.id)

        let bensList = try await ben.chat.conversations()
        let bensDirect = try #require(bensList.first { $0.id == direct.id })
        #expect(bensDirect.unreadCount == 1)
        #expect(bensDirect.peer?.publicID == anna.publicID)
        #expect(bensDirect.lastMessage?.text == "Hallo Ben! 👋")
        #expect(bensDirect.lastMessage?.isOwn == false)
        #expect(try await ben.chat.openDirectConversation(with: anna.publicID).id == direct.id)

        let received = try await ben.chat.messages(in: direct.id, before: nil, limit: 40)
        #expect(received.map(\.id) == [sent.id])
        #expect(received.first?.sender?.publicID == anna.publicID)
        #expect(received.first?.isOwn == false)
        let reply = try await ben.chat.send(.text("Hi Anna, bin dabei."), to: direct.id)
        try await ben.chat.markRead(direct.id, through: reply.sentAt)
        #expect(try await ben.chat.conversations().first { $0.id == direct.id }?.unreadCount == 0)

        let history = try await anna.chat.messages(in: direct.id, before: nil, limit: 40)
        #expect(history.map(\.text) == ["Hallo Ben! 👋", "Hi Anna, bin dabei."])
        #expect(history.map(\.isOwn) == [true, false])
        // Pagination: ältere Nachrichten vor der Antwort.
        #expect(try await anna.chat.messages(in: direct.id, before: reply.sentAt, limit: 40).map(\.id) == [sent.id])
        // Fremde Nachrichten lassen sich nicht löschen.
        await #expect(throws: SocialError.notFound) {
            try await anna.chat.deleteMessage(reply.id)
        }

        // 5. Gruppe nur mit Einladung: Code-Beitritt geht nicht, die Einladung schon.
        let group = try await anna.social.createGroup(
            GroupDraft(name: "Abendrunde", description: "Jeden Tag ein Stück", kind: .friends, dailyGoal: 8_000,
                       privacy: .inviteOnly, inviteePublicIDs: [ben.publicID]),
            timeZone: "Europe/Berlin"
        )
        #expect(group.privacy == .inviteOnly)
        #expect(try await anna.social.outgoingInvitations(for: group.id).map(\.profile.publicID) == [ben.publicID])
        await #expect(throws: SocialError.invalidInviteCode) {
            try await ben.social.joinGroup(inviteCode: group.inviteCode)
        }
        let invitation = try #require(try await ben.social.groupInvitations().first { $0.groupID == group.id })
        let joined = try #require(try await ben.social.respondToInvitation(invitation.id, accept: true))
        #expect(joined.memberCount == 2)
        #expect(joined.role == .member)

        // 6. Gruppenchat: beide schreiben und lesen dieselbe Unterhaltung.
        let groupChat = try await anna.chat.groupConversation(for: group.id)
        #expect(groupChat.kind == .group)
        #expect(groupChat.groupID == group.id)
        #expect(groupChat.memberCount == 2)
        #expect(try await ben.chat.groupConversation(for: group.id).id == groupChat.id)
        _ = try await anna.chat.send(.text("Willkommen in der Abendrunde!"), to: groupChat.id)
        _ = try await ben.chat.send(.text("Danke!"), to: groupChat.id)
        #expect(try await ben.chat.messages(in: groupChat.id, before: nil, limit: 40).map(\.text)
            == ["Willkommen in der Abendrunde!", "Danke!"])

        // 7. Gruppen-Streak: 2 Mitglieder → ceil(2/3) = 1 nötig; Anna (9.000 ≥ 8.000) sichert die Flamme.
        let annasView = try await anna.social.group(group.id)
        let bensView = try await ben.social.group(group.id)
        #expect(annasView.todayRequiredCount == GroupStreakRules.requiredMembers(forMemberCount: 2))
        #expect(annasView.todayReachedCount == 1)
        #expect(annasView.todayComplete)
        #expect(annasView.currentStreak == 1)
        #expect(bensView.todayRequiredCount == annasView.todayRequiredCount)
        #expect(bensView.todayReachedCount == annasView.todayReachedCount)
        #expect(bensView.currentStreak == annasView.currentStreak)
        let ranking = try await ben.social.groupRanking(group.id, period: .daily)
        #expect(ranking.entries.map(\.profile.publicID) == [anna.publicID, ben.publicID])
        #expect(ranking.entries.filter(\.reachedGoalToday).count == annasView.todayReachedCount)
        #expect(ranking.dailyGoal == 8_000)
        let today = try #require(try await ben.social.groupDays(group.id, count: 7).first)
        #expect(today.isToday)
        #expect(today.memberCount == 2)
        #expect(today.requiredCount == 1)
        #expect(today.reachedCount == 1)
        #expect(today.reached)

        // 8. Austritt entzieht den Zugriff auf Gruppe und Gruppenchat.
        try await ben.social.leaveGroup(group.id)
        await #expect(throws: SocialError.notFound) {
            try await ben.chat.messages(in: groupChat.id, before: nil, limit: 40)
        }
        await #expect(throws: SocialError.notFound) {
            try await ben.chat.groupConversation(for: group.id)
        }
        await #expect(throws: (any Error).self) {
            try await ben.chat.send(.text("Noch da?"), to: groupChat.id)
        }
        #expect(try await !ben.chat.conversations().contains { $0.id == groupChat.id })
        #expect(try await anna.social.group(group.id).memberCount == 1)

        // 9. Blockieren beendet die Freundschaft; danach weder Anfragen noch Nachrichten noch Suche.
        try await anna.social.block(ben.publicID)
        #expect(try await anna.social.blockedUsers().map(\.publicID) == [ben.publicID])
        #expect(try await anna.social.friends().isEmpty)
        #expect(try await ben.social.friends().isEmpty)
        #expect(try await anna.social.publicProfile(ben.publicID, date: IntegrationUser.today).isBlockedByMe)
        // Der Privatchat ist für beide nicht mehr sichtbar, Schreiben geht in keine Richtung.
        await #expect(throws: SocialError.notFound) {
            try await ben.chat.send(.text("Hallo?"), to: direct.id)
        }
        await #expect(throws: SocialError.notFound) {
            try await anna.chat.send(.text("Tschüss"), to: direct.id)
        }
        await #expect(throws: SocialError.notFound) {
            try await ben.chat.messages(in: direct.id, before: nil, limit: 40)
        }
        #expect(try await !ben.chat.conversations().contains { $0.id == direct.id })
        #expect(try await !anna.chat.conversations().contains { $0.id == direct.id })
        await #expect(throws: SocialError.blocked) {
            try await anna.chat.openDirectConversation(with: ben.publicID)
        }
        await #expect(throws: (any Error).self) {
            _ = try await ben.social.sendFriendRequest(to: anna.publicID)
        }
        #expect(try await ben.social.searchProfiles(query: anna.username).isEmpty)
        #expect(try await anna.social.searchProfiles(query: ben.username).isEmpty)
        #expect(try await ben.social.findProfile(username: anna.username) == nil)

        // Aufheben: wieder auffindbar, nicht automatisch befreundet; der alte Verlauf ist lesbar, aber schreibgeschützt.
        try await anna.social.unblock(ben.publicID)
        #expect(try await anna.social.blockedUsers().isEmpty)
        #expect(try await ben.social.findProfile(username: anna.username)?.relationship == SocialRelationship.none)
        #expect(try await ben.chat.conversations().first { $0.id == direct.id }?.canSend == false)
        await #expect(throws: SocialError.readOnly) {
            try await ben.chat.send(.text("Hallo?"), to: direct.id)
        }
    }

    @Test func prefixSearchHonoursDiscoverabilityAndEscapesWildcards() async throws {
        let stem = "sr\(UUID().uuidString.prefix(6).lowercased())"
        let searcher = try await IntegrationUser.make("Sucher", steps: 0)
        let first = try await IntegrationUser.make("Erste", steps: 0, username: "\(stem)_eins")
        let second = try await IntegrationUser.make("Zweite", steps: 0, username: "\(stem)_zwei")

        let both = try await searcher.social.searchProfiles(query: stem.uppercased())
        #expect(Set(both.map(\.profile.publicID)) == [first.publicID, second.publicID])
        #expect(both.allSatisfy { $0.relationship == .none })
        #expect(try await searcher.social.searchProfiles(query: "@\(stem)_z").map(\.profile.publicID) == [second.publicID])
        // Zu kurze Anfragen und LIKE-Platzhalter liefern keine beliebigen Treffer.
        #expect(try await searcher.social.searchProfiles(query: "s").isEmpty)
        #expect(try await searcher.social.searchProfiles(query: "%%%").isEmpty)
        #expect(try await searcher.social.searchProfiles(query: "\(stem)%").isEmpty)
        // Man findet sich selbst nicht.
        #expect(try await first.social.searchProfiles(query: stem).map(\.profile.publicID) == [second.publicID])

        // Nicht auffindbar: Fremde finden das Profil nicht mehr über einen Anfang, nur mit dem genauen Benutzernamen
        // (Vertrag von UserProfile.isDiscoverable) …
        let hidden = try await second.profiles.updateDiscoverable(false, for: second.session.userID)
        #expect(!hidden.isDiscoverable)
        #expect(try await searcher.social.searchProfiles(query: stem).map(\.profile.publicID) == [first.publicID])
        #expect(try await searcher.social.searchProfiles(query: second.username).map(\.profile.publicID) == [second.publicID])
        #expect(try await searcher.social.findProfile(username: second.username)?.profile.publicID == second.publicID)

        // … Freunde dagegen auch über den Anfang.
        #expect(try await second.social.sendFriendRequest(to: first.publicID) == .requested)
        let request = try #require(try await first.social.friendRequests().first)
        try await first.social.respondToFriendRequest(request.id, accept: true)
        let friendHits = try await first.social.searchProfiles(query: stem)
        #expect(friendHits.map(\.profile.publicID) == [second.publicID])
        #expect(friendHits.first?.relationship == .friend)

        // Namen ändern über die Spalten-Grants (Constraints greifen).
        let renamed = try await first.profiles.updateNames(username: "\(stem)_neu", displayName: "  Erste   Neu ", for: first.session.userID)
        #expect(renamed.username == "\(stem)_neu")
        #expect(renamed.displayName == "Erste Neu")
        await #expect(throws: ProfileError.usernameTaken) {
            try await searcher.profiles.updateNames(username: "\(stem)_NEU", displayName: nil, for: searcher.session.userID)
        }
    }

    @Test func reportsOnlyForVisibleTargets() async throws {
        let reporter = try await IntegrationUser.make("Melderin", steps: 0)
        let target = try await IntegrationUser.make("Gemeldet", steps: 0)
        let outsider = try await IntegrationUser.make("Aussen", steps: 0)
        try await reporter.befriend(target)

        try await reporter.social.report(.user(publicID: target.publicID), reason: .harassment, details: "Beleidigt mich im Chat.")
        // Eine offene Meldung je Ziel: erneutes Melden ist unschädlich.
        try await reporter.social.report(.user(publicID: target.publicID), reason: .spam, details: nil)

        let direct = try await target.chat.openDirectConversation(with: reporter.publicID)
        let message = try await target.chat.send(.text("Das ist Spam."), to: direct.id)
        try await reporter.social.report(.message(id: message.id), reason: .spam, details: nil)
        // Eigene Nachrichten und Nachrichten fremder Unterhaltungen lassen sich nicht melden.
        await #expect(throws: SocialError.notFound) {
            try await target.social.report(.message(id: message.id), reason: .spam, details: nil)
        }
        await #expect(throws: SocialError.notFound) {
            try await outsider.social.report(.message(id: message.id), reason: .spam, details: nil)
        }

        let group = try await target.social.createGroup(GroupDraft(name: "Geheimrunde"), timeZone: "Europe/Berlin")
        await #expect(throws: SocialError.notFound) {
            try await outsider.social.report(.group(id: group.id), reason: .inappropriate, details: nil)
        }
        _ = try await target.social.invite(reporter.publicID, to: group.id)
        // Eingeladene dürfen melden, auch ohne beizutreten.
        try await reporter.social.report(.group(id: group.id), reason: .inappropriate, details: nil)

        await #expect(throws: SocialError.notFound) {
            try await reporter.social.report(.user(publicID: reporter.publicID), reason: .other, details: nil)
        }
        await #expect(throws: SocialError.invalidInput) {
            try await reporter.social.report(.user(publicID: outsider.publicID), reason: .other, details: String(repeating: "x", count: 1_001))
        }
    }

    @Test func usernameAvailabilityIsRateLimited() async throws {
        let backend = SupabaseBackend(configuration: try #require(IntegrationEnvironment.configuration), localStorage: InMemoryAuthStorage())
        // Noch ohne Profil (wie im Onboarding): das Limit hängt am Auth-Nutzer.
        _ = try await backend.auth.signInAnonymously()
        for index in 0..<60 {
            _ = try await backend.profiles.isUsernameAvailable("frei_\(index)_\(UUID().uuidString.prefix(4))")
        }
        await #expect(throws: ProfileError.rateLimited) {
            try await backend.profiles.isUsernameAvailable("einer_zu_viel")
        }
    }

    /// Unter Linux steckt hinter URLSessionWebSocketTask libcurl, das dort ohne WebSocket-Unterstützung gebaut ist.
    /// Die Echtzeit-Kanäle prüft dann `supabase/scripts/realtime_smoke_test.mjs` gegen denselben Stack (auch in der CI).
    @Test(.enabled(if: IntegrationEnvironment.supportsWebSockets, "WebSockets sind unter Linux (libcurl) nicht verfügbar"))
    func newChatMessagesArriveOverRealtime() async throws {
        let anna = try await IntegrationUser.make("Echt", steps: 0)
        let ben = try await IntegrationUser.make("Zeit", steps: 0)
        try await anna.befriend(ben)
        let direct = try await anna.chat.openDirectConversation(with: ben.publicID)

        // Ben hört auf den Kanal der Unterhaltung und auf seinen eigenen; Anna schreibt, bis ein Hinweis ankommt.
        let annaChat = anna.chat
        let messageHint = await IntegrationUser.receivesEvent(ben.chat.messageEvents(in: direct.id), within: .seconds(20)) {
            _ = try await annaChat.send(.text("Ping"), to: direct.id)
        }
        #expect(messageHint)
        let conversationHint = await IntegrationUser.receivesEvent(ben.chat.conversationEvents(), within: .seconds(20)) {
            _ = try await annaChat.send(.text("Noch ein Ping"), to: direct.id)
        }
        #expect(conversationHint)

        // Fremde dürfen den Kanal nicht abonnieren: Der Stream endet ohne Hinweis.
        let outsider = try await IntegrationUser.make("Lauscher", steps: 0)
        let eavesdropped = await IntegrationUser.receivesEvent(outsider.chat.messageEvents(in: direct.id), within: .seconds(6)) {
            _ = try await annaChat.send(.text("Privat"), to: direct.id)
        }
        #expect(!eavesdropped)
    }
}

// MARK: - Nutzer für Integrationstests

extension IntegrationEnvironment {
    /// Ob der Swift-Client hier WebSockets öffnen kann (Apple-Plattformen ja, Linux nein).
    static var supportsWebSockets: Bool {
        #if canImport(FoundationNetworking)
        false
        #else
        true
        #endif
    }
}

/// Neuer anonymer Nutzer mit eigenem Sitzungsspeicher (wie ein eigenes Gerät), Profil und heutigen Schritten.
struct IntegrationUser {
    let backend: SupabaseBackend
    let session: AuthSession
    let username: String
    let displayName: String
    let publicID: UUID

    var social: any SocialRepository { backend.social }
    var chat: any ChatRepository { backend.chat }
    var media: any MediaRepository { backend.media }
    var account: any AccountRepository { backend.account }
    var profiles: any ProfileRepository { backend.profiles }

    /// Lokaler Kalendertag in Berlin, wie ihn die App für Sync und Gruppen verwendet.
    static var today: LocalDate {
        ActivityCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!).day(containing: Date())
    }

    static func make(_ displayName: String, steps: Int, username: String? = nil) async throws -> IntegrationUser {
        let backend = SupabaseBackend(configuration: try #require(IntegrationEnvironment.configuration), localStorage: InMemoryAuthStorage())
        let session = try await backend.auth.signInAnonymously()
        let name = username ?? "\(displayName)_\(UUID().uuidString.prefix(8))".replacingOccurrences(of: "-", with: "")
        let profile = try await backend.profiles.createProfile(NewProfile(username: name, displayName: displayName), for: session.userID)
        if steps > 0 {
            try await backend.activitySync.upsert([DailyCompetitionSteps(date: today, competitionSteps: steps)], for: session.userID)
        }
        return IntegrationUser(backend: backend, session: session, username: profile.username, displayName: displayName, publicID: profile.publicID)
    }

    /// Anfrage senden und von der anderen Seite annehmen lassen.
    func befriend(_ other: IntegrationUser) async throws {
        #expect(try await social.sendFriendRequest(to: other.publicID) == .requested)
        let request = try #require(try await other.social.friendRequests().first { $0.profile.publicID == publicID })
        try await other.social.respondToFriendRequest(request.id, accept: true)
    }

    /// `true`, sobald `stream` innerhalb von `timeout` einen Hinweis liefert. `trigger` läuft währenddessen wiederholt
    /// (der Beitritt zum Kanal dauert einen Moment, ein zu früher Hinweis ginge sonst verloren).
    static func receivesEvent(
        _ stream: AsyncStream<Void>,
        within timeout: Duration,
        trigger: @escaping @Sendable () async throws -> Void
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream {
                    return true
                }
                return false
            }
            group.addTask {
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: timeout)
                while clock.now < deadline, !Task.isCancelled {
                    try? await trigger()
                    try? await Task.sleep(for: .milliseconds(800))
                }
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
