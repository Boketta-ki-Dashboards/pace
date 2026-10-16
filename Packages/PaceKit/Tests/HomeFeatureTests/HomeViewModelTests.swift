import Foundation
import HomeFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct HomeViewModelTests {
    private let now = Fixtures.date(2026, 10, 16, 9, 15)
    private let today = Fixtures.date(2026, 10, 16)

    private func makeViewModel(_ service: HealthServiceStub) -> HomeViewModel {
        let currentDate = now
        return HomeViewModel(stepCounts: service, calendar: Fixtures.calendar, now: { currentDate })
    }

    @Test func startsInLoadingState() {
        let viewModel = makeViewModel(HealthServiceStub())

        #expect(viewModel.state == .loading)
    }

    @Test func showsTodaysSteps() async {
        let service = HealthServiceStub { $0.stepCount = .success(4_200) }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .loaded(DailyStepCount(day: today, steps: 4_200, updatedAt: now)))
    }

    @Test func showsMissingReadAccess() async {
        let service = HealthServiceStub {
            $0.stepCount = .success(nil)
            $0.hasAnyStepSamples = .success(false)
        }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()

        #expect(viewModel.state == .noReadAccess)
    }

    @Test func showsErrorMessageWhenLoadingFails() async {
        let service = HealthServiceStub { $0.stepCount = .failure(.protectedDataUnavailable) }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
        #expect(message.contains("gesperrt"))
    }

    @Test func retryRecoversFromError() async {
        let service = HealthServiceStub { $0.stepCount = .failure(.queryFailed(reason: "Test")) }
        let viewModel = makeViewModel(service)
        await viewModel.loadIfNeeded()

        service.update { $0.stepCount = .success(1_000) }
        await viewModel.retry()

        #expect(viewModel.state == .loaded(DailyStepCount(day: today, steps: 1_000, updatedAt: now)))
    }

    @Test func loadIfNeededDoesNotReloadLoadedData() async {
        let service = HealthServiceStub { $0.stepCount = .success(10) }
        let viewModel = makeViewModel(service)

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        #expect(service.recordedCalls.stepCountIntervals.count == 1)
    }

    @Test func refreshPicksUpGrantedAccess() async {
        let service = HealthServiceStub {
            $0.stepCount = .success(nil)
            $0.hasAnyStepSamples = .success(false)
        }
        let viewModel = makeViewModel(service)
        await viewModel.loadIfNeeded()
        #expect(viewModel.state == .noReadAccess)

        // Nutzer erlaubt den Zugriff in der Health-App und kehrt zurück.
        service.update { $0.stepCount = .success(2_500) }
        await viewModel.refresh()

        #expect(viewModel.state == .loaded(DailyStepCount(day: today, steps: 2_500, updatedAt: now)))
    }

    @Test func reloadsWhenStepDataChanges() async throws {
        let service = HealthServiceStub { $0.stepCount = .success(100) }
        let viewModel = makeViewModel(service)
        await viewModel.loadIfNeeded()

        let observation = Task { await viewModel.observeStepChanges() }
        defer { observation.cancel() }
        try await waitUntil { service.activeChangeObservers == 1 }

        service.update { $0.stepCount = .success(250) }
        service.simulateStepCountChange()

        try await waitUntil {
            viewModel.state == .loaded(DailyStepCount(day: today, steps: 250, updatedAt: now))
        }
    }

    @Test func stopsObservingWhenTaskIsCancelled() async throws {
        let service = HealthServiceStub { $0.stepCount = .success(100) }
        let viewModel = makeViewModel(service)

        let observation = Task { await viewModel.observeStepChanges() }
        try await waitUntil { service.activeChangeObservers == 1 }

        observation.cancel()
        await observation.value

        #expect(service.activeChangeObservers == 0)
    }
}
