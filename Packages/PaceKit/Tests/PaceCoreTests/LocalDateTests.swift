import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct LocalDateTests {
    @Test func formatsAsISODate() {
        #expect(LocalDate(year: 2026, month: 3, day: 7).isoString == "2026-03-07")
    }

    @Test(arguments: ["2026-10-16", "2024-02-29", "2026-12-31"])
    func parsesValidISODates(_ string: String) throws {
        let date = try #require(LocalDate(isoString: string))
        #expect(date.isoString == string)
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-10-32", "26-10-16", "2026-1-16", "2026/10/16", "", "abcd-ef-gh"])
    func rejectsInvalidISODates(_ string: String) {
        #expect(LocalDate(isoString: string) == nil)
    }

    @Test func comparesChronologically() {
        #expect(Fixtures.day(2025, 12, 31) < Fixtures.day(2026, 1, 1))
        #expect(Fixtures.day(2026, 2, 28) < Fixtures.day(2026, 3, 1))
        #expect(!(Fixtures.day(2026, 3, 1) < Fixtures.day(2026, 3, 1)))
    }

    @Test func roundTripsThroughJSONAsISOString() throws {
        let date = Fixtures.day(2026, 10, 16)
        let data = try JSONEncoder().encode([date])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-10-16"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [date])
    }

    @Test func decodingInvalidStringThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDate].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
    }
}
