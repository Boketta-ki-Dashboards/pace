import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivityPeriodSummaryTests {
    private func day(_ dayOfMonth: Int, health: Int, competition: Int, distance: Double? = nil, energy: Double? = nil) -> DailyActivitySummary {
        DailyActivitySummary(
            date: Fixtures.day(2026, 10, dayOfMonth),
            healthSteps: health,
            competitionSteps: competition,
            walkingRunningDistanceMeters: distance,
            activeEnergyKilocalories: energy
        )
    }

    @Test func sortsDaysChronologically() {
        let summary = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(12, health: 1, competition: 1),
            day(10, health: 1, competition: 1),
            day(11, health: 1, competition: 1),
        ])

        #expect(summary.days.map(\.date.day) == [10, 11, 12])
    }

    @Test func totalsAndAverageUseCompetitionSteps() {
        let summary = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(10, health: 5_000, competition: 4_000),
            day(11, health: 6_000, competition: 6_000),
            day(12, health: 3_001, competition: 3_001),
        ])

        #expect(summary.totalCompetitionSteps == 13_001)
        #expect(summary.totalHealthSteps == 14_001)
        #expect(summary.averageCompetitionStepsPerDay == 4_334)
    }

    @Test func averageOfEmptyPeriodIsZero() {
        #expect(ActivityPeriodSummary(period: .today, days: []).averageCompetitionStepsPerDay == 0)
    }

    @Test func bestDayIsHighestCompetitionStepsAndPrefersMoreRecentOnTie() {
        let summary = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(10, health: 9_000, competition: 7_000),
            day(11, health: 7_000, competition: 7_000),
            day(12, health: 8_000, competition: 2_000),
        ])

        #expect(summary.bestDay?.date == Fixtures.day(2026, 10, 11))
    }

    @Test func bestDayIsNilWithoutAnySteps() {
        let summary = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(10, health: 0, competition: 0),
            day(11, health: 0, competition: 0),
        ])

        #expect(summary.bestDay == nil)
    }

    @Test func optionalTotalsAreNilWhenMetricUnavailable() {
        let summary = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(10, health: 1, competition: 1),
            day(11, health: 1, competition: 1),
        ])

        #expect(summary.totalWalkingRunningDistanceMeters == nil)
        #expect(summary.totalActiveEnergyKilocalories == nil)
        #expect(summary.totalFlightsClimbed == nil)
        #expect(summary.totalExerciseMinutes == nil)
    }

    @Test func optionalTotalsSumAvailableValues() {
        let summary = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(10, health: 1, competition: 1, distance: 1_500, energy: 200),
            day(11, health: 1, competition: 1, distance: 0, energy: 150.5),
        ])

        #expect(summary.totalWalkingRunningDistanceMeters == 1_500)
        #expect(summary.totalActiveEnergyKilocalories == 350.5)
    }

    @Test func detectsNonCompetitionSteps() {
        let equal = ActivityPeriodSummary(period: .today, days: [day(10, health: 100, competition: 100)])
        let different = ActivityPeriodSummary(period: .lastSevenDays, days: [
            day(10, health: 100, competition: 100),
            day(11, health: 500, competition: 100),
        ])

        #expect(!equal.hasNonCompetitionSteps)
        #expect(different.hasNonCompetitionSteps)
    }
}
