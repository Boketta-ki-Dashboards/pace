import SwiftUI

/// Karte im Pace-Stil: helle Fläche, feiner Rand, sehr weicher Schatten (nur im Light Mode sichtbar).
public struct PaceCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = PaceSpacing.m, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground()
    }
}

/// Kachel innerhalb einer Karte, z. B. eine Ranking-Zeile oder die Distanz-/Kalorien-Leiste.
public struct PaceTile<Content: View>: View {
    private let isHighlighted: Bool
    private let content: Content

    public init(isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, PaceSpacing.s)
            .padding(.vertical, PaceSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted ? PaceColor.accentSoft : PaceColor.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isHighlighted ? PaceColor.accent.opacity(0.35) : PaceColor.border, lineWidth: 1)
            )
    }
}

public extension View {
    /// Hintergrund, Rand und Schatten einer Pace-Karte.
    func paceCardBackground(cornerRadius: CGFloat = PaceRadius.card) -> some View {
        modifier(PaceCardBackground(cornerRadius: cornerRadius))
    }
}

private struct PaceCardBackground: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(PaceColor.surface, in: shape)
            .overlay(shape.strokeBorder(PaceColor.border, lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 10, y: 3)
    }
}

#Preview {
    VStack(spacing: PaceSpacing.m) {
        PaceCard {
            Text("Karte")
        }
        PaceTile(isHighlighted: true) {
            Text("Hervorgehobene Kachel")
        }
    }
    .padding()
    .paceScreenBackground()
}
