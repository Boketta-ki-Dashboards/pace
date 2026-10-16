import Foundation
import PaceCore

public enum Fixtures {
    /// Berlin, damit Tagesgrenzen und Sommerzeit deterministisch sind.
    public static let timeZone = TimeZone(identifier: "Europe/Berlin")!

    public static let activityCalendar = ActivityCalendar(timeZone: timeZone)

    /// Gregorianischer Kalender in Berlin.
    public static var calendar: Calendar { activityCalendar.calendar }

    public static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    public static func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)
    }
}

public struct WaitTimeoutError: Error {}

/// Ein Test hat einen anderen Zustand erhalten als erwartet (Details stehen im aufgezeichneten Issue).
public struct UnexpectedStateError: Error {
    public init() {}
}

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
