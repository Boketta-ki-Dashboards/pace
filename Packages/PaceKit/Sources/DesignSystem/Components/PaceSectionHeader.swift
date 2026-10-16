import SwiftUI

/// Überschrift eines Abschnitts in Versalien, optional mit Zusatz rechts.
public struct PaceSectionHeader: View {
    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(PaceFont.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(PaceColor.textSecondary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    PaceSectionHeader("Letzte 7 Tage", detail: "Fr, 16. Okt.")
        .padding()
}
