import Foundation
import LeaderboardFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct LeaderboardViewModelTests {
    private struct Environment {
        let store: ProfileStore
        let profiles: ProfileRepositoryStub
        let leaderboards: LeaderboardRepositoryStub
        let syncing: ActivitySyncingSpy
    }

    /// Fester Zeitpunkt: Samstag, 17.10.2026, 12:00 in Berlin.
    private static let now = Fixtures.date(2026, 10, 17, 12)
    private static let today = LocalDate(year: 2026, month: 10, day: 17)

    private func makeViewModel(
        profile: UserProfile = Fixtures.profile(regionalLeaderboardEnabled: true),
        regions: RegionRepositoryStub = RegionRepositoryStub(),
        leaderboards: LeaderboardRepositoryStub = LeaderboardRepositoryStub(),
        topLimit: Int = 50
    ) -> (LeaderboardViewModel, Environment) {
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: regions, cache: InMemoryProfileCache())
        let syncing = ActivitySyncingSpy()
        let viewModel = LeaderboardViewModel(
            store: store,
            leaderboards: leaderboards,
            syncing: syncing,
            calendar: Fixtures.activityCalendar,
            now: { [now = Self.now] in now },
            topLimit: topLimit
        )
        return (viewModel, Environment(store: store, profiles: profiles, leaderboards: leaderboards, syncing: syncing))
    }

    // MARK: Ebenen

    @Test func pfungstadtHasFourScopesAndStartsWithMunicipality() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.loadIfNeeded()

        #expect(viewModel.scopes.map(\.id) == ["DE:06432018", "DE:06432", "DE:06", "DE"])
        #expect(viewModel.selectedScope?.id == Fixtures.pfungstadt.id)
        #expect(viewModel.snapshot?.query == LeaderboardQuery(regionID: Fixtures.pfungstadt.id, period: .daily, date: Self.today))
    }

    @Test func frankfurtSkipsTheDuplicateDistrict() async {
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(municipalityID: Fixtures.frankfurt.id))

        await viewModel.loadIfNeeded()

        #expect(viewModel.scopes.map(\.id) == ["DE:06412000", "DE:06", "DE"])
    }

    @Test func berlinHasCityAndCountryOnly() async {
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(municipalityID: Fixtures.berlin.id))

        await viewModel.loadIfNeeded()

        #expect(viewModel.scopes.map(\.id) == ["DE:11000000", "DE"])
    }

    @Test func selectingAScopeLoadsItsRanking() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.hessen.id] = Fixtures.ranking(count: 3, currentUserRank: 2)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)
        await viewModel.loadIfNeeded()

        await viewModel.select(Fixtures.hessen)

        #expect(viewModel.selectedScope?.id == Fixtures.hessen.id)
        #expect(viewModel.snapshot?.query.regionID == Fixtures.hessen.id)
        #expect(viewModel.snapshot?.currentUserEntry?.rank == 2)
    }

    // MARK: Laden

    @Test func flushesPendingStepsBeforeLoading() async {
        let (viewModel, env) = makeViewModel()

        await viewModel.loadIfNeeded()

        #expect(env.syncing.state.current.flushes == 1)
    }

    @Test func showsTopListAndOwnPositionWithGap() async throws {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 30, currentUserRank: 20)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards, topLimit: 10)

        await viewModel.loadIfNeeded()

        let snapshot = try #require(viewModel.snapshot)
        #expect(snapshot.totalParticipants == 30)
        #expect(snapshot.rows.count == 10 + 1 + 3)
        #expect(snapshot.rows[10] == .gap(afterRank: 10))
        #expect(snapshot.entries.suffix(3).map(\.rank) == [19, 20, 21])
        #expect(snapshot.currentUserEntry?.rank == 20)
        #expect(viewModel.emptyStateText == nil)
    }

    @Test func secondAppearanceDoesNotReloadFreshData() async {
        let leaderboards = LeaderboardRepositoryStub()
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        #expect(leaderboards.state.current.pageRequests.count == 1)
    }

    @Test func refreshReloadsAndKeepsDataOnNetworkError() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 2, currentUserRank: 1)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)
        await viewModel.loadIfNeeded()

        leaderboards.state.withLock { $0.error = .network }
        await viewModel.refresh()

        #expect(leaderboards.state.current.pageRequests.count == 2)
        #expect(viewModel.snapshot?.totalParticipants == 2)
    }

    @Test func networkErrorShowsMessageAndRetryRecovers() async {
        let leaderboards = LeaderboardRepositoryStub { $0.error = .network }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)

        await viewModel.loadIfNeeded()
        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
        #expect(message.contains("Verbindung"))

        leaderboards.state.withLock { $0.error = nil }
        await viewModel.retry()

        #expect(viewModel.snapshot != nil)
    }

    @Test func failingHierarchyShowsError() async {
        let (viewModel, _) = makeViewModel(regions: RegionRepositoryStub { $0.error = .network })

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .failed(message: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."))
    }

    @Test func staleResponseDoesNotOverwriteNewerScope() async throws {
        let leaderboards = SlowLeaderboards(delays: [Fixtures.pfungstadt.id: .milliseconds(80)])
        let profile = Fixtures.profile(regionalLeaderboardEnabled: true)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(
            profile: profile,
            hierarchy: Fixtures.pfungstadtHierarchy,
            profiles: profiles,
            regions: RegionRepositoryStub(),
            cache: InMemoryProfileCache()
        )
        let viewModel = LeaderboardViewModel(
            store: store,
            leaderboards: leaderboards,
            syncing: nil,
            calendar: Fixtures.activityCalendar,
            now: { [now = Self.now] in now }
        )

        async let slow: Void = viewModel.loadIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        await viewModel.select(Fixtures.germany)
        await slow

        #expect(viewModel.snapshot?.query.regionID == Fixtures.germany.id)
    }

    // MARK: Leere Rankings & Teilnahme

    @Test func aloneInRankingSaysFirst() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 1, currentUserRank: 1)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)

        await viewModel.loadIfNeeded()

        #expect(viewModel.emptyStateText == "Du bist der Erste in Pfungstadt.")
    }

    @Test func emptyRankingWithoutParticipationSaysNoUsersYet() async {
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))

        await viewModel.loadIfNeeded()

        #expect(viewModel.emptyStateText == "Noch keine Pace-Nutzer in Pfungstadt.")
    }

    @Test func emptyDistrictUsesFullDistrictName() async {
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))
        await viewModel.loadIfNeeded()

        await viewModel.select(Fixtures.darmstadtDieburg)

        #expect(viewModel.emptyStateText == "Noch keine Pace-Nutzer in Landkreis Darmstadt-Dieburg.")
    }

    @Test func enableParticipationStoresConsentAndReloads() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))
        await viewModel.loadIfNeeded()
        let keyBefore = viewModel.reloadKey

        await viewModel.enableParticipation()

        #expect(viewModel.isParticipating)
        #expect(env.profiles.state.current.optInUpdates == [true])
        #expect(viewModel.reloadKey != keyBefore)
        #expect(env.leaderboards.state.current.pageRequests.count == 2)
        // Die anschließende `.task(id: reloadKey)` der View lädt nicht ein drittes Mal.
        await viewModel.loadIfNeeded()
        #expect(env.leaderboards.state.current.pageRequests.count == 2)
    }

    @Test func failedParticipationUpdateShowsError() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))
        env.profiles.state.withLock { $0.error = .network }

        await viewModel.enableParticipation()

        #expect(!viewModel.isParticipating)
        #expect(viewModel.participationError != nil)
        #expect(!viewModel.isUpdatingParticipation)
    }
}

/// Antwortet je Region mit einstellbarer Verzögerung.
private struct SlowLeaderboards: LeaderboardRepository {
    let delays: [RegionID: Duration]

    func page(for query: LeaderboardQuery, offset: Int, limit: Int) async throws -> LeaderboardPage {
        if let delay = delays[query.regionID] {
            try await Task.sleep(for: delay)
        }
        return LeaderboardPage(entries: [], totalParticipants: 0, offset: offset, limit: limit)
    }

    func neighborhood(for query: LeaderboardQuery, radius: Int) async throws -> [LeaderboardEntry] {
        []
    }
}
