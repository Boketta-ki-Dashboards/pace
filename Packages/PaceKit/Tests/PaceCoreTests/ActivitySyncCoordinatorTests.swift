import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivitySyncCoordinatorTests {
    private let today = Fixtures.day(2026, 10, 16)

    private func overview(steps: [Int], updatedAt: Date = Fixtures.date(2026, 10, 16, 12)) -> ActivityOverview {
        let calendar = Fixtures.activityCalendar
        let days = steps.enumerated().map { index, value in
            DailyActivitySummary(
                date: calendar.adding(index - (steps.count - 1), to: today),
                healthSteps: value + 100,
                competitionSteps: value
            )
        }
        return ActivityOverview(
            today: days.last!,
            yesterday: days[days.count - 2],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: Array(days.suffix(5))),
            lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: days),
            updatedAt: updatedAt
        )
    }

    private let week = [1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000]

    private func makeCoordinator(clock: Locked<Date>) -> (ActivitySyncCoordinator, ActivitySyncRepositoryStub) {
        let repository = ActivitySyncRepositoryStub()
        let coordinator = ActivitySyncCoordinator(
            repository: repository,
            userID: Fixtures.userID,
            minimumInterval: 60,
            now: { clock.current }
        )
        return (coordinator, repository)
    }

    @Test func firstSyncSendsAllSevenDaysWithCompetitionStepsOnly() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))

        await coordinator.submit(overview(steps: week), trigger: .appStart)

        let uploads = repository.state.current.uploads
        #expect(uploads.count == 1)
        #expect(uploads[0].map(\.competitionSteps) == week)
        #expect(uploads[0].last?.date == today)
        #expect(uploads[0].first?.date == Fixtures.day(2026, 10, 10))
        #expect(await coordinator.pendingDays.isEmpty)
    }

    @Test func unchangedValuesAreNotSentAgain() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))

        await coordinator.submit(overview(steps: week), trigger: .appStart)
        await coordinator.submit(overview(steps: week), trigger: .foreground)

        #expect(repository.state.current.uploads.count == 1)
    }

    @Test func onlyChangedDaysAreSent() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))
        await coordinator.submit(overview(steps: week), trigger: .appStart)

        var changed = week
        changed[6] = 7_500
        await coordinator.submit(overview(steps: changed), trigger: .pullToRefresh)

        #expect(repository.state.current.uploads.last == [DailyCompetitionSteps(date: today, competitionSteps: 7_500)])
    }

    @Test func healthKitUpdatesAreThrottledAndFlushedLater() async {
        let clock = Locked(Fixtures.date(2026, 10, 16, 12))
        let (coordinator, repository) = makeCoordinator(clock: clock)
        await coordinator.submit(overview(steps: week), trigger: .appStart)

        var changed = week
        changed[6] = 7_100
        clock.withLock { $0 += 10 }
        await coordinator.submit(overview(steps: changed), trigger: .healthKitUpdate)

        #expect(repository.state.current.uploads.count == 1)
        #expect(await coordinator.pendingDays == [DailyCompetitionSteps(date: today, competitionSteps: 7_100)])

        await coordinator.flush()

        #expect(repository.state.current.uploads.count == 2)
        #expect(await coordinator.pendingDays.isEmpty)
    }

    @Test func healthKitUpdateAfterIntervalIsSentImmediately() async {
        let clock = Locked(Fixtures.date(2026, 10, 16, 12))
        let (coordinator, repository) = makeCoordinator(clock: clock)
        await coordinator.submit(overview(steps: week), trigger: .appStart)

        var changed = week
        changed[6] = 7_200
        clock.withLock { $0 += 61 }
        await coordinator.submit(overview(steps: changed), trigger: .healthKitUpdate)

        #expect(repository.state.current.uploads.count == 2)
    }

    @Test func failedSyncKeepsValuesPendingAndRetries() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))
        repository.state.withLock { $0.error = .network }

        await coordinator.submit(overview(steps: week), trigger: .appStart)

        #expect(await coordinator.status == .failed(.network))
        #expect(await coordinator.pendingDays.count == 7)

        repository.state.withLock { $0.error = nil }
        await coordinator.flush()

        #expect(repository.state.current.uploads.count == 1)
        #expect(await coordinator.pendingDays.isEmpty)
        guard case .synced = await coordinator.status else {
            Issue.record("Expected synced status")
            return
        }
    }

    @Test func clampsImplausibleValuesToServerLimits() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))

        await coordinator.submit(overview(steps: [0, 0, 0, 0, 0, -5, 999_999]), trigger: .appStart)

        let values = repository.state.current.uploads[0].map(\.competitionSteps)
        #expect(values.suffix(2) == [0, DailyCompetitionSteps.maximumSteps])
    }

    @Test func olderOverviewArrivingLateIsIgnored() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))
        var newer = week
        newer[6] = 7_800

        await coordinator.submit(overview(steps: newer, updatedAt: Fixtures.date(2026, 10, 16, 12, 5)), trigger: .appStart)
        await coordinator.submit(overview(steps: week, updatedAt: Fixtures.date(2026, 10, 16, 12, 1)), trigger: .pullToRefresh)

        #expect(repository.state.current.uploads.count == 1)
        #expect(repository.state.current.uploads[0].last?.competitionSteps == 7_800)
    }

    @Test func flushWithoutPendingValuesDoesNothing() async {
        let (coordinator, repository) = makeCoordinator(clock: Locked(Fixtures.date(2026, 10, 16, 12)))

        await coordinator.flush()

        #expect(repository.state.current.uploads.isEmpty)
        #expect(await coordinator.status == .idle)
    }
}
