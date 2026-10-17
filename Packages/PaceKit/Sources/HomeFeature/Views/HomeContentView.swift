import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Reine Darstellung des Home-Zustands – ohne Logik, dadurch einfach in Previews prüfbar.
struct HomeContentView<Details: View>: View {
    let state: HomeViewModel.State
    var manualStepsNote: String? = nil
    let formatter: ActivityFormatter
    let onRetry: () -> Void
    @ViewBuilder let details: () -> Details

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                PaceLoadingView("Schritte werden geladen …")
                    .containerRelativeFrame(.vertical)

            case .loaded(let overview):
                VStack(alignment: .leading, spacing: PaceSpacing.m) {
                    HomeStepsHero(
                        today: overview.today,
                        manualStepsNote: manualStepsNote,
                        formatter: formatter,
                        details: details
                    )
                    Text("Aktualisiert um \(formatter.time(overview.updatedAt))")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
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

private let previewFormatter = ActivityFormatter(locale: Locale(identifier: "de_DE"))

private func previewOverview(health: Int, competition: Int) -> ActivityOverview {
    let calendar = ActivityCalendar()
    let today = calendar.day(containing: .now)
    let days = (0..<7).map { offset in
        DailyActivitySummary(
            date: calendar.adding(offset - 6, to: today),
            healthSteps: offset == 6 ? health : 6_000 + offset * 500,
            competitionSteps: offset == 6 ? competition : 6_000 + offset * 500,
            walkingRunningDistanceMeters: 6_400,
            activeEnergyKilocalories: 382,
            flightsClimbed: 9,
            exerciseMinutes: 34
        )
    }
    return ActivityOverview(
        today: days[6],
        yesterday: days[5],
        currentWeek: ActivityPeriodSummary(period: .currentWeek, days: days),
        lastSevenDays: ActivityPeriodSummary(period: .lastSevenDays, days: days),
        updatedAt: .now
    )
}

#Preview("Geladen") {
    NavigationStack {
        HomeContentView(
            state: .loaded(previewOverview(health: 9_120, competition: 8_742)),
            manualStepsNote: ActivityStatsViewModel.manualStepsNote,
            formatter: previewFormatter,
            onRetry: {}
        ) {
            Text("Details")
        }
    }
}

#Preview("Laden") {
    HomeContentView(state: .loading, formatter: previewFormatter, onRetry: {}) { EmptyView() }
}

#Preview("Kein Zugriff") {
    HomeContentView(state: .noReadAccess, formatter: previewFormatter, onRetry: {}) { EmptyView() }
}

#Preview("Fehler") {
    HomeContentView(
        state: .failed(message: "Deine Schritte konnten nicht geladen werden. Bitte versuche es erneut."),
        formatter: previewFormatter,
        onRetry: {}
    ) {
        EmptyView()
    }
}
