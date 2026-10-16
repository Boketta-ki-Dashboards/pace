import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivityPeriodTests {
    private let calendar = Fixtures.activityCalendar
    private let friday = Fixtures.day(2026, 10, 16)

    @Test func todayIsSingleDay() {
        #expect(ActivityPeriod.today.dayRange(endingOn: friday, calendar: calendar) == friday...friday)
    }

    @Test func yesterdayIsPreviousDay() {
        let yesterday = Fixtures.day(2026, 10, 15)
        #expect(ActivityPeriod.yesterday.dayRange(endingOn: friday, calendar: calendar) == yesterday...yesterday)
    }

    @Test func lastSevenDaysIncludeToday() {
        let range = ActivityPeriod.lastSevenDays.dayRange(endingOn: friday, calendar: calendar)

        #expect(range == Fixtures.day(2026, 10, 10)...friday)
        #expect(calendar.days(from: range.lowerBound, through: range.upperBound).count == 7)
    }

    @Test func currentWeekRunsFromMondayToToday() {
        #expect(ActivityPeriod.currentWeek.dayRange(endingOn: friday, calendar: calendar) == Fixtures.day(2026, 10, 12)...friday)
    }

    @Test func currentWeekOnMondayIsOnlyToday() {
        let monday = Fixtures.day(2026, 10, 12)
        #expect(ActivityPeriod.currentWeek.dayRange(endingOn: monday, calendar: calendar) == monday...monday)
    }

    @Test func currentWeekIsAlwaysWithinLastSevenDays() {
        for offset in 0..<7 {
            let today = calendar.adding(offset, to: Fixtures.day(2026, 10, 12))
            let week = ActivityPeriod.currentWeek.dayRange(endingOn: today, calendar: calendar)
            let lastSeven = ActivityPeriod.lastSevenDays.dayRange(endingOn: today, calendar: calendar)
            #expect(lastSeven.lowerBound <= week.lowerBound)
            #expect(week.upperBound == lastSeven.upperBound)
        }
    }
}
