import Foundation
import OnboardingFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct OnboardingViewModelTests {
    private final class Finished {
        var profiles: [UserProfile] = []
    }

    private func makeViewModel(
        start: OnboardingViewModel.Start,
        profiles: ProfileRepositoryStub = ProfileRepositoryStub(),
        regions: RegionRepositoryStub = RegionRepositoryStub(),
        cache: InMemoryProfileCache = InMemoryProfileCache(),
        finished: Finished = Finished()
    ) -> OnboardingViewModel {
        OnboardingViewModel(start: start, profiles: profiles, regions: regions, cache: cache, debounce: .immediate) {
            finished.profiles.append($0)
        }
    }

    private func profileStep(_ viewModel: OnboardingViewModel) throws -> ProfileSetupViewModel {
        guard case .profile(let step) = viewModel.step else {
            throw StepMismatch()
        }
        return step
    }

    private func regionStep(_ viewModel: OnboardingViewModel) throws -> RegionOnboardingViewModel {
        guard case .region(let step) = viewModel.step else {
            throw StepMismatch()
        }
        return step
    }

    private struct StepMismatch: Error {}

    @Test func fullFlowCreatesProfileThenStoresOnlyTheMunicipality() async throws {
        let profiles = ProfileRepositoryStub()
        let cache = InMemoryProfileCache()
        let finished = Finished()
        let viewModel = makeViewModel(start: .profile(Fixtures.userID), profiles: profiles, cache: cache, finished: finished)
        #expect(viewModel.step.number == 1)

        let setup = try profileStep(viewModel)
        setup.displayName = "Niklas"
        setup.username = "niklas"
        await setup.submit()

        let region = try regionStep(viewModel)
        #expect(viewModel.step.number == 2)
        #expect(cache.load(for: Fixtures.userID)?.municipalityID == nil)

        await region.search.search("Pfungstadt")
        region.search.select(Fixtures.pfungstadtHierarchy)
        await region.confirm(regionalLeaderboardEnabled: true)

        let updates = profiles.state.current.regionUpdates
        #expect(updates.count == 1)
        #expect(updates.first?.0 == Fixtures.pfungstadt.id)
        #expect(updates.first?.1 == true)

        let profile = try #require(finished.profiles.first)
        #expect(profile.municipalityID == Fixtures.pfungstadt.id)
        #expect(profile.regionalLeaderboardEnabled)
        #expect(cache.load(for: Fixtures.userID) == profile)
    }

    @Test func profileWithoutRegionStartsAtRegionStep() throws {
        let viewModel = makeViewModel(start: .region(Fixtures.profile(municipalityID: nil)))

        let region = try regionStep(viewModel)
        #expect(region.profile.username == "niklas")
        #expect(!region.canConfirm)
    }

    @Test func optOutStoresRegionWithoutLeaderboardConsent() async throws {
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile(municipalityID: nil) }
        let finished = Finished()
        let viewModel = makeViewModel(start: .region(Fixtures.profile(municipalityID: nil)), profiles: profiles, finished: finished)
        let region = try regionStep(viewModel)

        region.search.select(Fixtures.berlinHierarchy)
        await region.confirm(regionalLeaderboardEnabled: false)

        let profile = try #require(finished.profiles.first)
        #expect(profile.municipalityID == Fixtures.berlin.id)
        #expect(!profile.regionalLeaderboardEnabled)
    }

    @Test func confirmWithoutSelectionDoesNothing() async throws {
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile(municipalityID: nil) }
        let finished = Finished()
        let viewModel = makeViewModel(start: .region(Fixtures.profile(municipalityID: nil)), profiles: profiles, finished: finished)
        let region = try regionStep(viewModel)

        await region.confirm(regionalLeaderboardEnabled: true)

        #expect(profiles.state.current.regionUpdates.isEmpty)
        #expect(finished.profiles.isEmpty)
    }

    @Test func failedSaveShowsErrorAndCanBeRetried() async throws {
        let profiles = ProfileRepositoryStub {
            $0.profiles[Fixtures.userID] = Fixtures.profile(municipalityID: nil)
            $0.error = .network
        }
        let finished = Finished()
        let viewModel = makeViewModel(start: .region(Fixtures.profile(municipalityID: nil)), profiles: profiles, finished: finished)
        let region = try regionStep(viewModel)
        region.search.select(Fixtures.pfungstadtHierarchy)

        await region.confirm(regionalLeaderboardEnabled: true)

        #expect(finished.profiles.isEmpty)
        #expect(region.errorMessage?.contains("Verbindung") == true)
        #expect(region.canConfirm)

        profiles.state.withLock { $0.error = nil }
        await region.confirm(regionalLeaderboardEnabled: true)

        #expect(finished.profiles.count == 1)
        #expect(region.errorMessage == nil)
    }

    @Test func invalidRegionClearsSelection() async throws {
        let profiles = ProfileRepositoryStub {
            $0.profiles[Fixtures.userID] = Fixtures.profile(municipalityID: nil)
            $0.error = .invalidRegion
        }
        let viewModel = makeViewModel(start: .region(Fixtures.profile(municipalityID: nil)), profiles: profiles)
        let region = try regionStep(viewModel)
        region.search.select(Fixtures.pfungstadtHierarchy)

        await region.confirm(regionalLeaderboardEnabled: true)

        #expect(region.search.selection == nil)
        #expect(region.errorMessage != nil)
    }
}
