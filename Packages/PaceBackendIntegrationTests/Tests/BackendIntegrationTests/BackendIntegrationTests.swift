import Foundation
import PaceBackend
import PaceCore
import Testing

/// Ende-zu-Ende gegen einen echten (lokalen) Supabase-Stack mit allen Migrationen: anonyme Anmeldung, Profil,
/// Regionen, Sync und Rankings – über genau die Schicht, die auch die App verwendet.
@Suite(.enabled(if: IntegrationEnvironment.configuration != nil, "PACE_SUPABASE_URL/PACE_SUPABASE_PUBLISHABLE_KEY fehlen"))
struct BackendIntegrationTests {
    private let pfungstadt: RegionID = "DE:06432018"
    private let griesheim: RegionID = "DE:06432010"

    /// Ein neuer, anonym angemeldeter Nutzer mit eigenem Sitzungsspeicher (wie ein eigenes Gerät).
    private func newUser() async throws -> (backend: SupabaseBackend, session: AuthSession) {
        let backend = SupabaseBackend(configuration: try #require(IntegrationEnvironment.configuration), localStorage: InMemoryAuthStorage())
        #expect(await backend.auth.restoreSession() == nil)
        let session = try await backend.auth.signInAnonymously()
        #expect(session.isAnonymous)
        #expect(await backend.auth.restoreSession()?.userID == session.userID)
        return (backend, session)
    }

    private func uniqueUsername(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.prefix(8))".replacingOccurrences(of: "-", with: "")
    }

