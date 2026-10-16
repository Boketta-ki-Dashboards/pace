import DesignSystem
import PaceCore
import SwiftUI

/// Reine Darstellung des Home-Zustands – ohne Logik, dadurch einfach in Previews prüfbar.
struct HomeContentView: View {
    let state: HomeViewModel.State
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                PaceLoadingView("Schritte werden geladen …")
                    .containerRelativeFrame(.vertical)

            case .loaded(let count):
                VStack(spacing: PaceSpacing.m) {
                    TodayStepsCard(count: count)
                }
                .padding(PaceSpacing.m)

            case .noReadAccess:
                PaceStatusView(
                    systemImage: "hand.raised.fill",
                    title: "Keine Schrittdaten lesbar",
                    message: """
                    Pace hat keinen Zugriff auf deine Schritte. Öffne die Health-App, tippe auf dein Profilbild \
                    und aktiviere unter „Datenschutz“ → „Apps“ → „Pace“ den Zugriff auf „Schritte“.

                    Hast du den Zugriff bereits erlaubt? Dann prüfe unter Einstellungen → Datenschutz & Sicherheit \
                    → Bewegung & Fitness, ob „Fitness-Tracking“ aktiviert ist.
                    """,
                    tint: PaceColor.warning
                ) {
                    Button("Erneut prüfen", action: onRetry)
                        .buttonStyle(.pacePrimary)
                }
                .containerRelativeFrame(.vertical)

            case .failed(let message):
                PaceStatusView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Schritte nicht verfügbar",
                    message: message,
                    tint: PaceColor.danger
                ) {
                    Button("Erneut versuchen", action: onRetry)
                        .buttonStyle(.pacePrimary)
                }
                .containerRelativeFrame(.vertical)
            }
        }
        .paceScreenBackground()
    }
}

#Preview("Geladen") {
    NavigationStack {
        HomeContentView(
            state: .loaded(DailyStepCount(day: .now, steps: 8_432, updatedAt: .now)),
            onRetry: {}
        )
        .navigationTitle("Heute")
    }
}

#Preview("Laden") {
    HomeContentView(state: .loading, onRetry: {})
}

#Preview("Kein Zugriff") {
    HomeContentView(state: .noReadAccess, onRetry: {})
}

#Preview("Fehler") {
    HomeContentView(
        state: .failed(message: "Deine Schritte konnten nicht geladen werden. Bitte versuche es erneut."),
        onRetry: {}
    )
}
