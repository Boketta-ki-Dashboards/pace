import DesignSystem
import PaceCore
import SwiftUI

/// Zeigt die heutige Schrittzahl prominent an.
struct TodayStepsCard: View {
    let count: DailyStepCount

    @ScaledMetric(relativeTo: .largeTitle) private var metricSize: CGFloat = 64

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                Label {
                    Text(count.day, format: .dateTime.weekday(.wide).day().month(.wide))
                } icon: {
                    Image(systemName: "figure.walk")
                }
                .font(PaceFont.headline)
                .foregroundStyle(PaceColor.textSecondary)

                Text(count.steps, format: .number)
                    .font(PaceFont.metric(size: metricSize))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: Double(count.steps)))

                Text("Schritte")
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.accent)

                Text("Aktualisiert um \(count.updatedAt, format: .dateTime.hour().minute())")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .padding(.top, PaceSpacing.xs)
            }
        }
        .animation(.snappy, value: count.steps)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TodayStepsCard(count: DailyStepCount(day: .now, steps: 12_045, updatedAt: .now))
        .padding()
        .paceScreenBackground()
}
