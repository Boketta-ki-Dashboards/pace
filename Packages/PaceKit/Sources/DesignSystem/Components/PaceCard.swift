import SwiftUI

/// Abgesetzte Fläche zum Gruppieren von Inhalten.
public struct PaceCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(PaceSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PaceColor.surface,
                in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous)
            )
    }
}

#Preview {
    PaceCard {
        Text("Inhalt")
    }
    .padding()
    .background(PaceColor.background)
}
