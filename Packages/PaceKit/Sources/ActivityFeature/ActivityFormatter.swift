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

    /// Prozent in Ringen und Kurzangaben wie in den Pace-Referenzen: `84%` (Deutsch, Englisch), `84 %` (Russisch).
    public func compactPercent(_ fraction: Double) -> String {
        let value = Self.wholePercent(fraction).formatted(.number.locale(locale))
        return language == .russian ? "\(value)\u{00A0}%" : "\(value)%"
    }

    /// Puls in Schlägen pro Minute, getrennt in Zahl und Einheit: `62` + `/min` (Deutsch), `bpm` (Englisch),
    /// `уд/мин` (Russisch).
    public func beatsPerMinute(_ value: Double) -> (value: String, unit: String) {
        let number = Int(value.rounded()).formatted(.number.locale(locale))
        switch language {
        case .german: return (number, "/min")
        case .english: return (number, "bpm")
        case .russian: return (number, "уд/мин")
        }
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

    /// Kurzer Wochentag, z. B. `Mo`, `Mon`, `Пн`.
    public func weekdayShort(_ day: LocalDate) -> String {
        Self.capitalizedFirst(
            dateStyle.weekday(.abbreviated).format(calendar.startOfDay(day))
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        )
    }

    /// Ein Buchstabe für den Wochentag, z. B. `M`, `D`, `M`, `D`, `F`, `S`, `S` bzw. `П`, `В`, `С` …
    public func weekdayLetter(_ day: LocalDate) -> String {
        Self.capitalizedFirst(dateStyle.weekday(.narrow).format(calendar.startOfDay(day)))
    }

    /// z. B. `Freitag, 16. Oktober`, `Friday, October 16`, `Пятница, 16 октября`
    public func dayLong(_ day: LocalDate) -> String {
        Self.capitalizedFirst(dateStyle.weekday(.wide).day().month(.wide).format(calendar.startOfDay(day)))
    }

    /// z. B. `Samstag, 17. Oktober 2026`, `Saturday, October 17, 2026`, `Суббота, 17 октября 2026 г.`
    public func dayLongWithYear(_ day: LocalDate) -> String {
        Self.capitalizedFirst(dateStyle.weekday(.wide).day().month(.wide).year().format(calendar.startOfDay(day)))
    }

    /// Erster Wochentag im Kalender der App-Sprache (1 = Sonntag, 2 = Montag): Englisch beginnt mit Sonntag,
    /// Deutsch und Russisch mit Montag.
    public var firstWeekday: Int {
        language == .english ? 1 : 2
    }

    /// z. B. `16. Okt.`
    public func dayShort(_ day: LocalDate) -> String {
        dateStyle.day().month(.abbreviated).format(calendar.startOfDay(day))
    }

    /// Wochentag, z. B. `Montag`
    public func weekdayLong(_ day: LocalDate) -> String {
        Self.capitalizedFirst(dateStyle.weekday(.wide).format(calendar.startOfDay(day)))
    }

    /// z. B. `Mo., 12. Okt.`
    public func dayWithWeekdayShort(_ day: LocalDate) -> String {
        dateStyle.weekday(.abbreviated).day().month(.abbreviated).format(calendar.startOfDay(day))
    }

    /// z. B. `Oktober 2026`, `October 2026`, `Октябрь 2026` (Monatsname im Nominativ).
    public func monthYear(_ day: LocalDate) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar.calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return Self.capitalizedFirst(formatter.string(from: calendar.startOfDay(day)))
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

    /// Sprache des Formats (bestimmt Einheiten, Wochenbeginn und die Schreibweise von Zeiträumen).
    public var language: AppLanguage {
        AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "") ?? .german
    }

    /// Großer Anfangsbuchstabe für Datumsangaben am Zeilenanfang (Russisch schreibt Wochentage und Monate klein).
    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
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
