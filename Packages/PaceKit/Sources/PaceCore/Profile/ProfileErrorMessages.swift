import Foundation

extension ProfileError {
    /// Text für die Anzeige, wenn eine Profiländerung fehlschlägt.
    public var message: String {
        switch self {
        case .usernameTaken:
            PaceLocalization.text(
                de: "Dieser Benutzername ist schon vergeben.",
                en: "This username is already taken.",
                ru: "Это имя пользователя уже занято."
            )
        case .invalidUsername:
            PaceLocalization.text(
                de: "Dieser Benutzername ist nicht erlaubt. Bitte wähle einen anderen.",
                en: "This username is not allowed. Please choose a different one.",
                ru: "Это имя пользователя недопустимо. Пожалуйста, выбери другое."
            )
        case .invalidDisplayName:
            PaceLocalization.text(
                de: "Dieser Anzeigename ist nicht erlaubt. Bitte wähle einen anderen.",
                en: "This display name is not allowed. Please choose a different one.",
                ru: "Это отображаемое имя недопустимо. Пожалуйста, выбери другое."
            )
        case .invalidRegion:
            PaceLocalization.text(
                de: "Diese Gemeinde kann nicht gewählt werden. Bitte suche erneut.",
                en: "This municipality can't be selected. Please search again.",
                ru: "Этот муниципалитет нельзя выбрать. Пожалуйста, попробуй найти снова."
            )
        case .notAuthenticated:
            PaceLocalization.text(
                de: "Du bist nicht angemeldet. Starte Pace neu.",
                en: "You are not signed in. Restart Pace.",
                ru: "Ты не вошёл в систему. Перезапусти Pace."
            )
        case .network:
            PaceLocalization.text(
                de: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut.",
                en: "No connection. Check your internet connection and try again.",
                ru: "Нет соединения. Проверь подключение к интернету и попробуй снова."
            )
        case .rateLimited:
            PaceLocalization.text(
                de: "Zu viele Versuche in kurzer Zeit. Bitte versuche es später erneut.",
                en: "Too many attempts in a short time. Please try again later.",
                ru: "Слишком много попыток за короткое время. Попробуй позже."
            )
        case .unavailable:
            PaceLocalization.text(
                de: "Diese Funktion ist auf dem Server noch nicht eingerichtet.",
                en: "This feature is not set up on the server yet.",
                ru: "Эта функция ещё не настроена на сервере."
            )
        case .unexpected:
            PaceLocalization.text(
                de: "Etwas ist schiefgelaufen. Bitte versuche es erneut.",
                en: "Something went wrong. Please try again.",
                ru: "Что-то пошло не так. Попробуй снова."
            )
        }
    }
}
