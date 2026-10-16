import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivityCalendarTests {
    private let calendar = Fixtures.activityCalendar

    @Test func dayUsesLocalTimeZoneNotUTC() {
        // 00:30 Uhr in Berlin ist in UTC noch der Vortag.
        let date = Fixtures.date(2026, 10, 16, 0, 30)

        #expect(calendar.day(containing: date) == Fixtures.day(2026, 10, 16))
    }

    @Test func dayIntervalIsHalfOpenLocalMidnightToMidnight() {
        let interval = calendar.interval(for: Fixtures.day(2026, 10, 16))

        #expect(interval.start == Fixtures.date(2026, 10, 16))
        #expect(interval.end == Fixtures.date(2026, 10, 17))
    }

    @Test func dayIntervalRespectsDaylightSavingTimeEnd() {
        // In Berlin endet die Sommerzeit am 25.10.2026 – der Tag hat 25 Stunden.
        let interval = calendar.interval(for: Fixtures.day(2026, 10, 25))

        #expect(interval.start == Fixtures.date(2026, 10, 25))
        #expect(interval.duration == 25 * 60 * 60)
    }

    @Test func dayIntervalRespectsDaylightSavingTimeStart() {
        // Am 29.03.2026 beginnt die Sommerzeit – der Tag hat 23 Stunden.
        let interval = calendar.interval(for: Fixtures.day(2026, 3, 29))

        #expect(interval.duration == 23 * 60 * 60)
    }

    @Test func addingDaysCrossesDSTMonthAndYearBoundaries() {
        #expect(calendar.adding(1, to: Fixtures.day(2026, 10, 25)) == Fixtures.day(2026, 10, 26))
        #expect(calendar.adding(-1, to: Fixtures.day(2026, 3, 30)) == Fixtures.day(2026, 3, 29))
        #expect(calendar.adding(1, to: Fixtures.day(2026, 12, 31)) == Fixtures.day(2027, 1, 1))
        #expect(calendar.adding(-6, to: Fixtures.day(2026, 3, 2)) == Fixtures.day(2026, 2, 24))
    }

    @Test func listsDaysInclusive() {
        let days = calendar.days(from: Fixtures.day(2026, 10, 24), through: Fixtures.day(2026, 10, 26))

        #expect(days == [Fixtures.day(2026, 10, 24), Fixtures.day(2026, 10, 25), Fixtures.day(2026, 10, 26)])
    }

    @Test func multiDayIntervalSpansFromFirstStartToLastEnd() {
        let interval = calendar.interval(from: Fixtures.day(2026, 10, 19), through: Fixtures.day(2026, 10, 25))

        #expect(interval.start == Fixtures.date(2026, 10, 19))
        #expect(interval.end == Fixtures.date(2026, 10, 26))
        #expect(interval.duration == (7 * 24 + 1) * 60 * 60)
    }

    @Test(arguments: [
        (Fixtures.day(2026, 10, 12), Fixtures.day(2026, 10, 12)), // Montag
        (Fixtures.day(2026, 10, 16), Fixtures.day(2026, 10, 12)), // Freitag
        (Fixtures.day(2026, 10, 18), Fixtures.day(2026, 10, 12)), // Sonntag
        (Fixtures.day(2027, 1, 1), Fixtures.day(2026, 12, 28)),   // Woche über den Jahreswechsel
    ])
    func weekStartsOnMonday(day: LocalDate, expectedMonday: LocalDate) {
        #expect(calendar.startOfWeek(containing: day) == expectedMonday)
    }

    @Test func weekStartIsIndependentOfDeviceLocale() {
        // Auch in einer US-Zeitzone beginnt die Pace-Woche am Montag.
        let newYork = ActivityCalendar(timeZone: TimeZone(identifier: "America/New_York")!)

        #expect(newYork.startOfWeek(containing: Fixtures.day(2026, 10, 18)) == Fixtures.day(2026, 10, 12))
    }
}
