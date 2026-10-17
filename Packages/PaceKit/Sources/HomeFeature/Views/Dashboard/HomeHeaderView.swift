import DesignSystem
import SwiftUI

/// Kopf des Dashboards: Wortmarke, Begrüßung, „Anpassen“ und Mitteilungen.
struct HomeHeaderView: View {
    let greeting: String
    let onCustomize: () -> Void
    let onNotifications: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            HStack(alignment: .center) {
                PaceWordmark(height: 34)
                Spacer()
                Button(action: onCustomize) {
                    Label("Anpassen", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.paceCompact)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(greeting)
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onNotifications) {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundStyle(PaceColor.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel("Mitteilungen")
            }
        }
        .padding(.top, PaceSpacing.xs)
    }
}
