import Foundation

/// Ein Kalendertag ohne Uhrzeit und Zeitzone, z. B. `2026-10-16`.
///
/// Wird überall verwendet, wo ein „Tag“ gemeint ist (Tageswerte, Sync, Rankings). Die Umrechnung von und zu
/// `Date` erfolgt ausschließlich über `ActivityCalendar`, damit Zeitzone und Sommerzeit an einer Stelle behandelt werden.
/// Jahr, Monat und Tag beziehen sich immer auf den gregorianischen Kalender (ISO 8601).
public struct LocalDate: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parst `YYYY-MM-DD`. Liefert `nil` bei ungültigem Format oder unmöglichem Datum.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }

        self.init(year: year, month: month, day: day)
    }

    /// ISO-8601-Darstellung `YYYY-MM-DD`, wie sie das Backend für `date`-Spalten erwartet.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension LocalDate: CustomStringConvertible {
    public var description: String { isoString }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = LocalDate(isoString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Ungültiges Datum: \(string)"
            )
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
