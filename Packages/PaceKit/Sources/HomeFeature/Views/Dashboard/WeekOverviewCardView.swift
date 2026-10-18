import ActivityFeature
import DesignSystem
import SwiftUI

/// „Deine Woche“: Montag bis Sonntag als Kacheln, deren Höhe und Farbe die Schritte zeigen. Heute ist hervorgehoben.
///
/// Die Überschrift öffnet die Wochenstatistik, ein Tag die Tagesansicht dieses Tages.
struct WeekOverviewCardView: View {
    let week: WeekOverview?

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                NavigationLink(value: StatisticsRoute(period: .week, metric: .steps)) {
                    PaceCardHeader("Deine Woche", showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(week?.accessibilitySummary ?? "Deine Woche")
                .accessibilityHint("Öffnet die Wochenstatistik")

                HStack(alignment: .bottom, spacing: PaceSpacing.s) {
                    ForEach(days) { day in
                        if day.isFuture {
                            DayBar(day: day)
                                .accessibilityHidden(true)
                        } else {
                            NavigationLink(value: StatisticsRoute(period: .day, metric: .steps, day: day.date)) {
                                DayBar(day: day)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pacePressable)
                            .accessibilityLabel(day.accessibilityLabel)
                            .accessibilityHint("Öffnet die Details dieses Tages")
                        }
                    }
                }
            }
        }
    }

    private var days: [WeekOverview.Day] {
        week?.days ?? []
    }
}

private struct DayBar: View {
    let day: WeekOverview.Day

    private let minimumHeight: CGFloat = 26
    private let maximumHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: PaceSpacing.xs) {
            Group {
                if day.isFuture {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PaceColor.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(day.isToday ? PaceColor.accentStrong : PaceColor.chartLow.opacity(0.55 + 0.45 * day.level))
                }
            }
            .frame(height: minimumHeight + (maximumHeight - minimumHeight) * day.level)
            .frame(maxWidth: .infinity)

            Text(day.letter)
                .font(PaceFont.caption)
                .fontWeight(day.isToday ? .bold : .regular)
                .foregroundStyle(day.isToday ? PaceColor.textPrimary : PaceColor.textSecondary)
        }
        .frame(height: maximumHeight + 26, alignment: .bottom)
    }
}
