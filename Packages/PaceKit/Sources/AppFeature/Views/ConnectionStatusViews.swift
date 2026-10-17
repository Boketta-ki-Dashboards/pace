import DesignSystem
import SwiftUI

/// Verbindung zu Pace fehlgeschlagen – mit Möglichkeit, es erneut zu versuchen.
struct ConnectionFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        PaceStatusView(
            systemImage: "wifi.exclamationmark",
            title: "Keine Verbindung",
            message: message,
            tint: PaceColor.warning
        ) {
            Button("Erneut versuchen", action: onRetry)
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
            title: "Backend nicht konfiguriert",
            message: message,
            tint: PaceColor.textSecondary
        )
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
