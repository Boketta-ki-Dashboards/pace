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

@MainActor
struct ProfileStoreRaceTests {
    /// Ein Abgleich, dessen Antwort erst nach einer eigenen Änderung eintrifft, darf die Änderung nicht zurückdrehen –
    /// sonst wäre z. B. die Zustimmung zu Rankings ohne Zutun wieder an.
    @Test func staleRefreshDoesNotRevertOptOut() async throws {
        let base = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile(regionalLeaderboardEnabled: true) }
        let repository = SlowFetchRepository(base: base, delay: .milliseconds(80))
        let cache = InMemoryProfileCache()
        let store = ProfileStore(
            profile: Fixtures.profile(regionalLeaderboardEnabled: true),
            profiles: repository,
            regions: RegionRepositoryStub(),
            cache: cache
        )

        async let refresh: Void = store.refresh()
        try await Task.sleep(for: .milliseconds(10))
        try await store.setRegionalLeaderboardEnabled(false)
        try await refresh

        #expect(!store.profile.regionalLeaderboardEnabled)
        #expect(cache.load(for: Fixtures.userID)?.regionalLeaderboardEnabled == false)
    }
}

/// Liefert beim Laden den Stand vom Zeitpunkt der Anfrage – mit Verzögerung, wie eine langsame Verbindung.
private struct SlowFetchRepository: ProfileRepository {
    let base: ProfileRepositoryStub
    let delay: Duration

    func fetchProfile(for userID: UserID) async throws -> UserProfile? {
        let snapshot = try await base.fetchProfile(for: userID)
        try await Task.sleep(for: delay)
        return snapshot
    }

    func createProfile(_ profile: NewProfile, for userID: UserID) async throws -> UserProfile {
        try await base.createProfile(profile, for: userID)
    }

    func updateRegion(municipalityID: RegionID, regionalLeaderboardEnabled: Bool, for userID: UserID) async throws -> UserProfile {
        try await base.updateRegion(municipalityID: municipalityID, regionalLeaderboardEnabled: regionalLeaderboardEnabled, for: userID)
    }

    func updateRegionalLeaderboardEnabled(_ enabled: Bool, for userID: UserID) async throws -> UserProfile {
        try await base.updateRegionalLeaderboardEnabled(enabled, for: userID)
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await base.isUsernameAvailable(username)
    }
}
