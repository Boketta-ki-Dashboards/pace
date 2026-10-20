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
        topLimit: Int = 50,
        social: SocialRepositoryStub? = nil
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
            topLimit: topLimit,
            social: social
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

    @Test func progressHintUsesTheSameRulesAsHome() async {
        let (viewModel, _) = makeViewModel(leaderboards: LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 20, currentUserRank: 12, topSteps: 8_552)
        })

        await viewModel.loadIfNeeded()

        // Platz 11 hat 10 Schritte mehr → 11 fehlen (wie in „Dein Umfeld“ auf Home).
        #expect(viewModel.progressText == "Noch 11 Schritte bis Platz #11")
    }

    @Test func leaderGetsNoClimbHint() async {
        let (viewModel, _) = makeViewModel(leaderboards: LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 5, currentUserRank: 1)
        })

        await viewModel.loadIfNeeded()

        #expect(viewModel.progressText == "Du führst in Pfungstadt.")
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

    @Test func loadMoreShowsFurtherPlaces() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 25, currentUserRank: 3)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards, topLimit: 10)
        await viewModel.loadIfNeeded()
        #expect(viewModel.canLoadMore)

        await viewModel.loadMore()
        #expect(viewModel.snapshot?.entries.count == 20)

        await viewModel.loadMore()
        #expect(viewModel.snapshot?.entries.count == 25)
        #expect(!viewModel.canLoadMore)
        #expect(!viewModel.isLoadingMore)
    }

    @Test func pullToRefreshReadsOwnStepsBeforeLoading() async {
        let refreshes = Locked(0)
        let leaderboards = LeaderboardRepositoryStub()
        let profile = Fixtures.profile(regionalLeaderboardEnabled: true)
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: profiles, regions: RegionRepositoryStub(), cache: InMemoryProfileCache())
        let viewModel = LeaderboardViewModel(
            store: store,
            leaderboards: leaderboards,
            syncing: ActivitySyncingSpy(),
            refreshActivity: {
                // Beim Neu-Einlesen ist noch keine Ranking-Anfrage dieses Durchgangs gestellt.
                #expect(leaderboards.state.current.pageRequests.count == refreshes.current)
                refreshes.withLock { $0 += 1 }
            },
            calendar: Fixtures.activityCalendar,
            now: { [now = Self.now] in now }
        )

        await viewModel.refresh()

        #expect(refreshes.current == 1)
        #expect(leaderboards.state.current.pageRequests.count == 1)
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

    @Test func emptyRankingSaysNobodyHasStepsYet() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.loadIfNeeded()

        #expect(
            viewModel.emptyStateText
                == "Heute hat in Pfungstadt noch niemand Schritte gesammelt. Deine erscheinen, sobald sie synchronisiert sind."
        )
    }

    @Test func emptyDistrictUsesDistrictNameWithPreposition() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.loadIfNeeded()

        await viewModel.select(Fixtures.darmstadtDieburg)

        #expect(viewModel.emptyStateText?.hasPrefix("Heute hat im Landkreis Darmstadt-Dieburg noch niemand") == true)
    }

    // MARK: Ranking-Sichtbarkeit aus

    @Test func hiddenRankingLoadsNothing() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 5)
        }
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false), leaderboards: leaderboards)

        await viewModel.loadIfNeeded()
        await viewModel.select(Fixtures.darmstadtDieburg)
        await viewModel.refresh()

        #expect(viewModel.state == .hidden)
        #expect(viewModel.isRankingHidden)
        #expect(viewModel.snapshot == nil)
        #expect(viewModel.emptyStateText == nil)
        #expect(viewModel.progressText == nil)
        #expect(env.leaderboards.state.current.pageRequests.isEmpty)
        // Ohne Teilnahme werden auch keine Schritte „für das Ranking“ hochgeladen.
        #expect(env.syncing.state.current.flushes == 0)
        // Die eigenen Ebenen (eigene Region, keine fremden Daten) bleiben als Struktur sichtbar.
        #expect(viewModel.scopes.count == 4)
    }

    @Test func enableParticipationStoresConsentAndReloads() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))
        await viewModel.loadIfNeeded()
        let keyBefore = viewModel.reloadKey
        #expect(env.leaderboards.state.current.pageRequests.isEmpty)

        await viewModel.enableParticipation()

        #expect(viewModel.isParticipating)
        #expect(!viewModel.isRankingHidden)
        #expect(env.profiles.state.current.optInUpdates == [true])
        #expect(viewModel.reloadKey != keyBefore)
        #expect(env.leaderboards.state.current.pageRequests.count == 1)
        // Die anschließende `.task(id: reloadKey)` der View lädt nicht ein zweites Mal.
        await viewModel.loadIfNeeded()
        #expect(env.leaderboards.state.current.pageRequests.count == 1)
    }

    @Test func failedReloadAfterParticipationChangeShowsError() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 2)
        }
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false), leaderboards: leaderboards)
        await viewModel.loadIfNeeded()
        #expect(viewModel.snapshot == nil)

        leaderboards.state.withLock { $0.error = .network }
        await viewModel.enableParticipation()

        guard case .failed = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
    }

    @Test func failedParticipationUpdateShowsError() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))
        env.profiles.state.withLock { $0.error = .network }

        await viewModel.enableParticipation()

        #expect(!viewModel.isParticipating)
        #expect(viewModel.participationError != nil)
        #expect(!viewModel.isUpdatingParticipation)
    }

    // MARK: Freunde

    @Test func friendsRankingLoadsEvenWhenRegionalRankingIsHidden() async {
        let social = SocialRepositoryStub { $0.ranking = Fixtures.ranking(count: 3, currentUserRank: 2) }
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false), social: social)
        await viewModel.loadIfNeeded()
        #expect(viewModel.isRankingHidden)

        await viewModel.selectFriends()

        #expect(viewModel.isShowingFriends)
        #expect(!viewModel.isRankingHidden)
        guard case .loaded(let entries) = viewModel.friends else {
            Issue.record("Freunde-Ranking nicht geladen: \(viewModel.friends)")
            return
        }
        #expect(entries.map(\.rank) == [1, 2, 3])
        #expect(social.state.current.friendRankingPeriods == [.daily])
        #expect(env.leaderboards.state.current.pageRequests.isEmpty)
        #expect(viewModel.friendsProgressText == "Noch 11 Schritte bis Platz #1")
    }

    @Test func friendsHintsForLeaderAndLoneUser() async {
        let leader = SocialRepositoryStub { $0.ranking = Fixtures.ranking(count: 3, currentUserRank: 1) }
        let (leading, _) = makeViewModel(social: leader)
        await leading.selectFriends()
        #expect(leading.friendsProgressText == "Du führst unter deinen Freunden.")

        let alone = SocialRepositoryStub { $0.ranking = Fixtures.ranking(count: 1, currentUserRank: 1) }
        let (lonely, _) = makeViewModel(social: alone)
        await lonely.selectFriends()
        #expect(lonely.friendsProgressText == "Du bist der Erste unter deinen Freunden.")
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(lonely.friendsProgressText == "You're the first one among your friends.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(lonely.friendsProgressText == "Ты первый среди друзей.")
        }
    }

    @Test func friendsErrorShowsMessageAndRetryRecovers() async {
        let social = SocialRepositoryStub {
            $0.ranking = Fixtures.ranking(count: 2, currentUserRank: 2)
            $0.error = .network
        }
        let (viewModel, _) = makeViewModel(social: social)

        await viewModel.selectFriends()
        guard case .failed(let message) = viewModel.friends else {
            Issue.record("Kein Fehlerzustand: \(viewModel.friends)")
            return
        }
        #expect(message.hasPrefix("Keine Verbindung."))

        social.state.withLock { $0.error = nil }
        await viewModel.retry()
        guard case .loaded(let entries) = viewModel.friends else {
            Issue.record("Erneut versuchen hat nicht geladen")
            return
        }
        #expect(entries.count == 2)
    }

    @Test func friendsStayVisibleWhenRefreshFails() async {
        let social = SocialRepositoryStub { $0.ranking = Fixtures.ranking(count: 2, currentUserRank: 1) }
        let (viewModel, env) = makeViewModel(social: social)
        await viewModel.selectFriends()

        social.state.withLock { $0.error = .network }
        await viewModel.refresh()

        guard case .loaded(let entries) = viewModel.friends else {
            Issue.record("Alte Werte verworfen")
            return
        }
        #expect(entries.count == 2)
        #expect(env.syncing.state.current.flushes == 1)
    }

    @Test func switchingBackFromFriendsKeepsFreshRegionalRanking() async {
        let social = SocialRepositoryStub { $0.ranking = Fixtures.ranking(count: 2, currentUserRank: 1) }
        let (viewModel, env) = makeViewModel(social: social)
        await viewModel.loadIfNeeded()
        await viewModel.selectFriends()

        await viewModel.select(Fixtures.pfungstadt)

        #expect(!viewModel.isShowingFriends)
        #expect(viewModel.snapshot != nil)
        #expect(env.leaderboards.state.current.pageRequests.count == 1)
    }

    @Test func withoutSocialThereIsNoFriendsRanking() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.selectFriends()

        #expect(!viewModel.offersFriends)
        #expect(!viewModel.isShowingFriends)
        #expect(viewModel.friends == .idle)
    }

    @Test func messagesFollowTheAppLanguage() async {
        let leaderboards = LeaderboardRepositoryStub {
            $0.rankings[Fixtures.pfungstadt.id] = Fixtures.ranking(count: 1, currentUserRank: 1)
        }
        let (viewModel, _) = makeViewModel(leaderboards: leaderboards)
        await viewModel.loadIfNeeded()

        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(viewModel.emptyStateText == "You're the first one in Pfungstadt.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(viewModel.emptyStateText == "Ты первый в рейтинге «Pfungstadt».")
        }
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
