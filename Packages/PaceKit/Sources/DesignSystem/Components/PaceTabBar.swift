import SwiftUI

/// Eintrag der Tab-Leiste.
public struct PaceTabItem<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public let systemImage: String
    public let selectedSystemImage: String

    public var id: Value { value }

    public init(value: Value, title: String, systemImage: String, selectedSystemImage: String) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.selectedSystemImage = selectedSystemImage
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
                    VStack(spacing: 3) {
                        Image(systemName: isSelected ? item.selectedSystemImage : item.systemImage)
                            .font(.system(size: 21, weight: .medium))
                            .frame(height: 26)
                        Text(item.title)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(PaceColor.selectionFill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.top, PaceSpacing.xs)
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
