import SwiftUI

/// Vollflächiger Zustand mit Symbol, Titel, Erklärung und optionalen Aktionen –
/// z. B. für Fehler, fehlende Berechtigungen oder leere Zustände.
public struct PaceStatusView<Actions: View>: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let tint: Color
    private let actions: Actions

    public init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = PaceColor.accent,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: PaceSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 96, height: 96)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: PaceSpacing.xs) {
                Text(title)
                    .font(PaceFont.title)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(message)
                    .font(PaceFont.body)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: PaceSpacing.xs) {
                actions
            }
        }
        .padding(PaceSpacing.l)
        .frame(maxWidth: .infinity)
    }
}

public extension PaceStatusView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String, tint: Color = PaceColor.accent) {
        self.init(systemImage: systemImage, title: title, message: message, tint: tint) {
            EmptyView()
        }
    }
}

#Preview {
    PaceStatusView(
        systemImage: "exclamationmark.triangle.fill",
        title: "Etwas ist schiefgelaufen",
        message: "Bitte versuche es erneut.",
        tint: PaceColor.warning
    ) {
        Button("Erneut versuchen") {}.buttonStyle(.pacePrimary)
    }
}
