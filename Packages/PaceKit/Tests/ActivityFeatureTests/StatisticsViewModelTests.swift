import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Die Statistik nutzt den geteilten Verlauf, liest Stundenwerte nur einmal je Tag und blättert durch Zeiträume.
@MainActor
struct StatisticsViewModelTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 16)
    private let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 9, 30) }

    /// Live-Quelle wie Home: liefert die zuletzt geladenen 7 Tage.
    private final class LiveSource: ActivityOverviewSource {
        var detailsState: ActivityDetailsState = .loading
        private(set) var refreshes = 0

        func refresh() async {
            refreshes += 1
        }
    }

    private func makeViewModel(
        route: StatisticsRoute,
        health: HealthServiceStub,
        live: LiveSource = LiveSource()
    ) -> (StatisticsViewModel, ActivityHistoryStore) {
        let store = ActivityHistoryStore(activityData: health, live: live, calendar: calendar, now: now)
        let streak = StepStreakTracker(
            history: store,
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: calendar,
            now: now
        )
        let viewModel = StatisticsViewModel(
            route: route,
            streak: streak,
            activityData: health,
            live: live,
            calendar: calendar,
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: calendar),
            now: now
        )
        return (viewModel, store)
    }

    private func healthWithHistory() -> HealthServiceStub {
        HealthServiceStub { configuration in
            for offset in -60 ... 0 {
                configuration.setSteps(6_000, on: calendar.adding(offset, to: today))
            }
            configuration.hourlyTotals[.competitionSteps] = [
                today: [7: 1_000, 8: 2_000],
                calendar.adding(-1, to: today): [7: 500, 8: 500, 9: 1_000],
                calendar.adding(-3, to: today): [12: 6_000],
            ]
        }
    }

    @Test func loadsTheHistoryOnceAndShowsTheRequestedRoute() async throws {
        let health = healthWithHistory()
        let (viewModel, store) = makeViewModel(route: StatisticsRoute(period: .week, metric: .distance), health: health)

        #expect(viewModel.content == .loading)
        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        guard case .report(let report) = viewModel.content else { throw UnexpectedStateError() }
        #expect(report.period == .week)
        #expect(report.metric == .distance)
        #expect(store.history?.range.lowerBound == Fixtures.day(2025, 10, 1))
        // Ein Ladevorgang: eine Abfrage je Kennzahl.
        #expect(health.recordedCalls.dailyTotalsRequests.count == ActivityMetric.allCases.count)
        #expect(viewModel.hourlyKey == nil)
    }

    @Test func dayViewLoadsHourlyValuesWithTheDayBeforeForToday() async throws {
        let health = healthWithHistory()
        let (viewModel, _) = makeViewModel(route: StatisticsRoute(period: .day), health: health)
        await viewModel.loadIfNeeded()

        await viewModel.loadHourly()

        #expect(viewModel.hourlyValues?.values == [7: 1_000, 8: 2_000])
        #expect(viewModel.hourlyValues?.previousDay == [7: 500, 8: 500, 9: 1_000])
        #expect(health.recordedCalls.hourlyTotalsRequests.map(\.day) == [today, calendar.adding(-1, to: today)])
        guard case .report(let report) = viewModel.content else { throw UnexpectedStateError() }
        #expect(report.bars.count == 24)
    }

    @Test func pastDaysAreReadOnceAndReused() async {
        let health = healthWithHistory()
        let (viewModel, _) = makeViewModel(route: StatisticsRoute(period: .week), health: health)
        await viewModel.loadIfNeeded()
        let tuesday = calendar.adding(-3, to: today)

        viewModel.showDay(tuesday)
        #expect(viewModel.period == .day)
        await viewModel.loadHourly()
        viewModel.select(.distance)
        await viewModel.loadHourly()
        viewModel.select(.steps)
        await viewModel.loadHourly()

        #expect(viewModel.hourlyValues?.values == [12: 6_000])
        #expect(viewModel.hourlyValues?.previousDay == nil)
        let stepRequests = health.recordedCalls.hourlyTotalsRequests.filter { $0.metric == .competitionSteps }
        #expect(stepRequests.map(\.day) == [tuesday])
    }

    @Test func navigatesBetweenPeriodsWithinTheHistory() async throws {
        let health = healthWithHistory()
        let (viewModel, _) = makeViewModel(route: StatisticsRoute(period: .month), health: health)
        await viewModel.loadIfNeeded()

        viewModel.showNext() // kein Monat in der Zukunft
        #expect(viewModel.anchor == today)

        viewModel.showPrevious()
        #expect(viewModel.anchor == Fixtures.day(2026, 9, 16))
        for _ in 0 ..< 20 { viewModel.showPrevious() }
        #expect(viewModel.anchor == Fixtures.day(2025, 10, 16)) // erster Monat des Verlaufs
        guard case .report(let report) = viewModel.content else { throw UnexpectedStateError() }
        #expect(!report.canShowPrevious)

        viewModel.select(.day)
        viewModel.showDay(calendar.adding(1, to: today)) // Zukunft: ignoriert
        #expect(viewModel.anchor == Fixtures.day(2025, 10, 16))
    }

    @Test func futureRouteDayIsClampedToToday() {
        let (viewModel, _) = makeViewModel(
            route: StatisticsRoute(period: .day, day: Fixtures.day(2026, 12, 24)),
            health: healthWithHistory()
        )
        #expect(viewModel.anchor == today)
    }

    @Test func failedHourlyLoadIsReported() async {
        let health = healthWithHistory()
        let (viewModel, _) = makeViewModel(route: StatisticsRoute(period: .day), health: health)
        await viewModel.loadIfNeeded()
        health.update { $0.dailyTotalsError = .queryFailed(reason: "Test") }

        await viewModel.loadHourly()

        #expect(viewModel.hourly == .failed)
    }

    @Test func missingReadAccessIsShown() async {
        let (viewModel, _) = makeViewModel(route: StatisticsRoute(period: .week), health: HealthServiceStub())

        await viewModel.loadIfNeeded()

        #expect(viewModel.content == .noReadAccess)
    }

    @Test func refreshReadsTodayAndTheHistoryAgain() async {
        let health = healthWithHistory()
        let live = LiveSource()
        let (viewModel, _) = makeViewModel(route: StatisticsRoute(period: .week), health: health, live: live)
        await viewModel.loadIfNeeded()

        await viewModel.refresh()

        #expect(live.refreshes == 1)
        #expect(health.recordedCalls.dailyTotalsRequests.count == 2 * ActivityMetric.allCases.count)
    }
}

