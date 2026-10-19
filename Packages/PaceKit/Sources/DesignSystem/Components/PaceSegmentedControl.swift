import SwiftUI

/// Segmente wie „Alle | Freunde | Gruppen“: das gewählte gefüllt (Dunkelgrün bzw. Mint), die anderen hellgrau.
/// Reine SwiftUI-Darstellung – sieht in Light und Dark Mode wie in den Pace-Referenzen aus.
public struct PaceSegmentedControl<Value: Hashable>: View {
    private let options: [(value: Value, title: String)]
    @Binding private var selection: Value

    public init(options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? PaceColor.onAccent : PaceColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            isSelected ? PaceColor.accentStrong : PaceColor.fieldBackground,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
