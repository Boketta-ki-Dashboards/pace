import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Die heutige Wettbewerbs-Schrittzahl als dominanter Wert, darunter kompakte Nebenwerte mit Link zu den Details.
struct HomeStepsHero<Details: View>: View {
    let today: DailyActivitySummary
    let formatter: ActivityFormatter
    @ViewBuilder let details: () -> Details

    @ScaledMetric(relativeTo: .largeTitle) private var metricSize: CGFloat = 76

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("HEUTE")
                        .font(PaceFont.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(PaceColor.textSecondary)
                    Spacer()
                    Text(formatter.dayLong(today.date))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }

                Text(formatter.steps(today.competitionSteps))
                    .font(PaceFont.metric(size: metricSize))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: Double(today.competitionSteps)))
                    .animation(.snappy, value: today.competitionSteps)

                Text("SCHRITTE")
                    .font(PaceFont.headline.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(PaceColor.accent)

                Divider()
                    .padding(.vertical, PaceSpacing.s)

                NavigationLink {
                    details()
                } label: {
                    secondaryStats
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var secondaryStats: some View {
        HStack(spacing: PaceSpacing.m) {
            if let energy = today.activeEnergyKilocalories {
                Label(formatter.energy(kilocalories: energy), systemImage: "flame.fill")
                    .labelStyle(SecondaryStatLabelStyle(tint: PaceColor.accent))
            }
            if let distance = today.walkingRunningDistanceMeters {
                Label(formatter.distance(meters: distance), systemImage: "shoeprints.fill")
                    .labelStyle(SecondaryStatLabelStyle(tint: PaceColor.success))
            }
            if today.activeEnergyKilocalories == nil, today.walkingRunningDistanceMeters == nil {
                Text("Statistiken")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zeigt detaillierte Statistiken")
    }
}

private struct SecondaryStatLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: PaceSpacing.xxs) {
            configuration.icon
                .foregroundStyle(tint)
            configuration.title
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
        }
        .font(PaceFont.callout.weight(.semibold))
    }
}
