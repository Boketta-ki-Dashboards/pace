import ActivityFeature
import Foundation
import PaceCore

/// Unterseiten des Profil-Tabs.
public enum ProfileRoute: Hashable, Sendable {
    /// Konto & Profil: Namen, Profilbild, Teilen, Kontoinformationen, Anmeldung.
    case account
    /// Darstellung (Automatisch/Hell/Dunkel) und App-Icon.
    case appearance
    case language
    case privacy
    case notifications
    /// Social-Einstellungen (blockierte Nutzer, Chats, Anfragen) – auch aus dem Social-Tab erreichbar.
    case social
    /// Datenschutz & Daten: Erklärungen, Datenexport, Konto löschen.
    case dataPrivacy
    /// Zweite Stufe beim Löschen des Kontos.
    case deleteAccount
    case help
    case feedback(FeedbackKind)
    /// Rechtliche Texte (Datenschutzerklärung, Impressum, Nutzungsbedingungen).
    case legal
    case legalDocument(LegalDocument)
    case statistics(StatisticsRoute)

    /// Titel der Seite (auch Zurück-Ziel der folgenden Seite).
    public var title: String {
        switch self {
        case .account: PaceLocalization.text(de: "Konto & Profil", en: "Account & profile", ru: "Аккаунт и профиль")
        case .appearance: PaceLocalization.text(de: "Darstellung", en: "Appearance", ru: "Оформление")
        case .language: PaceLocalization.text(de: "Sprache", en: "Language", ru: "Язык")
        case .privacy: PaceLocalization.text(de: "Privatsphäre", en: "Privacy", ru: "Конфиденциальность")
        case .notifications: PaceLocalization.text(de: "Mitteilungen", en: "Notifications", ru: "Уведомления")
        case .social: PaceLocalization.text(de: "Social-Einstellungen", en: "Social settings", ru: "Настройки общения")
        case .dataPrivacy: PaceLocalization.text(de: "Datenschutz & Daten", en: "Data & privacy", ru: "Данные и защита")
        case .deleteAccount: PaceLocalization.text(de: "Konto löschen", en: "Delete account", ru: "Удалить аккаунт")
        case .help: PaceLocalization.text(de: "Hilfe & Feedback", en: "Help & feedback", ru: "Помощь и отзывы")
        case .feedback(let kind): kind.title
        case .legal: PaceLocalization.text(de: "Rechtliches", en: "Legal", ru: "Правовая информация")
        case .legalDocument(let document): document.title
        case .statistics: PaceLocalization.text(de: "Statistik", en: "Statistics", ru: "Статистика")
        }
    }
}

/// Rechtliche Texte. Sie sind Entwürfe bzw. Platzhalter und müssen vom Betreiber geprüft und ergänzt werden.
public enum LegalDocument: String, CaseIterable, Hashable, Sendable, Identifiable {
    case privacyPolicy
    case imprint
    case terms

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .privacyPolicy: PaceLocalization.text(de: "Datenschutzerklärung", en: "Privacy policy", ru: "Политика конфиденциальности")
        case .imprint: PaceLocalization.text(de: "Impressum", en: "Legal notice", ru: "Выходные данные")
        case .terms: PaceLocalization.text(de: "Nutzungsbedingungen", en: "Terms of use", ru: "Условия использования")
        }
    }
}

/// Gemeinsame Texte des Profil-Bereichs.
enum ProfileTexts {
    static var profileTitle: String {
        PaceLocalization.text(de: "Profil", en: "Profile", ru: "Профиль")
    }

    static var retry: String {
        PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Попробовать снова")
    }

    static var cancel: String {
        PaceLocalization.text(de: "Abbrechen", en: "Cancel", ru: "Отмена")
    }

    static var save: String {
        PaceLocalization.text(de: "Sichern", en: "Save", ru: "Сохранить")
    }

    static var notAvailableTitle: String {
        PaceLocalization.text(de: "Noch nicht verfügbar", en: "Not available yet", ru: "Пока недоступно")
    }

    static var placeholder: String { "–" }

    static var shareProfile: String {
        PaceLocalization.text(de: "Profil teilen", en: "Share profile", ru: "Поделиться профилем")
    }

    static var rankingVisibilityTitle: String {
        PaceLocalization.text(de: "Sichtbarkeit in Rankings", en: "Visibility in rankings", ru: "Видимость в рейтингах")
    }

    static var off: String {
        PaceLocalization.text(de: "Aus", en: "Off", ru: "Выкл.")
    }

    static var openSocialTab: String {
        PaceLocalization.text(de: "Im Social-Tab öffnen", en: "Open in Social tab", ru: "Открыть во вкладке «Друзья»")
    }

    /// „Pace 0.1.0 (1)“.
    static func versionText(_ version: String) -> String {
        PaceLocalization.text(de: "Pace \(version)", en: "Pace \(version)", ru: "Pace \(version)")
    }

    /// „3 Zeichen“ / „3 characters“ / „3 символа“.
    static func characters(_ count: Int) -> String {
        "\(count.paceFormatted) " + PaceLocalization.plural(
            count,
            de: ("Zeichen", "Zeichen"),
            en: ("character", "characters"),
            ru: ("символ", "символа", "символов")
        )
    }

    /// „Entwurf – vom Betreiber zu prüfen“ für Rechts- und Datenschutztexte.
    static var draftNotice: String {
        PaceLocalization.text(
            de: "Entwurf – vom Betreiber zu prüfen",
            en: "Draft – to be reviewed by the operator",
            ru: "Черновик – требует проверки оператором"
        )
    }
}
