import Foundation
import HomeFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct HomeViewModelTests {
    private let now = Fixtures.date(2026, 10, 16, 9, 15)
    private let today = Fixtures.day(2026, 10, 16)

    private func makeViewModel(_ service: HealthServiceStub, syncing: ActivitySyncingSpy? = nil) -> HomeViewModel {
        let currentDate = now
        return HomeViewModel(activityData: service, syncing: syncing, calendar: Fixtures.activityCalendar, now: { currentDate })
    }

    private func todaysCompetitionSteps(_ viewModel: HomeViewModel) -> Int? {
        viewModel.overview?.today.competitionSteps
    }

    @Test func startsInLoadingState() {
        let viewModel = makeViewModel(HealthServiceStub())

        #expect(viewModel.state == .loading)
        #expect(viewModel.overview == nil)
    }

    @Test func showsTodaysActivity() async {
        let service = HealthServiceStub {
            $0.setSteps(4_300, competition: 4_200, on: today)
            $0.set(.activeEnergy, 382, on: today)
            $0.set(.walkingRunningDistance, 6_400, on: today)
        }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()

        let overview = viewModel.overview
        #expect(overview?.today.date == today)
        #expect(overview?.today.competitionSteps == 4_200)
        #expect(overview?.today.healthSteps == 4_300)
        #expect(overview?.today.activeEnergyKilocalories == 382)
        #expect(overview?.today.walkingRunningDistanceMeters == 6_400)
        #expect(overview?.updatedAt == now)
    }

    @Test func showsMissingReadAccess() async {
        let viewModel = makeViewModel(HealthServiceStub())

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .noReadAccess)
    }

    @Test func showsErrorMessageWhenLoadingFails() async {
        let service = HealthServiceStub { $0.dailyTotalsError = .protectedDataUnavailable }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
        #expect(message.contains("gesperrt"))
    }

    @Test func retryRecoversFromError() async {
        let service = HealthServiceStub { $0.dailyTotalsError = .queryFailed(reason: "Test") }
        let viewModel = makeViewModel(service)
        await viewModel.loadIfNeeded()

        service.update {
            $0.dailyTotalsError = nil
            $0.setSteps(1_000, on: today)
        }
        await viewModel.retry()

        #expect(todaysCompetitionSteps(viewModel) == 1_000)
    }

    @Test func loadIfNeededDoesNotReloadLoadedData() async {
        let service = HealthServiceStub { $0.setSteps(10, on: today) }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()
        let requestsAfterFirstLoad = service.recordedCalls.dailyTotalsRequests.count
        await viewModel.loadIfNeeded()

        #expect(service.recordedCalls.dailyTotalsRequests.count == requestsAfterFirstLoad)
    }

    @Test func refreshPicksUpGrantedAccess() async {
        let service = HealthServiceStub()
        let viewModel = makeViewModel(service)
        await viewModel.loadIfNeeded()
        #expect(viewModel.state == .noReadAccess)

        // Nutzer erlaubt den Zugriff in der Health-App und kehrt zurück.
        service.update { $0.setSteps(2_500, on: today) }
        await viewModel.refresh()

        #expect(todaysCompetitionSteps(viewModel) == 2_500)
    }

    @Test func reloadsWhenActivityDataChanges() async throws {
        let service = HealthServiceStub { $0.setSteps(100, on: today) }
        let viewModel = makeViewModel(service)
        await viewModel.loadIfNeeded()

        let observation = Task { await viewModel.observeActivityChanges() }
        defer { observation.cancel() }
        try await waitUntil { service.activeChangeObservers == 1 }

        service.update { $0.setSteps(250, on: today) }
        service.simulateActivityChange()

        try await waitUntil { todaysCompetitionSteps(viewModel) == 250 }
    }

    @Test func stopsObservingWhenTaskIsCancelled() async throws {
        let service = HealthServiceStub { $0.setSteps(100, on: today) }
        let viewModel = makeViewModel(service)

        let observation = Task { await viewModel.observeActivityChanges() }
        try await waitUntil { service.activeChangeObservers == 1 }

        observation.cancel()
        await observation.value

        #expect(service.activeChangeObservers == 0)
    }

    // MARK: Sync

    @Test func initialLoadSubmitsForSyncAsAppStart() async throws {
        let syncing = ActivitySyncingSpy()
        let viewModel = makeViewModel(HealthServiceStub { $0.setSteps(1_234, on: today) }, syncing: syncing)

        await viewModel.loadIfNeeded()

        try await waitUntil { syncing.triggers == [.appStart] }
        #expect(syncing.state.current.submissions.first?.overview.today.competitionSteps == 1_234)
    }

    @Test func refreshTriggersAreForwarded() async throws {
        let syncing = ActivitySyncingSpy()
        let viewModel = makeViewModel(HealthServiceStub { $0.setSteps(10, on: today) }, syncing: syncing)
        await viewModel.loadIfNeeded()

        await viewModel.refresh(trigger: .foreground)
        await viewModel.refresh()

        try await waitUntil { syncing.triggers.count == 3 }
        #expect(syncing.triggers == [.appStart, .foreground, .pullToRefresh])
    }

    @Test func healthKitChangesSubmitAsHealthKitUpdate() async throws {
        let syncing = ActivitySyncingSpy()
        let service = HealthServiceStub { $0.setSteps(100, on: today) }
        let viewModel = makeViewModel(service, syncing: syncing)
        await viewModel.loadIfNeeded()

        let observation = Task { await viewModel.observeActivityChanges() }
        defer { observation.cancel() }
        try await waitUntil { service.activeChangeObservers == 1 }
        service.simulateActivityChange()

        try await waitUntil { syncing.triggers.contains(.healthKitUpdate) }
    }

    @Test func nothingIsSubmittedWithoutReadAccessOrOnError() async throws {
        let syncing = ActivitySyncingSpy()
        let noAccess = makeViewModel(HealthServiceStub(), syncing: syncing)
        let failing = makeViewModel(HealthServiceStub { $0.dailyTotalsError = .queryFailed(reason: "x") }, syncing: syncing)

        await noAccess.loadIfNeeded()
        await failing.loadIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        #expect(syncing.triggers.isEmpty)
    }
}
