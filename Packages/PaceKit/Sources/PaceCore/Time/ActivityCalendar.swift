import Foundation

/// Einzige Stelle für Tages- und Wochengrenzen.
///
/// - Gregorianischer Kalender in der Zeitzone des Nutzers (unabhängig vom eingestellten Kalendersystem).
/// - Wochen nach ISO 8601: Montag bis Sonntag – dieselbe Definition wie später bei Weekly-Rankings im Backend.
/// - Tagesintervalle sind halboffen `[Beginn, Beginn des Folgetags)` und dadurch bei Sommerzeit 23 bzw. 25 Stunden lang.
public struct ActivityCalendar: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Montag
        calendar.minimumDaysInFirstWeek = 4 // ISO 8601
        self.calendar = calendar
    }

    public var timeZone: TimeZone { calendar.timeZone }

    /// Der Kalendertag, in dem `date` liegt.
    public func day(containing date: Date) -> LocalDate {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: components.year!, month: components.month!, day: components.day!)
    }

    /// Beginn des Tags (lokale Mitternacht bzw. erster gültiger Zeitpunkt des Tags).
    public func startOfDay(_ day: LocalDate) -> Date {
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        // `date(from:)` liefert für existierende Kalendertage immer ein Datum.
        return calendar.startOfDay(for: calendar.date(from: components)!)
    }

    /// Halboffenes Intervall des Tags.
    public func interval(for day: LocalDate) -> DateInterval {
        DateInterval(start: startOfDay(day), end: startOfDay(adding(1, to: day)))
    }

    /// Halboffenes Intervall vom Beginn von `first` bis zum Ende von `last`.
    public func interval(from first: LocalDate, through last: LocalDate) -> DateInterval {
        precondition(first <= last, "first muss vor oder gleich last sein")
        return DateInterval(start: startOfDay(first), end: startOfDay(adding(1, to: last)))
    }

    public func adding(_ days: Int, to day: LocalDate) -> LocalDate {
        // Mittags rechnen, damit Sommerzeitwechsel um Mitternacht keinen Tag verschluckt.
        let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay(day))!
        return self.day(containing: calendar.date(byAdding: .day, value: days, to: noon)!)
    }

    /// Alle Tage von `first` bis einschließlich `last`, chronologisch.
    public func days(from first: LocalDate, through last: LocalDate) -> [LocalDate] {
        guard first <= last else { return [] }
        var result: [LocalDate] = []
        var current = first
        while current <= last {
            result.append(current)
            current = adding(1, to: current)
        }
        return result
    }

    /// Montag der ISO-Woche, in der `day` liegt.
    public func startOfWeek(containing day: LocalDate) -> LocalDate {
        let weekday = calendar.component(.weekday, from: startOfDay(day)) // 1 = Sonntag … 7 = Samstag
        let daysSinceMonday = (weekday + 5) % 7
        return adding(-daysSinceMonday, to: day)
    }
}
