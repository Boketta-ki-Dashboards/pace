import SwiftUI

/// Kopfzeile einer Karte: Titel links, optional eine Aktion („Alle ansehen“) oder ein Pfeil rechts.
public struct PaceCardHeader: View {
    private let title: String
    private let actionTitle: String?
    private let showsChevron: Bool

    /// - Parameters:
    ///   - actionTitle: Grüner Aktionstext rechts, z. B. „Alle ansehen“.
    ///   - showsChevron: Pfeil rechts ohne Text – für Karten, die als Ganzes antippbar sind.
    public init(_ title: String, actionTitle: String? = nil, showsChevron: Bool = false) {
        self.title = title
        self.actionTitle = actionTitle
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
            Text(title)
                .font(PaceFont.cardTitle)
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: PaceSpacing.xs)
            if let actionTitle {
                HStack(spacing: PaceSpacing.xxs) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.accent)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    VStack(spacing: PaceSpacing.l) {
        PaceCardHeader("Deine Freunde", actionTitle: "Alle ansehen")
        PaceCardHeader("Deine Woche", showsChevron: true)
    }
    .padding()
}
