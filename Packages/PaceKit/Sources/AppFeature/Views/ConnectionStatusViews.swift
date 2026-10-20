import DesignSystem
import PaceCore
import SwiftUI

/// Verbindung zu Pace fehlgeschlagen – mit Möglichkeit, es erneut zu versuchen.
struct ConnectionFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        PaceStatusView(
            systemImage: "wifi.exclamationmark",
            title: PaceLocalization.text(de: "Keine Verbindung", en: "No connection", ru: "Нет соединения"),
            message: message,
            tint: PaceColor.warning
        ) {
            Button(PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Попробовать снова"), action: onRetry)
                .buttonStyle(.pacePrimary)
        }
        .frame(maxHeight: .infinity)
        .paceScreenBackground()
    }
}

/// Das Backend ist nicht konfiguriert. Tritt nur in Entwicklungs-Builds ohne `Config/Pace.xcconfig` auf.
struct BackendUnavailableView: View {
    let message: String

    var body: some View {
        PaceStatusView(
            systemImage: "gearshape.2.fill",
            title: PaceLocalization.text(
                de: "Backend nicht konfiguriert",
                en: "Backend not configured",
                ru: "Сервер не настроен"
            ),
            message: message,
            tint: PaceColor.textSecondary
        )
        .frame(maxHeight: .infinity)
        .paceScreenBackground()
    }
}

/// Nach dem Löschen des Kontos: Bestätigung und Neubeginn mit einem neuen Konto.
struct AccountDeletedView: View {
    let onStartOver: () -> Void

    var body: some View {
        PaceStatusView(
            systemImage: "checkmark.circle",
            title: PaceLocalization.text(
                de: "Dein Konto wurde gelöscht",
                en: "Your account has been deleted",
                ru: "Твой аккаунт удалён"
            ),
            message: PaceLocalization.text(
                de: "Dein Profil und deine Daten wurden vom Pace-Server und von diesem iPhone entfernt. Deine Daten in Apple Health bleiben unverändert. Du kannst Pace jederzeit mit einem neuen Konto nutzen.",
                en: "Your profile and data have been removed from the Pace server and from this iPhone. Your data in Apple Health stays unchanged. You can start using Pace again with a new account at any time.",
                ru: "Профиль и данные удалены с сервера Pace и с этого iPhone. Данные в Apple Health не изменились. Ты можешь в любой момент снова пользоваться Pace с новым аккаунтом."
            )
        ) {
            Button(PaceLocalization.text(de: "Neu beginnen", en: "Start over", ru: "Начать заново"), action: onStartOver)
                .buttonStyle(.pacePrimary)
        }
        .frame(maxHeight: .infinity)
        .paceScreenBackground()
    }
}

#Preview("Keine Verbindung") {
    ConnectionFailedView(message: "Keine Verbindung zu Pace. Prüfe deine Internetverbindung und versuche es erneut.") {}
}

#Preview("Nicht konfiguriert") {
    BackendUnavailableView(message: "Trage SUPABASE_URL und SUPABASE_PUBLISHABLE_KEY in Config/Pace.xcconfig ein.")
}

#Preview("Konto gelöscht") {
    AccountDeletedView {}
}
