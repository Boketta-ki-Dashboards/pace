import DesignSystem
import PaceCore
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
                    title: PaceLocalization.text(
                        de: "Wo möchtest du antreten?",
                        en: "Where do you want to compete?",
                        ru: "Где ты хочешь соревноваться?"
                    ),
                    message: PaceLocalization.text(
                        de: "Wähle deine Gemeinde. Darüber kannst du in den Rankings deiner Gemeinde, deines Kreises, "
                            + "deines Bundeslandes und ganz Deutschlands antreten.",
                        en: "Choose your municipality. It lets you compete in the rankings of your municipality, your district, "
                            + "your state and all of Germany.",
                        ru: "Выбери свой населённый пункт. Так ты сможешь участвовать в рейтингах своего города, района, "
                            + "федеральной земли и всей Германии."
                    )
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
                        if viewModel.savingChoice == true {
                            ProgressView().tint(PaceColor.onAccent)
                        } else {
                            Text(PaceLocalization.text(de: "Regional antreten", en: "Compete regionally", ru: "Участвовать в регионе"))
                        }
                    }
                    .buttonStyle(.pacePrimary)
                    .disabled(!viewModel.canConfirm)

                    Text(PaceLocalization.text(
                        de: "Du erscheinst mit Anzeigename, Benutzername und deinen Wettbewerbsschritten in den Rankings deiner Regionen.",
                        en: "You appear with your display name, username and competition steps in the rankings of your regions.",
                        ru: "Ты появишься в рейтингах своих регионов с именем, именем пользователя и соревновательными шагами."
                    ))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)

                    Button {
                        Task { await viewModel.confirm(regionalLeaderboardEnabled: false) }
                    } label: {
                        if viewModel.savingChoice == false {
                            ProgressView().tint(PaceColor.accent)
                        } else {
                            Text(PaceLocalization.text(
                                de: "Ohne regionales Ranking weiter",
                                en: "Continue without regional ranking",
                                ru: "Продолжить без регионального рейтинга"
                            ))
                        }
                    }
                    .buttonStyle(.paceSecondary)
                    .disabled(!viewModel.canConfirm)

                    Text(PaceLocalization.text(
                        de: "Du erscheinst nicht in regionalen Rankings und siehst sie, sobald du deine Ranking-Sichtbarkeit aktivierst. "
                            + "Das kannst du jederzeit im Profil ändern.",
                        en: "You won't appear in regional rankings and will see them once you turn on your ranking visibility. "
                            + "You can change this in your profile at any time.",
                        ru: "Ты не будешь виден в региональных рейтингах и увидишь их, когда включишь видимость в рейтингах. "
                            + "Это можно изменить в профиле в любой момент."
                    ))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .padding(PaceSpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
