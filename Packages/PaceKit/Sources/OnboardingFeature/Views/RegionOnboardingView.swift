import DesignSystem
import RegionFeature
import SwiftUI

/// Gemeinde wählen und über die Teilnahme an regionalen Rankings entscheiden.
struct RegionOnboardingView: View {
    let viewModel: RegionOnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaceSpacing.l) {
                OnboardingStepHeader(
                    step: 2,
                    title: "Wo möchtest du antreten?",
                    message: "Wähle deine Gemeinde. Darüber nimmst du an den Rankings deiner Gemeinde, deines Kreises, "
                        + "deines Bundeslandes und ganz Deutschlands teil."
                )

                RegionSearchView(viewModel: viewModel.search)

                RegionPrivacyNotice()

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.danger)
                }

                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    Button {
                        Task { await viewModel.confirm(regionalLeaderboardEnabled: true) }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView().tint(PaceColor.onAccent)
                        } else {
                            Text("Regional antreten")
                        }
                    }
                    .buttonStyle(.pacePrimary)
                    .disabled(!viewModel.canConfirm)

                    Text("Du erscheinst mit Anzeigename, Benutzername und deinen Wettbewerbsschritten in den Rankings deiner Regionen.")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)

                    Button("Ohne regionales Ranking weiter") {
                        Task { await viewModel.confirm(regionalLeaderboardEnabled: false) }
                    }
                    .buttonStyle(.paceSecondary)
                    .disabled(!viewModel.canConfirm)

                    Text("Du siehst die Rankings, erscheinst selbst aber nicht darin. Das kannst du jederzeit im Profil ändern.")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .padding(PaceSpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
