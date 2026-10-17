import DesignSystem
import SwiftUI

/// Erklärt, wofür Pace Health-Zugriff braucht, und startet die System-Abfrage.
public struct HealthPermissionView: View {
    private let viewModel: HealthPermissionViewModel

    public init(viewModel: HealthPermissionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.xl) {
                    header
                    VStack(alignment: .leading, spacing: PaceSpacing.l) {
                        HealthPermissionPoint(
                            systemImage: "figure.walk",
                            title: "Nur Bewegungsdaten",
                            text: "Schritte, Distanz, aktive Kalorien, Stockwerke und Trainingsminuten. Keine Herzfrequenz, kein Schlaf, keine medizinischen Daten."
                        )
                        HealthPermissionPoint(
                            systemImage: "trophy.fill",
                            title: "Nur Schritte zählen für Rankings",
                            text: "Geteilt wird ausschließlich deine tägliche Schrittzahl. Alle anderen Werte bleiben auf deinem iPhone."
                        )
                        HealthPermissionPoint(
                            systemImage: "lock.fill",
                            title: "Nur lesen",
                            text: "Pace schreibt keine Daten in Apple Health."
                        )
                        HealthPermissionPoint(
                            systemImage: "location.slash",
                            title: "Kein Standort nötig",
                            text: "Für Schritte und Rankings brauchst du keine Standortfreigabe."
                        )
                        HealthPermissionPoint(
                            systemImage: "hand.raised.fill",
                            title: "Du behältst die Kontrolle",
                            text: "Du kannst den Zugriff jederzeit in der Health-App ändern."
                        )
                    }
                }
                .padding(PaceSpacing.l)
                .padding(.top, PaceSpacing.xl)
            }

            footer
        }
        .paceScreenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.m) {
            PaceWordmark(height: 34)
                .padding(.bottom, PaceSpacing.xs)

            Image(systemName: "figure.walk")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(PaceColor.onAccent)
                .frame(width: 72, height: 72)
                .background(PaceColor.accentStrong, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
                .accessibilityHidden(true)

            Text("Deine Schritte zählen")
                .font(PaceFont.largeTitle)
                .foregroundStyle(PaceColor.textPrimary)

            Text("Verbinde Pace mit Apple Health, damit wir deine Bewegung von heute anzeigen können.")
                .font(PaceFont.body)
                .foregroundStyle(PaceColor.textSecondary)
        }
    }

    private var footer: some View {
        VStack(spacing: PaceSpacing.s) {
            if case .failed(let message) = viewModel.state {
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.danger)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.requestAccess() }
            } label: {
                if viewModel.isRequesting {
                    ProgressView()
                        .tint(PaceColor.onAccent)
                } else {
                    Text("Mit Apple Health verbinden")
                }
            }
            .buttonStyle(.pacePrimary)
            .disabled(viewModel.isRequesting)
        }
        .padding(PaceSpacing.l)
    }
}

private struct HealthPermissionPoint: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(text)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
