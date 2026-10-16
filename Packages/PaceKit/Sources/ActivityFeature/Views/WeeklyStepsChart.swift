import Charts
import DesignSystem
import SwiftUI

/// Balkendiagramm der Wettbewerbsschritte pro Tag mit Durchschnittslinie.
struct WeeklyStepsChart: View {
    let days: [ActivityStatsViewModel.ChartDay]
    let average: Int

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Tag", day.weekday),
                    y: .value("Schritte", day.competitionSteps)
                )
                .foregroundStyle(day.isToday ? PaceColor.accent : PaceColor.accent.opacity(0.35))
                .cornerRadius(6)
                .accessibilityLabel(day.isToday ? "Heute" : day.weekday)
                .accessibilityValue("\(day.competitionSteps) Schritte")
            }

            if average > 0 {
                RuleMark(y: .value("Durchschnitt", average))
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Ø")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}
