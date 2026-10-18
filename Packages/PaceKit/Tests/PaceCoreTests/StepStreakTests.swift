import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct StepStreakTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 16)

    /// Verlauf ab `first` bis heute; `steps` je Tag (Tage ohne Eintrag: 0).
    private func history(from first: LocalDate, _ steps: [LocalDate: Int]) -> ActivityHistory {
        let days = calendar.days(from: first, through: today).map { day in
            DailyActivitySummary(date: day, healthSteps: steps[day] ?? 0, competitionSteps: steps[day] ?? 0)
        }
        return ActivityHistory(days: days, range: first...today, updatedAt: Fixtures.date(2026, 10, 16, 12))
    }

    private func day(_ offset: Int) -> LocalDate {
        calendar.adding(offset, to: today)
    }

    @Test func runningDayDoesNotBreakTheStreak() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        let history = history(from: day(-10), [day(-3): 10_000, day(-2): 12_000, day(-1): 10_500, day(0): 4_000])

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 3)
        #expect(streak.currentStart == day(-3))
        #expect(!streak.isTodayReached)
        #expect(streak.longest == 3)
    }

    @Test func reachedTodayCountsImmediately() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        let history = history(from: day(-10), [day(-1): 10_000, day(0): 10_000])

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 2)
        #expect(streak.isTodayReached)
        #expect(streak.longestRange == day(-1)...day(0))
    }

    @Test func aMissedDayEndsTheStreakAndTheLongestIsKept() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        var steps: [LocalDate: Int] = [:]
        for offset in -9 ... -5 { steps[day(offset)] = 11_000 } // 5 Tage
        steps[day(-4)] = 9_999 // verpasst
        for offset in -3 ... -1 { steps[day(offset)] = 11_000 } // 3 Tage
        let history = history(from: day(-20), steps)

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 3)
        #expect(streak.longest == 5)
        #expect(streak.longestRange == day(-9)...day(-5))
        #expect(!streak.reachesHistoryStart)
    }

    @Test func missingYesterdayMeansNoCurrentStreak() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        let history = history(from: day(-10), [day(-3): 10_000, day(-2): 10_000])

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 0)
        #expect(streak.currentStart == nil)
        #expect(streak.longest == 2)
    }

    @Test func eachDayUsesTheGoalThatWasValidThen() {
        // Bis gestern galt 8.000, ab heute 12.000: Die Vortage bleiben erreicht.
        var goals = StepGoalHistory(initialGoal: 8_000)
        goals.setGoal(12_000, from: today)
        let history = history(from: day(-10), [day(-2): 8_500, day(-1): 9_000, day(0): 10_000])

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 2)
        #expect(!streak.isTodayReached)
    }

    @Test func lateSyncedDataExtendsTheStreak() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        let before = history(from: day(-10), [day(-3): 10_000, day(-1): 10_000])
        // Die Apple Watch liefert die Schritte von vorgestern nach.
        let after = history(from: day(-10), [day(-3): 10_000, day(-2): 10_000, day(-1): 10_000])

        #expect(StepStreakCalculator.streak(history: before, goals: goals, today: today, calendar: calendar).current == 1)
        #expect(StepStreakCalculator.streak(history: after, goals: goals, today: today, calendar: calendar).current == 3)
    }

    @Test func streakReachingTheHistoryStartIsFlagged() {
        let goals = StepGoalHistory(initialGoal: 1_000)
        let history = history(from: day(-5), Dictionary(uniqueKeysWithValues: (-5 ... -1).map { (day($0), 5_000) }))

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 5)
        #expect(streak.reachesHistoryStart)
    }

    @Test func unknownDaysCountAsMissed() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        // Verlauf endet vor gestern (z. B. seit Tagen nicht neu geladen) – gestern ist unbekannt.
        let days = calendar.days(from: day(-5), through: day(-2)).map {
            DailyActivitySummary(date: $0, healthSteps: 10_000, competitionSteps: 10_000)
        }
        let history = ActivityHistory(days: days, range: day(-5)...day(-2), updatedAt: Fixtures.date(2026, 10, 14, 12))

        let streak = StepStreakCalculator.streak(history: history, goals: goals, today: today, calendar: calendar)

        #expect(streak.current == 0)
        #expect(streak.longest == 4)
    }

    @Test func dayStatusesForTheOverview() {
        let goals = StepGoalHistory(initialGoal: 10_000)
        let history = history(from: day(-2), [day(-2): 10_000, day(-1): 3_000, day(0): 2_000])

        let statuses = StepStreakCalculator.dayStatuses(
            history: history, goals: goals, from: day(-3), through: day(1), today: today, calendar: calendar
        )

        #expect(statuses.map(\.status) == [.unknown, .reached, .missed, .pending, .future])
    }

    @Test func recordKeepsTheLongerSeries() {
        let streak = StepStreak(
            current: 3, currentStart: day(-2), isTodayReached: true,
            longest: 4, longestRange: day(-20)...day(-17), reachesHistoryStart: false
        )
        let stored = StepStreakRecord(days: 30, start: Fixtures.day(2025, 1, 1), end: Fixtures.day(2025, 1, 30))

        #expect(StepStreakRecord.best(stored: stored, streak: streak) == stored)
        #expect(StepStreakRecord.best(stored: nil, streak: streak) == StepStreakRecord(days: 4, start: day(-20), end: day(-17)))
        #expect(StepStreakRecord.best(stored: nil, streak: .empty) == nil)
    }
}
