import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Kalender: geteilter Verlauf, Monatsnavigation im Verlaufszeitraum, Auswahl und Weg zu den Tagesdetails.
@MainActor
struct CalendarViewModelTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 17)
    private let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 17, 15, 20) }

    private final class LiveSource: ActivityOverviewSource {
        var detailsState: ActivityDetailsState = .loading
        private(set) var refreshes = 0

        func refresh() async {
            refreshes += 1
        }
    }

    private func makeViewModel(
        route: CalendarRoute = CalendarRoute(),
        health: HealthServiceStub? = nil,
        live: LiveSource = LiveSource()
    ) -> (CalendarViewModel, HealthServiceStub) {
        let health = health ?? HealthServiceStub { configuration in
            for offset in -400 ... 0 {
                configuration.setSteps(offset % 2 == 0 ? 11_000 : 7_000, on: calendar.adding(offset, to: today))
            }
        }
        let store = ActivityHistoryStore(activityData: health, live: live, calendar: calendar, now: now)
        let streak = StepStreakTracker(
            history: store,
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: calendar,
            now: now
        )
        let viewModel = CalendarViewModel(
            route: route,
            streak: streak,
            activityData: health,
            live: live,
            calendar: calendar,
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: calendar),
            now: now
        )
        return (viewModel, health)
    }

    @Test func showsTheCurrentMonthWithTodaySelectedAfterLoading() async throws {
        let (viewModel, health) = makeViewModel()
        #expect(viewModel.content == .loading)
        #expect(viewModel.monthTitle == "Oktober 2026")

        await viewModel.loadIfNeeded()

        guard case .month(let month) = viewModel.content else { throw UnexpectedStateError() }
        #expect(month.month == Fixtures.day(2026, 10, 1))
        #expect(viewModel.selectedDate == today)
        #expect(viewModel.selectedDay?.date == today)
        #expect(viewModel.selectedDay?.isToday == true)
        #expect(month.selectedCard?.date == today)
        // Der Kalender nutzt den geteilten Verlauf: eine Abfrage je Kennzahl, keine Stundenwerte.
        #expect(health.recordedCalls.dailyTotalsRequests.count == ActivityMetric.allCases.count)
        #expect(health.recordedCalls.hourlyTotalsRequests.isEmpty)
    }

    @Test func navigatesBetweenMonthsWithinTheHistory() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.loadIfNeeded()
        #expect(!viewModel.canShowNext)

        viewModel.showNext()
        #expect(viewModel.displayedMonth == Fixtures.day(2026, 10, 1))

        viewModel.showPrevious()
        #expect(viewModel.displayedMonth == Fixtures.day(2026, 9, 1))
        #expect(viewModel.monthTitle == "September 2026")
        // In früheren Monaten ist der letzte Tag ausgewählt.
        #expect(viewModel.selectedDate == Fixtures.day(2026, 9, 30))

        for _ in 0..<20 {
            viewModel.showPrevious()
        }
        #expect(viewModel.displayedMonth == Fixtures.day(2025, 10, 1))
        #expect(!viewModel.canShowPrevious)

        while viewModel.canShowNext {
            viewModel.showNext()
        }
        #expect(viewModel.displayedMonth == Fixtures.day(2026, 10, 1))
        #expect(viewModel.selectedDate == today)
    }

    @Test func selectsPastDaysOnlyInTheDisplayedMonth() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.loadIfNeeded()

        viewModel.select(Fixtures.day(2026, 10, 12))
        #expect(viewModel.selectedDate == Fixtures.day(2026, 10, 12))
        #expect(viewModel.selectedDay?.isSelected == true)

        viewModel.select(Fixtures.day(2026, 10, 20))
        #expect(viewModel.selectedDate == Fixtures.day(2026, 10, 12))

        viewModel.select(Fixtures.day(2026, 9, 12))
        #expect(viewModel.selectedDate == Fixtures.day(2026, 10, 12))
    }

    @Test func routeOpensAnEarlierMonthButNeverTheFuture() {
        let (earlier, _) = makeViewModel(route: CalendarRoute(month: Fixtures.day(2026, 3, 9)))
        #expect(earlier.displayedMonth == Fixtures.day(2026, 3, 1))
        #expect(earlier.selectedDate == Fixtures.day(2026, 3, 31))

        let (future, _) = makeViewModel(route: CalendarRoute(month: Fixtures.day(2027, 1, 1)))
        #expect(future.displayedMonth == Fixtures.day(2026, 10, 1))
        #expect(future.selectedDate == today)
    }

    @Test func dayDetailsOpenFromTheCalendar() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.loadIfNeeded()

        let details = viewModel.dayDetails(for: Fixtures.day(2026, 10, 14))

        #expect(details.day == Fixtures.day(2026, 10, 14))
        #expect(details.origin == .calendar)
        #expect(details.backTitle == "Kalender")
        guard case .report(let report) = details.content else {
            Issue.record("Kein Bericht")
            return
        }
        #expect(report.dateText == "Mittwoch, 14. Oktober 2026")
    }

    @Test func withoutStepAccessTheCalendarSaysSo() async {
        let (viewModel, _) = makeViewModel(health: HealthServiceStub())

        await viewModel.loadIfNeeded()

        #expect(viewModel.content == .noReadAccess)
        #expect(viewModel.selectedDay == nil)
    }

    @Test func refreshReadsTodayAndTheHistoryAgain() async {
        let live = LiveSource()
        let (viewModel, health) = makeViewModel(live: live)
        await viewModel.loadIfNeeded()

        await viewModel.refresh()

        #expect(live.refreshes == 1)
        #expect(health.recordedCalls.dailyTotalsRequests.count == 2 * ActivityMetric.allCases.count)
    }
}