/// Der geteilte Verlauf lädt selten und ergänzt die live aktualisierten letzten 7 Tage.
@MainActor
struct ActivityHistoryStoreTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 16)

    private final class LiveSource: ActivityOverviewSource {
        var detailsState: ActivityDetailsState = .loading
        func refresh() async {}
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date

        init(_ value: Date) { self.value = value }

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ date: Date) {
            lock.lock()
            value = date
            lock.unlock()
        }
    }

    @Test func reloadsOnlyWhenStaleOrOnANewDay() async {
        let health = HealthServiceStub { $0.setSteps(5_000, on: Fixtures.day(2026, 10, 1)) }
        let clock = Clock(Fixtures.date(2026, 10, 16, 9))
        let store = ActivityHistoryStore(activityData: health, live: LiveSource(), calendar: calendar, maximumAge: 3_600, now: { clock.now })
        let perLoad = ActivityMetric.allCases.count

        await store.loadIfNeeded()
        clock.set(Fixtures.date(2026, 10, 16, 9, 50))
        await store.loadIfNeeded()
        #expect(health.recordedCalls.dailyTotalsRequests.count == perLoad)

        clock.set(Fixtures.date(2026, 10, 16, 10, 5)) // älter als eine Stunde
        await store.loadIfNeeded()
        #expect(health.recordedCalls.dailyTotalsRequests.count == 2 * perLoad)

        clock.set(Fixtures.date(2026, 10, 17, 0, 1)) // neuer Tag
        await store.loadIfNeeded()
        #expect(health.recordedCalls.dailyTotalsRequests.count == 3 * perLoad)
        #expect(store.history?.range.upperBound == Fixtures.day(2026, 10, 17))
    }

    @Test func concurrentRequestsShareOneLoad() async {
        let health = HealthServiceStub { $0.setSteps(5_000, on: Fixtures.day(2026, 10, 1)) }
        let store = ActivityHistoryStore(activityData: health, live: LiveSource(), calendar: calendar, now: { Fixtures.date(2026, 10, 16, 9) })

        async let first: Void = store.loadIfNeeded()
        async let second: Void = store.reload()
        _ = await (first, second)

        #expect(health.recordedCalls.dailyTotalsRequests.count == ActivityMetric.allCases.count)
        #expect(store.state == .loaded)
    }

    @Test func liveDaysReplaceTheLoadedOnes() async {
        let health = HealthServiceStub { $0.setSteps(5_000, on: Fixtures.day(2026, 10, 16)) }
        let live = LiveSource()
        let store = ActivityHistoryStore(activityData: health, live: live, calendar: calendar, now: { Fixtures.date(2026, 10, 16, 9) })
        await store.loadIfNeeded()

        let days = calendar.days(from: calendar.adding(-6, to: today), through: today).map {
            DailyActivitySummary(date: $0, healthSteps: $0 == today ? 7_500 : 0, competitionSteps: $0 == today ? 7_500 : 0)
        }
        live.detailsState = .loaded(ActivityOverview(
            today: days[6],
            yesterday: days[5],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: Array(days.suffix(5))),
            lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: days),
            updatedAt: Fixtures.date(2026, 10, 16, 10)
        ), notice: nil)

        #expect(store.history?.summary(for: today)?.competitionSteps == 7_500)
    }

    @Test func withoutReadAccessItDoesNotAskOnEveryAppearance() async {
        let health = HealthServiceStub()
        let store = ActivityHistoryStore(activityData: health, live: LiveSource(), calendar: calendar, now: { Fixtures.date(2026, 10, 16, 9) })

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(store.state == .noReadAccess)
        #expect(health.recordedCalls.dailyTotalsRequests.count == ActivityMetric.allCases.count)
    }

    @Test func failureKeepsThePreviousHistory() async {
        let health = HealthServiceStub { $0.setSteps(5_000, on: Fixtures.day(2026, 10, 16)) }
        let store = ActivityHistoryStore(activityData: health, live: LiveSource(), calendar: calendar, now: { Fixtures.date(2026, 10, 16, 9) })
        await store.loadIfNeeded()
        health.update { $0.dailyTotalsError = .queryFailed(reason: "Test") }

        await store.reload()

        #expect(store.history?.summary(for: Fixtures.day(2026, 10, 16))?.competitionSteps == 5_000)
        if case .failed = store.state {} else { Issue.record("Fehlerzustand erwartet") }
    }
}

