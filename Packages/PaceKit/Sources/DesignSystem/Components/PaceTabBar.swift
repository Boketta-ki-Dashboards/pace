import PaceCore
import SwiftUI

/// Eintrag der Tab-Leiste.
public struct PaceTabItem<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public let systemImage: String
    public let selectedSystemImage: String
    /// Zähler am Symbol (z. B. ungelesene Nachrichten); 0 blendet ihn aus.
    public let badge: Int

    public var id: Value { value }

    public init(value: Value, title: String, systemImage: String, selectedSystemImage: String, badge: Int = 0) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.selectedSystemImage = selectedSystemImage
        self.badge = badge
    }
}

/// Untere Navigation von Pace. Der aktive Tab zeigt Symbol und Beschriftung gemeinsam in einer abgerundeten
/// Mint-Fläche (Light: zartes Mint mit dunkelgrünem Inhalt, Dark: Mint mit dunklem Inhalt).
public struct PaceTabBar<Value: Hashable>: View {
    private let items: [PaceTabItem<Value>]
    @Binding private var selection: Value

    public init(items: [PaceTabItem<Value>], selection: Binding<Value>) {
        self.items = items
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: PaceSpacing.xxs) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: isSelected ? item.selectedSystemImage : item.systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 24)
                            .overlay(alignment: .topTrailing) {
                                if item.badge > 0 {
                                    TabBadge(count: item.badge)
                                        .offset(x: 12, y: -4)
                                }
                            }
                        Text(item.title)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(PaceColor.selectionFill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.badge > 0 ? TabBadge.accessibilityText(item.badge) : "")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.top, 6)
        .padding(.bottom, PaceSpacing.xxs)
        // Große Schriftgrade würden die vier Beschriftungen sprengen; der Inhalt der Screens skaliert weiter.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background {
            PaceColor.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(PaceColor.border).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Kleiner Zähler am Tab-Symbol.
private struct TabBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : count.paceFormatted)
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(PaceColor.actionFill, in: Capsule())
            .overlay(Capsule().strokeBorder(PaceColor.surface, lineWidth: 1.5))
            .fixedSize()
            .accessibilityHidden(true)
    }

    static func accessibilityText(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count) ungelesen", "\(count) ungelesen"),
            en: ("\(count) unread", "\(count) unread"),
            ru: ("\(count) непрочитанное", "\(count) непрочитанных", "\(count) непрочитанных")
        )
    }
}
