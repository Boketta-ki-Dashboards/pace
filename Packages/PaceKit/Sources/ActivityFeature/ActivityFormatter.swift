import Foundation
import PaceCore

/// Formatiert Bewegungswerte für die Anzeige. Ohne SwiftUI, dadurch testbar.
public struct ActivityFormatter: Sendable {
    public let locale: Locale
    public let calendar: ActivityCalendar

    public init(locale: Locale = .autoupdatingCurrent, calendar: ActivityCalendar = ActivityCalendar()) {
        self.locale = locale
        self.calendar = calendar
    }

    /// `8.742`
    public func steps(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// `6,4 km`
    public func distance(meters: Double) -> String {
        let kilometers = (meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return "\(kilometers) km"
    }

    /// `382 kcal`
    public func energy(kilocalories: Double) -> String {
        "\(Int(kilocalories.rounded()).formatted(.number.locale(locale))) kcal"
    }

    /// `12`
    public func flights(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// `34 Min.`
    public func exerciseMinutes(_ value: Int) -> String {
        "\(value.formatted(.number.locale(locale))) Min."
    }

    /// Kurzer Wochentag, z. B. `Mo`.
    public func weekdayShort(_ day: LocalDate) -> String {
        dateStyle.weekday(.abbreviated).format(calendar.startOfDay(day))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// z. B. `Freitag, 16. Oktober`
    public func dayLong(_ day: LocalDate) -> String {
        dateStyle.weekday(.wide).day().month(.wide).format(calendar.startOfDay(day))
    }

    /// z. B. `16. Okt.`
    public func dayShort(_ day: LocalDate) -> String {
        dateStyle.day().month(.abbreviated).format(calendar.startOfDay(day))
    }

    /// Uhrzeit, z. B. `17:42`
    public func time(_ date: Date) -> String {
        dateStyle.hour().minute().format(date)
    }

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar.calendar, timeZone: calendar.timeZone)
    }
}