/// Streak und Rekord aus Verlauf und Zielverlauf.
@MainActor
struct StepStreakTrackerTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 16)

    private final class LiveSource: ActivityOverviewSource {
        var detailsState: ActivityDetailsState = .loading
        func refresh() async {}
    }

    @Test func computesTheStreakAndStoresANewRecord() async {
        let health = HealthServiceStub { configuration in
            for offset in -4 ... -1 { configuration.setSteps(10_000, on: calendar.adding(offset, to: today)) }
        }
        let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 9) }
        let records = InMemoryStepStreakRecordStore(StepStreakRecord(days: 2, start: Fixtures.day(2026, 1, 1), end: Fixtures.day(2026, 1, 2)))
        let tracker = StepStreakTracker(
            history: ActivityHistoryStore(activityData: health, live: LiveSource(), calendar: calendar, now: now),
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: records,
            calendar: calendar,
            now: now
        )
        #expect(tracker.streak == nil)
        #expect(tracker.record?.days == 2)

        await tracker.loadIfNeeded()

        #expect(tracker.streak?.current == 4)
        #expect(tracker.streak?.isTodayReached == false)
        #expect(records.load()?.days == 4)
        #expect(tracker.recentDays(3).map(\.status) == [.reached, .reached, .pending])
    }
}
