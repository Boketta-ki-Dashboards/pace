import Foundation

/// Liest `timestamptz`-Werte, wie PostgREST sie liefert, z. B. `2026-10-16T12:34:56.123456+00:00`.
///
/// Eigener Parser statt `ISO8601DateFormatter`, weil Postgres bis zu sechs Nachkommastellen und Offsets mit oder
/// ohne Doppelpunkt sendet und sich die Formatter-Varianten je Plattform unterschiedlich verhalten.
/// Erlaubt: `T` oder Leerzeichen als Trenner, optionale Nachkommastellen, `Z` oder `±HH`, `±HH:MM`, `±HHMM`.
enum BackendTimestamp {
    static func date(from string: String) -> Date? {
        var scanner = DigitScanner(Array(string.utf8))
        guard let year = scanner.number(digits: 4), scanner.skip("-"),
              let month = scanner.number(digits: 2), scanner.skip("-"),
              let day = scanner.number(digits: 2), scanner.skip(anyOf: "Tt "),
              let hour = scanner.number(digits: 2), scanner.skip(":"),
              let minute = scanner.number(digits: 2), scanner.skip(":"),
              let second = scanner.number(digits: 2)
        else { return nil }

        var fraction = 0.0
        if scanner.skip(".") {
            guard let value = scanner.fraction() else { return nil }
            fraction = value
        }

        guard let offset = scanner.utcOffset(), scanner.isAtEnd,
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }

        let components = DateComponents(
            calendar: utcCalendar, timeZone: utcCalendar.timeZone,
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        guard components.isValidDate(in: utcCalendar), let date = utcCalendar.date(from: components) else {
            return nil
        }
        return date.addingTimeInterval(fraction - TimeInterval(offset))
    }

    /// `timestamptz`-Literal in UTC mit Mikrosekunden, z. B. `2026-10-16T12:34:56.123456Z` – dieselbe Genauigkeit wie
    /// in Postgres, damit z. B. „Nachrichten vor diesem Zeitpunkt“ genau an einer Nachricht trennt.
    static func string(from date: Date) -> String {
        let totalMicroseconds = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
        var seconds = totalMicroseconds / 1_000_000
        var microseconds = totalMicroseconds % 1_000_000
        if microseconds < 0 {
            microseconds += 1_000_000
            seconds -= 1
        }
        let components = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(seconds))
        )
        func padded(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(padded(components.year, 4))-\(padded(components.month, 2))-\(padded(components.day, 2))"
            + "T\(padded(components.hour, 2)):\(padded(components.minute, 2)):\(padded(components.second, 2))"
            + ".\(padded(Int(microseconds), 6))Z"
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

/// Liest ASCII-Ziffern und Trennzeichen aus einem Byte-Array.
private struct DigitScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { index == bytes.count }

    mutating func number(digits count: Int) -> Int? {
        guard index + count <= bytes.count else { return nil }
        var value = 0
        for byte in bytes[index..<index + count] {
            guard let digit = Self.digit(byte) else { return nil }
            value = value * 10 + digit
        }
        index += count
        return value
    }

    /// Nachkommastellen nach dem Punkt, als Bruchteil einer Sekunde.
    mutating func fraction() -> Double? {
        var value = 0.0
        var scale = 0.1
        let start = index
        while index < bytes.count, let digit = Self.digit(bytes[index]) {
            value += Double(digit) * scale
            scale /= 10
            index += 1
        }
        return index > start ? value : nil
    }

    /// Offset zu UTC in Sekunden. `nil`, wenn keine gültige Zeitzone folgt.
    mutating func utcOffset() -> Int? {
        if skip(anyOf: "Zz") { return 0 }
        let sign: Int
        if skip("+") {
            sign = 1
        } else if skip("-") {
            sign = -1
        } else {
            return nil
        }
        guard let hours = number(digits: 2), hours <= 23 else { return nil }
        var minutes = 0
        if !isAtEnd {
            _ = skip(":")
            guard let value = number(digits: 2), value <= 59 else { return nil }
            minutes = value
        }
        return sign * (hours * 3600 + minutes * 60)
    }

    mutating func skip(_ character: Character) -> Bool {
        skip(anyOf: String(character))
    }

    mutating func skip(anyOf characters: String) -> Bool {
        guard index < bytes.count, characters.utf8.contains(bytes[index]) else { return false }
        index += 1
        return true
    }

    private static func digit(_ byte: UInt8) -> Int? {
        (48...57).contains(byte) ? Int(byte - 48) : nil
    }
}

extension KeyedDecodingContainer {
    /// Dekodiert einen `timestamptz`-String mit `BackendTimestamp`.
    func decodeTimestamp(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        guard let date = BackendTimestamp.date(from: string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Ungültiger Zeitstempel: \(string)"
            )
        }
        return date
    }

    /// Wie `decodeTimestamp(forKey:)`, aber `nil`, wenn der Wert fehlt oder `null` ist.
    func decodeTimestampIfPresent(forKey key: Key) throws -> Date? {
        guard let string = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = BackendTimestamp.date(from: string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Ungültiger Zeitstempel: \(string)"
            )
        }
        return date
    }
}
