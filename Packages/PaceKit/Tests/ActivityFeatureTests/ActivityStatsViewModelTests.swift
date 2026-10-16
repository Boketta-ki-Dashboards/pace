import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivityStatsViewModelTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)
    private let today = Fixtures.day(2026, 10, 16)

    private func overview(
        days: [(health: Int, competition: Int)],
        distance: Double? = nil,
        energy: Double? = nil,
        flights: Int? = nil,
        exercise: Int? = nil
    ) -> ActivityOverview {
        let calendar = Fixtures.activityCalendar
        let summaries = days.enumerated().map { index, steps in
            DailyActivitySummary(
                date: calendar.adding(index - (days.count - 1), to: today),
                healthSteps: steps.health,
                competitionSteps: steps.competition,
                walkingRunningDistanceMeters: distance,
                activeEnergyKilocalories: energy,
                flightsClimbed: flights,
                exerciseMinutes: exercise
            )
        }
        let week = ActivityPeriodSummary(period: .lastSevenDays, days: summaries)
        return ActivityOverview(
            today: summaries.last!,
            yesterday: summaries[summaries.count - 2],
            currentWeek: ActivityPeriodSummary(period: .currentWeek, days: Array(summaries.suffix(5))),
            lastSevenDays: week,
            updatedAt: Fixtures.date(2026, 10, 16, 17, 42)
        )
    }

    private var sevenEqualDays: [(health: Int, competition: Int)] {
        [(1_000, 1_000), (2_000, 2_000), (3_000, 3_000), (4_000, 4_000), (5_000, 5_000), (6_000, 6_000), (8_742, 8_742)]
    }

    @Test func todayShowsCompetitionStepsAsMainValue() {
        var days = sevenEqualDays
        days[6] = (9_120, 8_742)

        let stats = ActivityStatsViewModel(overview: overview(days: days), formatter: formatter)

        #expect(stats.todayTitle == "Freitag, 16. Oktober")
        #expect(stats.todaySteps == "8.742")
        #expect(stats.todayHealthSteps == "9.120")
        #expect(stats.manualStepsNote == ActivityStatsViewModel.manualStepsNote)
    }

    @Test func noManualNoteWhenStepsMatch() {
        let stats = ActivityStatsViewModel(overview: overview(days: sevenEqualDays), formatter: formatter)

        #expect(stats.todayHealthSteps == nil)
        #expect(stats.manualStepsNote == nil)
    }

    @Test func manualNoteAppearsForDifferenceOnEarlierDay() {
        var days = sevenEqualDays
        days[2] = (3_500, 3_000)

        let stats = ActivityStatsViewModel(overview: overview(days: days), formatter: formatter)

        #expect(stats.todayHealthSteps == nil)
        #expect(stats.manualStepsNote != nil)
    }

    @Test func listsOnlyAvailableTodayMetrics() {
        let stats = ActivityStatsViewModel(
            overview: overview(days: sevenEqualDays, distance: 6_400, energy: 382.4, flights: nil, exercise: 34),
            formatter: formatter
        )

        #expect(stats.todayMetrics.map(\.kind) == [.distance, .activeEnergy, .exercise])
        #expect(stats.todayMetrics.map(\.value) == ["6,4 km", "382 kcal", "34 Min."])
    }

    @Test func unavailableMetricsAreNotShownAsZero() {
        let stats = ActivityStatsViewModel(overview: overview(days: sevenEqualDays), formatter: formatter)

        #expect(stats.todayMetrics.isEmpty)
        #expect(stats.weekTotals.map(\.kind) == [.steps])
    }

    @Test func chartContainsSevenDaysWithTodayMarked() {
        let stats = ActivityStatsViewModel(overview: overview(days: sevenEqualDays), formatter: formatter)

        #expect(stats.chartDays.count == 7)
        #expect(stats.chartDays.map(\.weekday) == ["Sa", "So", "Mo", "Di", "Mi", "Do", "Fr"])
        #expect(stats.chartDays.filter(\.isToday).map(\.date) == [today])
        #expect(stats.chartMaximum == 8_742)
    }

    @Test func weekHighlightsShowAverageAndBestDay() {
        var days = sevenEqualDays
        days[3] = (12_000, 12_000)

        let stats = ActivityStatsViewModel(overview: overview(days: days), formatter: formatter)

        // (1000+2000+3000+12000+5000+6000+8742) / 7 = 5391,7
        #expect(stats.weekHighlights.map(\.title) == ["Tagesdurchschnitt", "Bester Tag"])
        #expect(stats.weekHighlights[0].value == "5.392")
        #expect(stats.chartAverage == 5_392)
        #expect(stats.weekHighlights[1].value == "12.000")
        #expect(stats.weekHighlights[1].detail == "13. Okt.")
    }

    @Test func bestDayTodayIsLabelledToday() {
        let stats = ActivityStatsViewModel(overview: overview(days: sevenEqualDays), formatter: formatter)

        #expect(stats.weekHighlights.last?.detail == "Heute")
    }

    @Test func weekWithoutStepsHasNoBestDay() {
        let days = Array(repeating: (health: 0, competition: 0), count: 7)

        let stats = ActivityStatsViewModel(overview: overview(days: days), formatter: formatter)

        #expect(stats.weekHighlights.map(\.title) == ["Tagesdurchschnitt"])
        #expect(stats.chartMaximum == 1)
    }

    @Test func weekTotalsIncludeDistanceAndEnergyWhenAvailable() {
        let stats = ActivityStatsViewModel(
            overview: overview(days: sevenEqualDays, distance: 1_000, energy: 100),
            formatter: formatter
        )

        #expect(stats.weekTotals.map(\.kind) == [.steps, .distance, .activeEnergy])
        #expect(stats.weekTotals.map(\.value) == ["29.742", "7,0 km", "700 kcal"])
    }
}
