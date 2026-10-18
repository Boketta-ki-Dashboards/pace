import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivityHistoryTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 16)

    @Test func loadsEveryDayFromTheFirstDayUntilTodayWithOneQueryPerMetric() async throws {
        let health = HealthServiceStub { configuration in
            configuration.setSteps(7_000, on: Fixtures.day(2026, 9, 3))
            configuration.setSteps(9_000, competition: 8_000, on: today)
            configuration.set(.walkingRunningDistance, 5_000, on: today)
        }
        let loader = ActivitySummaryLoader(provider: health, calendar: calendar, now: { Fixtures.date(2026, 10, 16, 12) })

        guard case .available(let history) = try await loader.loadHistory(from: Fixtures.day(2026, 9, 1)) else {
            Issue.record("Verlauf erwartet")
            return
        }

        #expect(history.range == Fixtures.day(2026, 9, 1)...today)
        #expect(history.summaries(from: Fixtures.day(2026, 9, 1), through: today, calendar: calendar).count == 46)
        #expect(history.summary(for: Fixtures.day(2026, 9, 3))?.competitionSteps == 7_000)
        #expect(history.summary(for: Fixtures.day(2026, 9, 4))?.competitionSteps == 0)
        #expect(history.summary(for: today)?.healthSteps == 9_000)
        #expect(history.summary(for: today)?.competitionSteps == 8_000)
        // Distanz ist lesbar → Tage ohne Samples sind 0; Stockwerke gar nicht lesbar → nil statt 0.
        #expect(history.summary(for: Fixtures.day(2026, 9, 3))?.walkingRunningDistanceMeters == 0)
        #expect(history.summary(for: today)?.flightsClimbed == nil)
        #expect(history.summary(for: Fixtures.day(2026, 8, 31)) == nil)
        #expect(health.recordedCalls.dailyTotalsRequests.count == ActivityMetric.allCases.count)
    }

    @Test func historyWithoutReadableStepsReportsNoAccess() async throws {
        let loader = ActivitySummaryLoader(provider: HealthServiceStub(), calendar: calendar, now: { Fixtures.date(2026, 10, 16, 12) })
        #expect(try await loader.loadHistory(from: Fixtures.day(2026, 9, 1)) == .noReadAccess)
    }

    @Test func mergingReplacesRecentDaysAndExtendsToTheNewDay() {
        let days = calendar.days(from: Fixtures.day(2026, 10, 10), through: today).map {
            DailyActivitySummary(date: $0, healthSteps: 1_000, competitionSteps: 1_000)
        }
        let history = ActivityHistory(days: days, range: Fixtures.day(2026, 10, 10)...today, updatedAt: Fixtures.date(2026, 10, 16, 12))
        let tomorrow = Fixtures.day(2026, 10, 17)

        let merged = history.merging([
            DailyActivitySummary(date: today, healthSteps: 5_000, competitionSteps: 5_000),
            DailyActivitySummary(date: tomorrow, healthSteps: 200, competitionSteps: 200),
            DailyActivitySummary(date: Fixtures.day(2026, 10, 1), healthSteps: 9, competitionSteps: 9),
        ])

        #expect(merged.range == Fixtures.day(2026, 10, 10)...tomorrow)
        #expect(merged.summary(for: today)?.competitionSteps == 5_000)
        #expect(merged.summary(for: tomorrow)?.competitionSteps == 200)
        #expect(merged.summary(for: Fixtures.day(2026, 10, 1)) == nil)
    }

    @Test func gapsAfterMergingStayUnknown() {
        let history = ActivityHistory(
            days: [DailyActivitySummary(date: Fixtures.day(2026, 10, 1), healthSteps: 1, competitionSteps: 1)],
            range: Fixtures.day(2026, 10, 1)...Fixtures.day(2026, 10, 1),
            updatedAt: Fixtures.date(2026, 10, 1, 12)
        )

        let merged = history.merging([DailyActivitySummary(date: today, healthSteps: 2, competitionSteps: 2)])

        #expect(merged.summary(for: Fixtures.day(2026, 10, 8)) == nil)
        #expect(merged.summaries(from: Fixtures.day(2026, 10, 1), through: today, calendar: calendar).count == 2)
    }

    @Test func monthHelpers() {
        #expect(calendar.startOfMonth(containing: today) == Fixtures.day(2026, 10, 1))
        #expect(calendar.endOfMonth(containing: today) == Fixtures.day(2026, 10, 31))
        #expect(calendar.endOfMonth(containing: Fixtures.day(2028, 2, 10)) == Fixtures.day(2028, 2, 29))
        #expect(calendar.addingMonths(-12, to: Fixtures.day(2026, 10, 1)) == Fixtures.day(2025, 10, 1))
        #expect(calendar.addingMonths(1, to: Fixtures.day(2026, 1, 31)) == Fixtures.day(2026, 2, 28))
        #expect(calendar.addingMonths(3, to: Fixtures.day(2026, 11, 15)) == Fixtures.day(2027, 2, 15))
        #expect(calendar.endOfWeek(containing: today) == Fixtures.day(2026, 10, 18))
    }
}
