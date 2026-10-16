import Foundation

public enum Fixtures {
    /// Gregorianischer Kalender in Berlin, damit Tagesgrenzen und Sommerzeit deterministisch sind.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    public static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }
}

public struct WaitTimeoutError: Error {}

/// Wartet, bis `condition` erfüllt ist, und gibt dabei den Main Actor frei.
@MainActor
public func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitTimeoutError() }
        try await Task.sleep(for: .milliseconds(5))
    }
}
