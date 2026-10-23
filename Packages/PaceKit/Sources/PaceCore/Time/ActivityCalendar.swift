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

    /// Zeitpunkt `hour:minute` an `day` in der Zeitzone des Kalenders; `nil`, wenn es die Uhrzeit nicht gibt (z. B. in
    /// der übersprungenen Stunde der Sommerzeitumstellung).
    public func date(_ day: LocalDate, hour: Int, minute: Int) -> Date? {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components),
              calendar.component(.hour, from: date) == hour
        else { return nil }
        return date
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

    /// Sonntag der ISO-Woche, in der `day` liegt.
    public func endOfWeek(containing day: LocalDate) -> LocalDate {
        adding(6, to: startOfWeek(containing: day))
    }

    /// Erster Tag des Monats, in dem `day` liegt.
    public func startOfMonth(containing day: LocalDate) -> LocalDate {
        LocalDate(year: day.year, month: day.month, day: 1)
    }

    /// Letzter Tag des Monats, in dem `day` liegt.
    public func endOfMonth(containing day: LocalDate) -> LocalDate {
        adding(-1, to: addingMonths(1, to: startOfMonth(containing: day)))
    }

    /// Verschiebt um ganze Monate; der Tag wird auf die Monatslänge begrenzt (31. Jan. + 1 Monat = 28./29. Feb.).
    public func addingMonths(_ months: Int, to day: LocalDate) -> LocalDate {
        let total = day.year * 12 + (day.month - 1) + months
        let year = total / 12
        let month = total % 12 + 1
        let length = calendar.range(of: .day, in: .month, for: startOfDay(LocalDate(year: year, month: month, day: 1)))!.count
        return LocalDate(year: year, month: month, day: min(day.day, length))
    }
}
