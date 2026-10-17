import DesignSystem
import PaceCore
import SwiftUI

/// Anzeigename und Benutzername wählen.
struct ProfileSetupView: View {
    @Bindable var viewModel: ProfileSetupViewModel

    private enum Field: Hashable {
        case displayName
        case username
    }

    @FocusState private var focusedField: Field?

    init(viewModel: ProfileSetupViewModel) {
        _viewModel = Bindable(viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaceSpacing.l) {
                OnboardingStepHeader(
                    step: 1,
                    title: "Wie sollen dich andere sehen?",
                    message: "Anzeigename und Benutzername erscheinen in Rankings neben deinen Schritten – "
                        + "aber nur, wenn du regional antrittst."
                )

                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    fieldLabel("Anzeigename")
                    TextField("z. B. Niklas", text: $viewModel.displayName)
                        .textContentType(.nickname)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .displayName)
                        .onSubmit { focusedField = .username }
                        .modifier(InputFieldStyle())
                    if let message = viewModel.displayNameMessage {
                        validationText(message, tint: PaceColor.danger)
                    }
                }

                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    fieldLabel("Benutzername")
                    HStack(spacing: PaceSpacing.xxs) {
                        Text("@")
                            .foregroundStyle(PaceColor.textSecondary)
                            .accessibilityHidden(true)
                        TextField("benutzername", text: $viewModel.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .username)
                            .onSubmit { Task { await viewModel.submit() } }
                    }
                    .modifier(InputFieldStyle())
                    usernameStatus
                    Text("3–20 Zeichen: Buchstaben, Ziffern und _. Groß- und Kleinschreibung zählen nicht als Unterschied.")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    validationText(errorMessage, tint: PaceColor.danger)
                }

                Button {
                    focusedField = nil
                    Task { await viewModel.submit() }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().tint(PaceColor.onAccent)
                    } else {
                        Text("Weiter")
                    }
                }
                .buttonStyle(.pacePrimary)
                .disabled(!viewModel.canSubmit)
            }
            .padding(PaceSpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: viewModel.username) { [viewModel] in
            await viewModel.checkUsernameAvailability()
        }
    }

    @ViewBuilder
    private var usernameStatus: some View {
        if let message = viewModel.usernameMessage {
            switch viewModel.usernameStatus {
            case .available:
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.success)
            case .checking:
                HStack(spacing: PaceSpacing.xs) {
                    ProgressView().controlSize(.mini)
                    validationText(message, tint: PaceColor.textSecondary)
                }
            default:
                validationText(message, tint: PaceColor.danger)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(PaceFont.headline)
            .foregroundStyle(PaceColor.textPrimary)
    }

    private func validationText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(PaceFont.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Einheitliche Eingabefelder im Onboarding.
private struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(PaceFont.body)
            .padding(PaceSpacing.s)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous))
    }
}
