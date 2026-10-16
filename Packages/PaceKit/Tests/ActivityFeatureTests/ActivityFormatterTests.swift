import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct ActivityFormatterTests {
    private let formatter = ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar)

    @Test func formatsStepsWithGroupingSeparator() {
        #expect(formatter.steps(8_742) == "8.742")
        #expect(formatter.steps(0) == "0")
        #expect(formatter.steps(123_456) == "123.456")
    }

    @Test func formatsDistanceInKilometersWithOneDecimal() {
        #expect(formatter.distance(meters: 6_400) == "6,4 km")
        #expect(formatter.distance(meters: 950) == "1,0 km")
        #expect(formatter.distance(meters: 0) == "0,0 km")
    }

    @Test func formatsEnergyRounded() {
        #expect(formatter.energy(kilocalories: 382.4) == "382 kcal")
        #expect(formatter.energy(kilocalories: 1_250.6) == "1.251 kcal")
    }

    @Test func formatsExerciseMinutesAndFlights() {
        #expect(formatter.exerciseMinutes(34) == "34 Min.")
        #expect(formatter.flights(12) == "12")
    }

    @Test func formatsDatesInLocalTimeZone() {
        #expect(formatter.dayLong(Fixtures.day(2026, 10, 16)) == "Freitag, 16. Oktober")
        #expect(formatter.weekdayShort(Fixtures.day(2026, 10, 12)) == "Mo")
        #expect(formatter.time(Fixtures.date(2026, 10, 16, 17, 42)) == "17:42")
    }
}
