import Foundation
import PaceCore
import PaceTestSupport
import ProfileFeature
import Testing

@MainActor
struct ProfileViewModelTests {
    private struct Environment {
        let store: ProfileStore
        let profiles: ProfileRepositoryStub
        let cache: InMemoryProfileCache
    }

    private func makeViewModel(
        profile: UserProfile = Fixtures.profile(),
        regions: RegionRepositoryStub = RegionRepositoryStub()
    ) -> (ProfileViewModel, Environment) {
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let cache = InMemoryProfileCache()
        let store = ProfileStore(profile: profile, profiles: profiles, regions: regions, cache: cache)
        let viewModel = ProfileViewModel(store: store, regions: regions, searchDebounce: .zero)
        return (viewModel, Environment(store: store, profiles: profiles, cache: cache))
    }

    @Test func showsNamesAndRegionOfPfungstadt() async {
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(displayName: "Niklas K."))

        await viewModel.load()

        #expect(viewModel.displayName == "Niklas K.")
        #expect(viewModel.username == "@niklas")
        #expect(viewModel.initials == "NK")
        #expect(viewModel.municipalityName == "Pfungstadt")
        #expect(viewModel.districtName == "Landkreis Darmstadt-Dieburg")
        #expect(viewModel.stateName == "Hessen")
        #expect(!viewModel.regionLoadFailed)
    }

    @Test func kreisfreieStadtIsShownAsSuch() async {
        let (viewModel, _) = makeViewModel(profile: Fixtures.profile(municipalityID: Fixtures.frankfurt.id))

        await viewModel.load()

        #expect(viewModel.municipalityName == "Frankfurt am Main")
        #expect(viewModel.districtName == "kreisfreie Stadt")
        #expect(viewModel.stateName == "Hessen")
    }

    @Test func failedRegionLoadIsReported() async {
        let (viewModel, _) = makeViewModel(regions: RegionRepositoryStub { $0.error = .network })

        await viewModel.load()

        #expect(viewModel.regionLoadFailed)
        #expect(viewModel.municipalityName == nil)
    }

    @Test func togglingParticipationUpdatesProfileAndCache() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: false))

        await viewModel.setRegionalLeaderboardEnabled(true)

        #expect(viewModel.regionalLeaderboardEnabled)
        #expect(env.profiles.state.current.optInUpdates == [true])
        #expect(env.cache.load(for: Fixtures.userID)?.regionalLeaderboardEnabled == true)

        await viewModel.setRegionalLeaderboardEnabled(false)

        #expect(!viewModel.regionalLeaderboardEnabled)
        #expect(env.profiles.state.current.optInUpdates == [true, false])
    }

    @Test func failedToggleKeepsPreviousValueAndShowsError() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: true))
        env.profiles.state.withLock { $0.error = .network }

        await viewModel.setRegionalLeaderboardEnabled(false)

        #expect(viewModel.regionalLeaderboardEnabled)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.isUpdatingParticipation)
    }

    @Test func changingRegionStoresOnlyTheMunicipalityAndKeepsConsent() async {
        let (viewModel, env) = makeViewModel(profile: Fixtures.profile(regionalLeaderboardEnabled: true))
        await viewModel.load()

        viewModel.beginRegionChange()
        #expect(viewModel.isChangingRegion)
        let search = viewModel.regionSearch
        await search?.search("Berlin")
        search?.select(Fixtures.berlinHierarchy)
        await viewModel.saveRegionChange()

        let updates = env.profiles.state.current.regionUpdates
        #expect(updates.count == 1)
        #expect(updates.first?.0 == Fixtures.berlin.id)
        #expect(updates.first?.1 == true)
        #expect(!viewModel.isChangingRegion)
        #expect(viewModel.municipalityName == "Berlin")
        #expect(viewModel.stateName == "Berlin")
        #expect(env.store.profile.municipalityID == Fixtures.berlin.id)
    }

    @Test func currentMunicipalityCannotBeSavedAgain() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()

        viewModel.beginRegionChange()
        viewModel.regionSearch?.select(Fixtures.pfungstadtHierarchy)

        #expect(!viewModel.canSaveRegion)
    }

    @Test func failedRegionChangeKeepsSheetOpenWithError() async {
        let (viewModel, env) = makeViewModel()
        await viewModel.load()
        viewModel.beginRegionChange()
        viewModel.regionSearch?.select(Fixtures.griesheimHierarchy)
        env.profiles.state.withLock { $0.error = .network }

        await viewModel.saveRegionChange()

        #expect(viewModel.isChangingRegion)
        #expect(viewModel.regionChangeError?.contains("Verbindung") == true)
        #expect(viewModel.municipalityName == "Pfungstadt")
    }

    @Test func cancellingClosesTheSheet() {
        let (viewModel, _) = makeViewModel()
        viewModel.beginRegionChange()

        viewModel.cancelRegionChange()

        #expect(!viewModel.isChangingRegion)
        #expect(viewModel.regionSearch == nil)
    }
}
