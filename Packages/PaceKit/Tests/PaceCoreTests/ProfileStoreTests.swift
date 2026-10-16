import Foundation
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct ProfileStoreTests {
    private func makeStore(
        profile: UserProfile = Fixtures.profile(),
        profiles: ProfileRepositoryStub? = nil,
        regions: RegionRepositoryStub = RegionRepositoryStub(),
        cache: InMemoryProfileCache = InMemoryProfileCache()
    ) -> (ProfileStore, ProfileRepositoryStub, InMemoryProfileCache) {
        let repository = profiles ?? ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let store = ProfileStore(profile: profile, profiles: repository, regions: regions, cache: cache)
        return (store, repository, cache)
    }

    @Test func loadsHierarchyOfSelectedMunicipality() async throws {
        let (store, _, _) = makeStore()

        try await store.loadHierarchyIfNeeded()

        #expect(store.hierarchy == Fixtures.pfungstadtHierarchy)
    }

    @Test func changingRegionKeepsLeaderboardConsentAndUpdatesCache() async throws {
        let (store, repository, cache) = makeStore(profile: Fixtures.profile(regionalLeaderboardEnabled: true))

        try await store.changeRegion(to: Fixtures.frankfurtHierarchy)

        #expect(store.profile.municipalityID == Fixtures.frankfurt.id)
        #expect(store.profile.regionalLeaderboardEnabled)
        #expect(store.hierarchy == Fixtures.frankfurtHierarchy)
        #expect(repository.state.current.regionUpdates.map(\.0) == [Fixtures.frankfurt.id])
        #expect(repository.state.current.regionUpdates.map(\.1) == [true])
        #expect(cache.load(for: Fixtures.userID)?.municipalityID == Fixtures.frankfurt.id)
    }

    @Test func togglingRegionalLeaderboardIsPersisted() async throws {
        let (store, repository, cache) = makeStore()

        try await store.setRegionalLeaderboardEnabled(true)

        #expect(store.profile.regionalLeaderboardEnabled)
        #expect(repository.state.current.optInUpdates == [true])
        #expect(cache.load(for: Fixtures.userID)?.regionalLeaderboardEnabled == true)
    }

    @Test func failedToggleKeepsPreviousValue() async {
        let (store, repository, _) = makeStore()
        repository.state.withLock { $0.error = .network }

        await #expect(throws: ProfileError.network) {
            try await store.setRegionalLeaderboardEnabled(true)
        }
        #expect(!store.profile.regionalLeaderboardEnabled)
    }

    @Test func refreshAppliesServerProfileAndReloadsHierarchy() async throws {
        let (store, repository, _) = makeStore()
        try await store.loadHierarchyIfNeeded()
        repository.state.withLock { $0.profiles[Fixtures.userID]?.municipalityID = Fixtures.berlin.id }

        try await store.refresh()

        #expect(store.profile.municipalityID == Fixtures.berlin.id)
        #expect(store.hierarchy == Fixtures.berlinHierarchy)
    }
}
