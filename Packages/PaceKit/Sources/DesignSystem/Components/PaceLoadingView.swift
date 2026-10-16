import SwiftUI

/// Vollflächiger Ladezustand.
public struct PaceLoadingView: View {
    private let message: String?

    public init(_ message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: PaceSpacing.m) {
            ProgressView()
                .controlSize(.large)
            if let message {
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PaceLoadingView("Wird geladen …")
}
