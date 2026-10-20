import DesignSystem
import PaceCore
import SwiftUI

/// Container für die Onboarding-Schritte.
public struct OnboardingView: View {
    private let viewModel: OnboardingViewModel

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.step {
            case .profile(let profileSetup):
                ProfileSetupView(viewModel: profileSetup)
                    .transition(.opacity)
            case .region(let regionOnboarding):
                RegionOnboardingView(viewModel: regionOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.step.number)
        .paceScreenBackground()
    }
}

/// Kopf eines Onboarding-Schritts: Fortschritt, Titel und Erklärung.
struct OnboardingStepHeader: View {
    let step: Int
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            PaceWordmark(height: 30)
                .padding(.bottom, PaceSpacing.s)
            Text(PaceLocalization.text(
                de: "Schritt \(step) von \(OnboardingViewModel.stepCount)",
                en: "Step \(step) of \(OnboardingViewModel.stepCount)",
                ru: "Шаг \(step) из \(OnboardingViewModel.stepCount)"
            ))
                .font(PaceFont.caption.weight(.semibold))
                .foregroundStyle(PaceColor.accent)
            Text(title)
                .font(PaceFont.largeTitle)
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(PaceFont.body)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
