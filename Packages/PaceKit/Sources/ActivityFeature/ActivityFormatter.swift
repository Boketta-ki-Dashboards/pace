import Foundation
import PaceCore

/// Formatiert Bewegungswerte für die Anzeige. Ohne SwiftUI, dadurch testbar.
public struct ActivityFormatter: Sendable {
    private let fixedLocale: Locale?
    public let calendar: ActivityCalendar

    /// - Parameter locale: Festes Format (z. B. in Tests); ohne Angabe gilt jeweils die aktuelle Sprache der App.
    public init(locale: Locale? = nil, calendar: ActivityCalendar = ActivityCalendar()) {
        fixedLocale = locale
        self.calendar = calendar
    }

    /// Format für Zahlen und Datumsangaben – folgt ohne festes Format der gewählten Sprache der App.
    public var locale: Locale {
        fixedLocale ?? PaceLocalization.shared.locale
    }

    /// `8.742`
    public func steps(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// `6,4 km`
    public func distance(meters: Double) -> String {
        let kilometers = (meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return "\(kilometers) \(units.kilometers)"
    }

    /// `382 kcal`
    public func energy(kilocalories: Double) -> String {
        "\(Int(kilocalories.rounded()).formatted(.number.locale(locale))) \(units.kilocalories)"
    }

    /// `12`
    public func flights(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// `34 Min.`
    public func exerciseMinutes(_ value: Int) -> String {
        "\(value.formatted(.number.locale(locale))) \(units.minutes)"
    }

    /// Kilometer ohne Einheit, z. B. `6,4`
    public func kilometers(meters: Double) -> String {
        (meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// Kilokalorien ohne Einheit, gerundet, z. B. `382`
    public func kilocalories(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    /// Anteil am Ziel als Prozent, abgerundet wie auf Home, z. B. `87 %` – 99,6 % erscheinen nicht als „100 %“,
    /// solange das Ziel nicht erreicht ist.
    public func percent(_ fraction: Double) -> String {
        "\(Self.wholePercent(fraction).formatted(.number.locale(locale))) %"
    }

    /// Ganze Prozent, abgerundet. Der kleine Zuschlag gleicht Rundungsfehler aus (5.700 / 10.000 · 100 ergibt
    /// 56,999…), damit dort 57 % stehen und nicht 56 %.
    public static func wholePercent(_ fraction: Double) -> Int {
        Int((fraction * 100 + 1e-9).rounded(.down))
    }

    /// Veränderung als Prozent mit Vorzeichen, z. B. `+12 %`, `−8 %`, `±0 %`
    public func signedPercent(_ change: Double) -> String {
        let value = Int((change * 100).rounded())
        let sign = value > 0 ? "+" : value < 0 ? "−" : "±"
        return "\(sign)\(abs(value).formatted(.number.locale(locale))) %"
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

    /// Wochentag, z. B. `Montag`
    public func weekdayLong(_ day: LocalDate) -> String {
        dateStyle.weekday(.wide).format(calendar.startOfDay(day))
    }

    /// z. B. `Mo., 12. Okt.`
    public func dayWithWeekdayShort(_ day: LocalDate) -> String {
        dateStyle.weekday(.abbreviated).day().month(.abbreviated).format(calendar.startOfDay(day))
    }

    /// z. B. `Oktober 2026`
    public func monthYear(_ day: LocalDate) -> String {
        dateStyle.month(.wide).year().format(calendar.startOfDay(day))
    }

    /// Zeitraum, z. B. `12.–18. Okt.` / `Oct 12–18` / `12–18 окт.` oder `28. Sept. – 4. Okt.`
    public func dayRange(_ first: LocalDate, _ last: LocalDate) -> String {
        if first.year == last.year, first.month == last.month {
            switch language {
            case .german: return "\(first.day).–\(dayShort(last))"
            case .english: return "\(dayShort(first))–\(last.day)"
            case .russian: return "\(first.day)–\(dayShort(last))"
            }
        }
        return "\(dayShort(first)) – \(dayShort(last))"
    }

    /// Uhrzeit, z. B. `17:42`
    public func time(_ date: Date) -> String {
        dateStyle.hour().minute().format(date)
    }

    /// Sprache des Formats (bestimmt Einheiten und die Schreibweise von Zeiträumen).
    private var language: AppLanguage {
        AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "") ?? .german
    }

    private var units: (kilometers: String, kilocalories: String, minutes: String) {
        switch language {
        case .german: ("km", "kcal", "Min.")
        case .english: ("km", "kcal", "min")
        case .russian: ("км", "ккал", "мин")
        }
    }

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar.calendar, timeZone: calendar.timeZone)
    }
}
