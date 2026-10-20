import Foundation
import OnboardingFeature
import PaceCore
import PaceTestSupport
import Testing

/// Hinweise im Onboarding folgen der App-Sprache.
@MainActor
struct OnboardingLanguageTests {
    private func makeViewModel() -> ProfileSetupViewModel {
        ProfileSetupViewModel(userID: Fixtures.userID, profiles: ProfileRepositoryStub(), availabilityDebounce: .zero) { _ in }
    }

    @Test func usernameHintsInEnglish() {
        let viewModel = makeViewModel()
        viewModel.username = "ab"
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(viewModel.usernameMessage == "At least 3 characters.")
            #expect(viewModel.usernameRulesHint.hasPrefix("3–20 characters"))
        }
    }

    @Test func usernameHintsInRussian() {
        let viewModel = makeViewModel()
        viewModel.username = "ab"
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(viewModel.usernameMessage == "Не менее 3 символов.")
            #expect(viewModel.usernameRulesHint.hasPrefix("3–20 символов"))
        }
        viewModel.username = "niklas_1"
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(viewModel.usernameMessage == nil)
        }
    }
}
