import Foundation
import PaceBackend
import PaceCore
import Testing

/// Freunde und Gruppen Ende-zu-Ende über den Swift-Client gegen die echte Datenbank (Migration 20261018100000_social).
@Suite(.enabled(if: IntegrationEnvironment.configuration != nil, "PACE_SUPABASE_URL/PACE_SUPABASE_PUBLISHABLE_KEY fehlen"))
struct SocialIntegrationTests {
    private struct User {
        let backend: SupabaseBackend
        let session: AuthSession
        let username: String
        let displayName: String
    }

    private var today: LocalDate {
        ActivityCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!).day(containing: Date())
    }

    /// Neuer anonymer Nutzer mit Profil und heutigen Schritten.
    private func newUser(_ name: String, steps: Int) async throws -> User {
        let backend = SupabaseBackend(configuration: try #require(IntegrationEnvironment.configuration), localStorage: InMemoryAuthStorage())
        let session = try await backend.auth.signInAnonymously()
        let username = "\(name)_\(UUID().uuidString.prefix(8))".replacingOccurrences(of: "-", with: "")
        _ = try await backend.profiles.createProfile(NewProfile(username: username, displayName: name), for: session.userID)
        try await backend.activitySync.upsert([DailyCompetitionSteps(date: today, competitionSteps: steps)], for: session.userID)
        return User(backend: backend, session: session, username: username, displayName: name)
    }

    @Test func friendshipFlowAndPrivacy() async throws {
        let anna = try await newUser("Anna", steps: 9_000)
        let ben = try await newUser("Ben", steps: 12_000)
        let fremd = try await newUser("Fremd", steps: 50_000)

        // Suche nur mit exaktem Benutzernamen (ohne Groß-/Kleinschreibung).
        let found = try #require(try await anna.backend.social.findProfile(username: ben.username.uppercased()))
        #expect(found.profile.displayName == "Ben")
        #expect(found.relationship == .none)
        #expect(try await anna.backend.social.findProfile(username: String(ben.username.prefix(5))) == nil)
        #expect(try await anna.backend.social.findProfile(username: anna.username)?.relationship == .me)

        // Anfrage → Ben sieht sie → annehmen.
        #expect(try await anna.backend.social.sendFriendRequest(to: found.profile.publicID) == .requested)
        #expect(try await anna.backend.social.sendFriendRequest(to: found.profile.publicID) == .alreadyRequested)
        let incoming = try await ben.backend.social.friendRequests()
        let request = try #require(incoming.first { $0.direction == .incoming })
        #expect(request.profile.username == anna.username)
        // Fremde sehen fremde Anfragen nicht und können sie nicht annehmen.
        #expect(try await fremd.backend.social.friendRequests().isEmpty)
        await #expect(throws: SocialError.notFound) {
            try await fremd.backend.social.respondToFriendRequest(request.id, accept: true)
        }
        try await ben.backend.social.respondToFriendRequest(request.id, accept: true)

        // Freundesranking: beide, sortiert, Fremde nicht enthalten.
        let ranking = try await anna.backend.social.friendRanking(period: .daily, date: today)
        #expect(ranking.map(\.displayName) == ["Ben", "Anna"])
        #expect(ranking.map(\.competitionSteps) == [12_000, 9_000])
        #expect(ranking.first { $0.isCurrentUser }?.rank == 2)
        #expect(!ranking.contains { $0.displayName == "Fremd" })

        let profile = try await anna.backend.social.friendProfile(found.profile.publicID, date: today)
        #expect(profile.stepsToday == 12_000)
        // Schritte von Nicht-Freunden sind nicht abrufbar.
        let fremdProfile = try #require(try await anna.backend.social.findProfile(username: fremd.username))
        await #expect(throws: SocialError.notFound) {
            try await anna.backend.social.friendProfile(fremdProfile.profile.publicID, date: today)
        }

        // Entfernen beendet die Freundschaft auf beiden Seiten.
        try await ben.backend.social.removeFriend(try #require(ranking.first { $0.displayName == "Anna" }).publicUserID)
        #expect(try await anna.backend.social.friends().isEmpty)
    }

    @Test func groupFlowWithInviteCodeAndStreakFields() async throws {
        let owner = try await newUser("Lehrerin", steps: 11_000)
        let student = try await newUser("Schueler", steps: 4_000)
        let outsider = try await newUser("Aussen", steps: 1_000)

        let created = try await owner.backend.social.createGroup(
            GroupDraft(name: "Klasse 8b", description: "Wir laufen!", kind: .schoolClass, dailyGoal: 10_000),
            timeZone: "Europe/Berlin"
        )
        #expect(created.isOwner)
        #expect(created.memberCount == 1)
        #expect(created.dailyGoal == 10_000)
        #expect(created.todayRequiredCount == 1)
        #expect(created.todayComplete) // Eigentümerin hat 11.000 ≥ 10.000
        #expect(created.currentStreak == 1)

        // Beitritt per Code: Normalisierung und falscher Code.
        let spaced = created.inviteCode.prefix(4) + "-" + created.inviteCode.dropFirst(4).lowercased()
        let joined = try await student.backend.social.joinGroup(inviteCode: String(spaced))
        #expect(joined.id == created.id)
        #expect(joined.role == .member)
        #expect(joined.memberCount == 2)
        await #expect(throws: SocialError.invalidInviteCode) {
            try await outsider.backend.social.joinGroup(inviteCode: "ZZZZZZZZ")
        }

        // Nichtmitglieder sehen die Gruppe nicht; Mitglieder dürfen nicht verwalten.
        await #expect(throws: SocialError.notFound) {
            try await outsider.backend.social.group(created.id)
        }
        await #expect(throws: SocialError.notAllowed) {
            try await student.backend.social.setGroupGoal(created.id, dailyGoal: 5_000)
        }

        // Ranking mit Ziel-Markierung; 2 Mitglieder → 1 nötig.
        let ranking = try await student.backend.social.groupRanking(created.id, period: .daily)
        #expect(ranking.entries.map(\.profile.displayName) == ["Lehrerin", "Schueler"])
        #expect(ranking.entries.map(\.reachedGoalToday) == [true, false])
        let days = try await student.backend.social.groupDays(created.id, count: 7)
        #expect(days.first?.isToday == true)
        #expect(days.first?.requiredCount == 1)

        // Zieländerung gilt erst ab morgen.
        let changed = try await owner.backend.social.setGroupGoal(created.id, dailyGoal: 12_000)
        #expect(changed.dailyGoal == 10_000)
        #expect(changed.nextDailyGoal == 12_000)

        // Eigentümerin verlässt die Gruppe → Schüler übernimmt.
        try await owner.backend.social.leaveGroup(created.id)
        let afterLeave = try await student.backend.social.group(created.id)
        #expect(afterLeave.isOwner)
        #expect(afterLeave.memberCount == 1)
        #expect(try await owner.backend.social.myGroups().isEmpty)

        // Letztes Mitglied löscht die Gruppe.
        try await student.backend.social.deleteGroup(created.id)
        #expect(try await student.backend.social.myGroups().isEmpty)
    }

    @Test func invitationsOnlyForFriends() async throws {
        let host = try await newUser("Host", steps: 1_000)
        let friend = try await newUser("Freundin", steps: 1_000)
        let stranger = try await newUser("Fremder", steps: 1_000)
        let group = try await host.backend.social.createGroup(GroupDraft(name: "Laufteam", kind: .work), timeZone: "Europe/Berlin")

        let friendProfile = try #require(try await host.backend.social.findProfile(username: friend.username)).profile
        let strangerProfile = try #require(try await host.backend.social.findProfile(username: stranger.username)).profile
        await #expect(throws: SocialError.notFound) {
            _ = try await host.backend.social.invite(strangerProfile.publicID, to: group.id)
        }

        _ = try await host.backend.social.sendFriendRequest(to: friendProfile.publicID)
        let request = try #require(try await friend.backend.social.friendRequests().first)
        try await friend.backend.social.respondToFriendRequest(request.id, accept: true)

        #expect(try await host.backend.social.invite(friendProfile.publicID, to: group.id) == .invited)
        #expect(try await host.backend.social.invite(friendProfile.publicID, to: group.id) == .alreadyInvited)
        #expect(try await host.backend.social.outgoingInvitations(for: group.id).map(\.profile.publicID) == [friendProfile.publicID])

        let invitation = try #require(try await friend.backend.social.groupInvitations().first)
        #expect(invitation.groupName == "Laufteam")
        let accepted = try await friend.backend.social.respondToInvitation(invitation.id, accept: true)
        #expect(accepted?.id == group.id)
        #expect(accepted?.memberCount == 2)
    }
}
