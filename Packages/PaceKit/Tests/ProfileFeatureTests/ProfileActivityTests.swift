import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import ProfileFeature
import Testing

/// Profil: Tagesziel, Serie, Rekord und Zugang zur Statistik.
@MainActor
struct ProfileActivityTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 16)
    private let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 9) }

    private final class LiveSource: ActivityOverviewSource {
        var detailsState: ActivityDetailsState = .loading
        func refresh() async {}
    }

    private func makeViewModel(withActivity: Bool) -> (ProfileViewModel, StepStreakTracker) {
        let profile = Fixtures.profile()
        let regions = RegionRepositoryStub()
        let store = ProfileStore(
            profile: profile,
            profiles: ProfileRepositoryStub { $0.profiles[profile.id] = profile },
            regions: regions,
            cache: InMemoryProfileCache()
        )
        let health = HealthServiceStub { configuration in
            for offset in -3 ... -1 { configuration.setSteps(12_000, on: calendar.adding(offset, to: today)) }
        }
        let live = LiveSource()
        let tracker = StepStreakTracker(
            history: ActivityHistoryStore(activityData: health, live: live, calendar: calendar, now: now),
            goals: StepGoalSettings(store: InMemoryStepGoalStore(), calendar: calendar, now: now),
            recordStore: InMemoryStepStreakRecordStore(),
            calendar: calendar,
            now: now
        )
        let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: calendar)
        var statistics: (@MainActor (StatisticsRoute) -> StatisticsViewModel)?
        if withActivity {
            statistics = { [calendar, now] route in
                StatisticsViewModel(route: route, streak: tracker, activityData: health, live: live, calendar: calendar, now: now)
            }
        }
        let viewModel = ProfileViewModel(
            store: store,
            regions: regions,
            streak: withActivity ? tracker : nil,
            statistics: statistics,
            formatter: formatter,
            searchDebounce: .zero
        )
        return (viewModel, tracker)
    }

    @Test func showsGoalStreakRecordAndStatistics() async {
        let (viewModel, tracker) = makeViewModel(withActivity: true)
        #expect(viewModel.goalText == "10.000 Schritte")
        #expect(viewModel.streakSummary == nil)

        await viewModel.loadActivity()

        #expect(viewModel.streakSummary?.currentText == "3 Tage")
        #expect(viewModel.streakSummary?.recordText == "Rekord: 3 Tage")
        #expect(viewModel.showsStatistics)
        #expect(viewModel.statistics(for: StatisticsRoute(period: .month))?.period == .month)

        tracker.goals.setGoal(12_500)
        #expect(viewModel.goalText == "12.500 Schritte")
        // Die Vortage behalten ihr Ziel (10.000) – die Serie bleibt.
        #expect(viewModel.streakSummary?.currentDays == 3)
    }

    @Test func withoutActivityTheCardIsHidden() async {
        let (viewModel, _) = makeViewModel(withActivity: false)

        await viewModel.loadActivity()

        #expect(viewModel.goalText == nil)
        #expect(viewModel.streakSummary == nil)
        #expect(!viewModel.showsStatistics)
        #expect(viewModel.statistics(for: StatisticsRoute(period: .week)) == nil)
    }
}
