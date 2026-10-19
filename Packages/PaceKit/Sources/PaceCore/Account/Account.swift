import Foundation

/// Art einer Rückmeldung aus „Hilfe“.
public enum FeedbackKind: String, CaseIterable, Sendable, Identifiable {
    case problem
    case idea

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .problem: PaceLocalization.text(de: "Problem melden", en: "Report a problem", ru: "Сообщить о проблеме")
        case .idea: PaceLocalization.text(de: "Feedback senden", en: "Send feedback", ru: "Отправить отзыв")
        }
    }
}

public enum FeedbackRules {
    public static let maximumLength = 2_000
}

public enum AccountError: Error, Equatable, Sendable {
    case network
    case notAuthenticated
    case rateLimited
    case invalidInput
    /// Die Funktion ist auf dem Server (noch) nicht eingerichtet.
    case unavailable
    case unexpected(String)

    public var message: String {
        switch self {
        case .network:
            PaceLocalization.text(
                de: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut.",
                en: "No connection. Check your internet connection and try again.",
                ru: "Нет соединения. Проверь подключение к интернету и попробуй снова."
            )
        case .notAuthenticated:
            PaceLocalization.text(de: "Du bist nicht angemeldet. Starte Pace neu.", en: "You are not signed in. Restart Pace.", ru: "Ты не вошёл в систему. Перезапусти Pace.")
        case .rateLimited:
            PaceLocalization.text(
                de: "Zu viele Versuche in kurzer Zeit. Bitte versuche es später erneut.",
                en: "Too many attempts in a short time. Please try again later.",
                ru: "Слишком много попыток за короткое время. Попробуй позже."
            )
        case .invalidInput:
            PaceLocalization.text(de: "Die Eingabe ist ungültig.", en: "The input is invalid.", ru: "Неверный ввод.")
        case .unavailable:
            PaceLocalization.text(
                de: "Diese Funktion ist auf dem Server noch nicht eingerichtet.",
                en: "This feature is not set up on the server yet.",
                ru: "Эта функция ещё не настроена на сервере."
            )
        case .unexpected:
            PaceLocalization.text(de: "Etwas ist schiefgelaufen. Bitte versuche es erneut.", en: "Something went wrong. Please try again.", ru: "Что-то пошло не так. Попробуй снова.")
        }
    }
}

/// Datenschutz-Funktionen des Kontos (DSGVO): Auskunft, Löschung, Rückmeldungen.
public protocol AccountRepository: Sendable {
    /// Alle auf dem Server gespeicherten personenbezogenen Daten des eigenen Kontos als JSON.
    func exportData() async throws -> Data
    /// Eigene hochgeladene Dateien (Profilbild, Chat-Anhänge, Bilder eigener Gruppen), damit die App sie vor dem
    /// Löschen des Kontos über Storage entfernen kann.
    func ownMedia() async throws -> [MediaReference]
    /// Löscht das Konto endgültig: Profil, Tageswerte, Freundschaften, Mitgliedschaften, Nachrichten und Meldungen.
    func deleteAccount() async throws
    /// Speichert eine Rückmeldung für das Pace-Team.
    func submitFeedback(kind: FeedbackKind, message: String, appVersion: String) async throws
}
