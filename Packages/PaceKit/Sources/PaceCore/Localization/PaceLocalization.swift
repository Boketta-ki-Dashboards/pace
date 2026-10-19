import Foundation
import Observation

/// Sprachen der App-Oberfläche.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case german = "de"
    case english = "en"
    case russian = "ru"

    public var id: String { rawValue }

    /// Name der Sprache in ihrer eigenen Sprache („Deutsch“, „English“, „Русский“) – so findet man sie in der Auswahl
    /// auch dann, wenn man die aktuelle Sprache nicht versteht.
    public var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// Format für Zahlen, Datumsangaben und Wochentage: `8.432` (de), `8,432` (en), `8 432` (ru).
    public var locale: Locale {
        switch self {
        case .german: Locale(identifier: "de_DE")
        case .english: Locale(identifier: "en_US")
        case .russian: Locale(identifier: "ru_RU")
        }
    }

    /// Passende Sprache zu den bevorzugten Sprachen des Geräts; ohne Treffer Deutsch.
    public static func matching(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier ?? String(identifier.prefix(2))
            if let language = AppLanguage(rawValue: code) {
                return language
            }
        }
        return .german
    }
}

/// Gewählte Sprache: wie das iPhone oder fest eine der drei Sprachen.
public enum LanguagePreference: Codable, Sendable, Hashable {
    case system
    case fixed(AppLanguage)

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .system: AppLanguage.matching(preferredLanguages: preferredLanguages)
        case .fixed(let language): language
        }
    }
}

/// Aktuelle Sprache der Oberfläche. Wird beim Start und bei jeder Änderung in den Einstellungen gesetzt.
///
/// Texte lesen die Sprache über ``PaceLocalization/text(de:en:ru:)``. Die Sprache ist beobachtbar: SwiftUI-Views, die
/// beim Zeichnen Texte abrufen, werden bei einem Wechsel automatisch neu gezeichnet – ohne Neustart der App.
/// Lesen ist von jedem Thread aus möglich (z. B. in reinen Berechnungen ohne Main Actor).
public final class PaceLocalization: Observable, @unchecked Sendable {
    public static let shared = PaceLocalization()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var storedLanguage: AppLanguage

    init(language: AppLanguage = .german) {
        storedLanguage = language
    }

    public var language: AppLanguage {
        get {
            registrar.access(self, keyPath: \.language)
            return lock.withLock { storedLanguage }
        }
        set {
            guard newValue != lock.withLock({ storedLanguage }) else { return }
            registrar.withMutation(of: self, keyPath: \.language) {
                lock.withLock { storedLanguage = newValue }
            }
        }
    }

    /// Sprache nur für die laufende Aufgabe (z. B. Tests einer Übersetzung), ohne die App-Sprache zu ändern.
    /// `PaceLocalization.$languageOverride.withValue(.english) { … }`
    @TaskLocal public static var languageOverride: AppLanguage?

    /// Die für Texte und Formate geltende Sprache.
    public var effectiveLanguage: AppLanguage {
        Self.languageOverride ?? language
    }

    /// Format für Zahlen und Datumsangaben in der aktuellen Sprache.
    public var locale: Locale {
        effectiveLanguage.locale
    }

    // MARK: Texte

    /// Text in der aktuellen Sprache. Jede Stelle liefert alle drei Sprachen – fehlende Übersetzungen fallen so schon
    /// beim Kompilieren auf.
    public static func text(
        de: @autoclosure () -> String,
        en: @autoclosure () -> String,
        ru: @autoclosure () -> String
    ) -> String {
        switch shared.effectiveLanguage {
        case .german: de()
        case .english: en()
        case .russian: ru()
        }
    }

    /// Passende Pluralform: Deutsch und Englisch kennen „eins“ und „mehrere“, Russisch drei Formen
    /// (1 шаг, 2 шага, 5 шагов; 21 шаг, 22 шага, 11 шагов).
    public static func plural(
        _ count: Int,
        de: (one: String, other: String),
        en: (one: String, other: String),
        ru: (one: String, few: String, many: String)
    ) -> String {
        switch shared.effectiveLanguage {
        case .german: count == 1 ? de.one : de.other
        case .english: count == 1 ? en.one : en.other
        case .russian: russianForm(count, ru)
        }
    }

    /// „8.432 Schritte“ / „8,432 steps“ / „8 432 шага“ mit passender Pluralform.
    public static func steps(_ count: Int) -> String {
        "\(count.paceFormatted) " + plural(count, de: ("Schritt", "Schritte"), en: ("step", "steps"), ru: ("шаг", "шага", "шагов"))
    }

    /// „5 Tage“ / „5 days“ / „5 дней“.
    public static func days(_ count: Int) -> String {
        "\(count.paceFormatted) " + plural(count, de: ("Tag", "Tage"), en: ("day", "days"), ru: ("день", "дня", "дней"))
    }

    static func russianForm(_ count: Int, _ forms: (one: String, few: String, many: String)) -> String {
        let value = abs(count)
        let lastTwo = value % 100
        let last = value % 10
        if last == 1, lastTwo != 11 { return forms.one }
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return forms.few }
        return forms.many
    }
}

extension Int {
    /// Zahl im Format der aktuellen Sprache, z. B. `8.432`, `8,432` oder `8 432`.
    public var paceFormatted: String {
        formatted(.number.locale(PaceLocalization.shared.locale))
    }
}

extension Date.FormatStyle {
    /// Datumsformat in der aktuellen Sprache der App.
    public static func pace(_ style: Date.FormatStyle) -> Date.FormatStyle {
        style.locale(PaceLocalization.shared.locale)
    }
}
