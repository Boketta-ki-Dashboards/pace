import SwiftUI

/// Die Pace-Wortmarke. Wird in der Markenfarbe eingefärbt (tiefes Grün, im Dark Mode Mint).
public struct PaceWordmark: View {
    private let height: CGFloat

    /// - Parameter height: Höhe der Wortmarke in Punkten (inklusive Unterlänge des „p“).
    public init(height: CGFloat = 28) {
        self.height = height
    }

    public var body: some View {
        Image("PaceWordmark", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(PaceColor.brand)
            .accessibilityLabel("Pace")
            .accessibilityAddTraits(.isImage)
    }
}

#Preview {
    VStack(spacing: PaceSpacing.l) {
        PaceWordmark()
        PaceWordmark(height: 56)
    }
    .padding()
}