    /// Lokaler Kalendertag in Berlin, wie ihn die App für Sync und Rankings verwendet.
    private var today: LocalDate {
        ActivityCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!).day(containing: Date())
    }

    @Test func profileLifecycleAndPrivacy() async throws {
        let (first, firstSession) = try await newUser()
        #expect(try await first.profiles.fetchProfile(for: firstSession.userID) == nil)

        let username = uniqueUsername("Erster")
        let created = try await first.profiles.createProfile(NewProfile(username: username, displayName: "  Erster   Nutzer "), for: firstSession.userID)
        #expect(created.username == username)
        #expect(created.displayName == "Erster Nutzer")
        #expect(created.municipalityID == nil)
        #expect(!created.regionalLeaderboardEnabled)
        #expect(try await first.profiles.fetchProfile(for: firstSession.userID) == created)

        #expect(try await !first.profiles.isUsernameAvailable(username.uppercased()))
        #expect(try await first.profiles.isUsernameAvailable(uniqueUsername("frei")))

        let (second, secondSession) = try await newUser()
        await #expect(throws: ProfileError.usernameTaken) {
            try await second.profiles.createProfile(NewProfile(username: username.lowercased(), displayName: "Kopie"), for: secondSession.userID)
        }
        await #expect(throws: ProfileError.invalidUsername) {
            try await second.profiles.createProfile(NewProfile(username: "mit leer", displayName: "Leer"), for: secondSession.userID)
        }
        // Fremde Profile sind über die Tabelle nicht lesbar.
        #expect(try await second.profiles.fetchProfile(for: firstSession.userID) == nil)

        // Region: nur Gemeinden, Zustimmung explizit.
        await #expect(throws: ProfileError.invalidRegion) {
            try await first.profiles.updateRegion(municipalityID: "DE:06432", regionalLeaderboardEnabled: true, for: firstSession.userID)
        }
        let withRegion = try await first.profiles.updateRegion(municipalityID: pfungstadt, regionalLeaderboardEnabled: true, for: firstSession.userID)
        #expect(withRegion.municipalityID == pfungstadt)
        #expect(withRegion.regionalLeaderboardEnabled)
        let optedOut = try await first.profiles.updateRegionalLeaderboardEnabled(false, for: firstSession.userID)
        #expect(!optedOut.regionalLeaderboardEnabled)
        #expect(optedOut.updatedAt >= created.updatedAt)
    }

    @Test func regionSearchAndHierarchy() async throws {
        let (user, _) = try await newUser()

        let results = try await user.regions.searchMunicipalities(matching: "Pfungstadt", limit: 5)
        let hierarchy = try #require(results.first)
        #expect(hierarchy.municipality.id == pfungstadt)
        #expect(hierarchy.district.id == "DE:06432")
        #expect(hierarchy.district.displayName == "Landkreis Darmstadt-Dieburg")
        #expect(hierarchy.state.id == "DE:06")
        #expect(hierarchy.state.name == "Hessen")
        #expect(hierarchy.country.id == "DE")
        #expect(hierarchy.subtitle == "Hessen · Landkreis Darmstadt-Dieburg")
        #expect(hierarchy.leaderboardScopes.map(\.name) == ["Pfungstadt", "Darmstadt-Dieburg", "Hessen", "Deutschland"])

        let frankfurt = try #require(try await user.regions.searchMunicipalities(matching: "frankfurt", limit: 5).first)
        #expect(frankfurt.municipality.id == "DE:06412000")
        #expect(frankfurt.leaderboardScopes.map(\.id) == ["DE:06412000", "DE:06", "DE"])

        let munich = try #require(try await user.regions.searchMunicipalities(matching: "muenchen", limit: 5).first)
        #expect(munich.municipality.name == "München")

        let berlin = try await user.regions.hierarchy(forMunicipality: "DE:11000000")
        #expect(berlin.leaderboardScopes.map(\.id) == ["DE:11000000", "DE"])
        await #expect(throws: RegionError.notFound) {
            try await user.regions.hierarchy(forMunicipality: "DE:06432")
        }
    }

    @Test func syncAndRegionalLeaderboards() async throws {
        let calendar = ActivityCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

        // Teilnehmer mit Zustimmung in Pfungstadt.
        let (me, mySession) = try await newUser()
        let myName = uniqueUsername("Ich")
        _ = try await me.profiles.createProfile(NewProfile(username: myName, displayName: "Ich"), for: mySession.userID)
        _ = try await me.profiles.updateRegion(municipalityID: pfungstadt, regionalLeaderboardEnabled: true, for: mySession.userID)

        // Viele Schritte, aber ohne Zustimmung (Griesheim, gleicher Kreis).
        let (hidden, hiddenSession) = try await newUser()
        let hiddenName = uniqueUsername("Versteckt")
        _ = try await hidden.profiles.createProfile(NewProfile(username: hiddenName, displayName: "Versteckt"), for: hiddenSession.userID)
        _ = try await hidden.profiles.updateRegion(municipalityID: griesheim, regionalLeaderboardEnabled: false, for: hiddenSession.userID)
        try await hidden.activitySync.upsert([DailyCompetitionSteps(date: today, competitionSteps: 150_000)], for: hiddenSession.userID)

        // Letzte 7 Tage synchronisieren – zweimal, um doppelte Datensätze auszuschließen.
        let week = (0..<7).map { offset in
            DailyCompetitionSteps(date: calendar.adding(-offset, to: today), competitionSteps: 1_000 + offset)
        }
        try await me.activitySync.upsert(week, for: mySession.userID)
        try await me.activitySync.upsert([DailyCompetitionSteps(date: today, competitionSteps: 123_456)], for: mySession.userID)

        // Tage außerhalb des Fensters lehnt der Server ab.
        await #expect(throws: ActivitySyncError.rejected) {
            try await me.activitySync.upsert([DailyCompetitionSteps(date: calendar.adding(-30, to: today), competitionSteps: 1)], for: mySession.userID)
        }

        // Alle vier Ebenen enthalten mich mit dem aktuellen Wert; der Nutzer ohne Zustimmung erscheint nirgends.
        for regionID: RegionID in [pfungstadt, "DE:06432", "DE:06", "DE"] {
            let query = LeaderboardQuery(regionID: regionID, period: .daily, date: today)
            let page = try await me.leaderboards.page(for: query, offset: 0, limit: 100)
            let neighborhood = try await me.leaderboards.neighborhood(for: query, radius: 1)
            let mine = try #require(neighborhood.first { $0.isCurrentUser }, "eigener Eintrag in \(regionID)")
            #expect(mine.competitionSteps == 123_456)
            #expect(mine.username == myName)
            #expect(page.totalParticipants >= 1)
            #expect(!page.entries.contains { $0.username == hiddenName })
            #expect(!neighborhood.contains { $0.username == hiddenName })
            #expect(page.entries.map(\.rank) == page.entries.map(\.rank).sorted())
            if let first = page.entries.first, page.entries.count > 1 {
                #expect(first.competitionSteps >= page.entries[1].competitionSteps)
            }
        }

        // Woche: Summe der ISO-Woche bis heute.
        let weekStart = calendar.startOfWeek(containing: today)
        let expectedWeek = week.filter { $0.date >= weekStart && $0.date != today }.reduce(123_456) { $0 + $1.competitionSteps }
        let weekly = try await me.leaderboards.neighborhood(for: LeaderboardQuery(regionID: pfungstadt, period: .weekly, date: today), radius: 0)
        #expect(weekly.first { $0.isCurrentUser }?.competitionSteps == expectedWeek)

        // Ohne Zustimmung: keine eigene Position, das Ranking anderer bleibt sichtbar.
        let hiddenView = try await hidden.leaderboards.neighborhood(for: LeaderboardQuery(regionID: "DE:06432", period: .daily, date: today), radius: 1)
        #expect(hiddenView.isEmpty)
        let hiddenPage = try await hidden.leaderboards.page(for: LeaderboardQuery(regionID: "DE:06432", period: .daily, date: today), offset: 0, limit: 50)
        #expect(hiddenPage.entries.contains { $0.username == myName })
        #expect(!hiddenPage.entries.contains { $0.isCurrentUser })

        await #expect(throws: LeaderboardError.unknownRegion) {
            try await me.leaderboards.page(for: LeaderboardQuery(regionID: "DE:00000", period: .daily, date: today), offset: 0, limit: 10)
        }
    }

    @Test func coreFlowsRunAgainstTheRealBackend() async throws {
        // Bootstrap wie in der App: neue Identität → Profil fehlt → anlegen → Region fehlt → setzen → bereit.
        let backend = SupabaseBackend(configuration: try #require(IntegrationEnvironment.configuration), localStorage: InMemoryAuthStorage())
        let cache = MemoryProfileCache()
        let bootstrapper = SessionBootstrapper(auth: backend.auth, profiles: backend.profiles, cache: cache)

        guard case .needsProfile(let userID) = try await bootstrapper.run() else {
            Issue.record("Neue Identität sollte ein Profil brauchen")
            return
        }
        _ = try await backend.profiles.createProfile(NewProfile(username: uniqueUsername("Boot"), displayName: "Boot"), for: userID)
        guard case .needsRegion = try await bootstrapper.run() else {
            Issue.record("Profil ohne Region sollte die Region brauchen")
            return
        }
        _ = try await backend.profiles.updateRegion(municipalityID: pfungstadt, regionalLeaderboardEnabled: true, for: userID)
        guard case .ready(let profile) = try await bootstrapper.run() else {
            Issue.record("Vollständiges Profil sollte bereit sein")
            return
        }
        #expect(profile.id == userID)

        // Sync-Koordinator und Leaderboard-Loader wie in der App.
        let berlin = ActivityCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let summaries = (0..<7).map { offset in
            DailyActivitySummary(date: berlin.adding(offset - 6, to: today), healthSteps: 5_000, competitionSteps: 4_000 + offset)
        }
        let overview = ActivityOverview(
            today: summaries[6], yesterday: summaries[5],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: summaries),
            lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: summaries),
            updatedAt: Date()
        )
        let coordinator = ActivitySyncCoordinator(repository: backend.activitySync, userID: userID)
        await coordinator.submit(overview, trigger: .appStart)
        guard case .synced = await coordinator.status else {
            Issue.record("Sync fehlgeschlagen: \(await coordinator.status)")
            return
        }

        let snapshot = try await LeaderboardLoader(repository: backend.leaderboards)
            .load(LeaderboardQuery(regionID: pfungstadt, period: .daily, date: today))
        #expect(snapshot.currentUserEntry?.competitionSteps == 4_006)
    }
}

enum IntegrationEnvironment {
    static let configuration: BackendConfiguration? = {
        let environment = ProcessInfo.processInfo.environment
        return try? BackendConfiguration.make(
            url: environment["PACE_SUPABASE_URL"],
            publishableKey: environment["PACE_SUPABASE_PUBLISHABLE_KEY"]
        )
    }()
}

final class MemoryProfileCache: ProfileCaching, @unchecked Sendable {
    // `@unchecked Sendable`: Zugriff nur unter `lock`.
    private let lock = NSLock()
    private var profiles: [UserID: UserProfile] = [:]

    func load(for userID: UserID) -> UserProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles[userID]
    }

    func save(_ profile: UserProfile) {
        lock.lock()
        defer { lock.unlock() }
        profiles[profile.id] = profile
    }
}
