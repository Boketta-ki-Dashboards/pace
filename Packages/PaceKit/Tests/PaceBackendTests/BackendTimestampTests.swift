import Foundation
@testable import PaceBackend
import Testing

struct BackendTimestampTests {
    @Test(arguments: [
        ("2026-10-16T12:34:56+00:00", 1_792_154_096.0),
        ("2026-10-16T12:34:56Z", 1_792_154_096.0),
        ("2026-10-16 12:34:56+00", 1_792_154_096.0),
        ("2026-10-16T14:34:56+02:00", 1_792_154_096.0),
        ("2026-10-16T14:34:56+0200", 1_792_154_096.0),
        ("2026-10-16T12:34:56.5+00:00", 1_792_154_096.5),
        ("2026-10-16T12:34:56.123456+00:00", 1_792_154_096.123456),
    ])
    func parsesPostgresTimestamps(string: String, expected: Double) throws {
        let date = try #require(BackendTimestamp.date(from: string))
        #expect(abs(date.timeIntervalSince1970 - expected) < 0.000_001)
    }

    @Test(arguments: ["", "2026-10-16", "2026-13-01T00:00:00Z", "2026-10-16T25:00:00Z", "gestern", "2026-10-16T12:34:56+00:00x"])
    func rejectsInvalidTimestamps(_ string: String) {
        #expect(BackendTimestamp.date(from: string) == nil)
    }
}
