import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Aktivitäts-Widget: eine Kennzahl (Schritte, Distanz oder aktive Kalorien) der letzten sieben Tage.
///
/// - Klein: Wert von heute. Mittel: dazu ein kleines Wochendiagramm.
/// - Groß: dazu Summe und Durchschnitt. Max: großes Diagramm mit Werten, Summe, Durchschnitt und bestem Tag.
struct ActivityWidgetContent: View {
    let widget: HomeActivityWidget?
    let size: HomeModuleSize
    let unavailableText: String?

    var body: some View {
        if let widget {
            NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .week, metric: Self.statisticsMetric(widget.metric)))) {
                content(widget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(PaceLocalization.text(
                de: "Öffnet die Wochenstatistik", en: "Opens the weekly statistics", ru: "Открывает статистику за неделю"
            ))
        } else if let unavailableText {
            HomeWidgetHint(systemImage: "info.circle", text: unavailableText)
        } else {
            HomeWidgetLoading()
        }
    }

    @ViewBuilder
    private func content(_ widget: HomeActivityWidget) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HStack(alignment: .center, spacing: PaceSpacing.s) {
                Image(systemName: widget.metric.systemImage)
                    .font(.title2)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 44, height: 44)
                    .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(widget.todayText ?? "–")
                        .font(.system(.title2, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(widget.isTodayEstimated
                        ? HomeActivityWidget.todayTitle + " · " + ActivityTexts.estimatedActiveCalories
                        : HomeActivityWidget.todayTitle + " · " + widget.metric.title)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if size == .small {
                    HomeRowChevron()
                }
            }

            if widget.days.allSatisfy({ $0.value == nil }) {
                if size != .small {
                    HomeWidgetHint(systemImage: "info.circle", text: HomeActivityWidget.unavailableText)
                }
            } else {
                switch size {
                case .small:
                    EmptyView()
                case .medium:
                    HomeBarChart(bars: bars(widget), height: 54)
                case .large:
                    HomeBarChart(bars: bars(widget), height: 70)
                    totals(widget)
                case .max:
                    HomeBarChart(bars: bars(widget), height: 110, showsValues: true)
                    totals(widget)
                    if let best = widget.bestDayText {
                        HomeStatTile(title: HomeActivityWidget.bestDayTitle, value: best, systemImage: "star")
                    }
                }
            }
        }
    }

    private func totals(_ widget: HomeActivityWidget) -> some View {
        HStack(spacing: PaceSpacing.xs) {
            HomeStatTile(title: HomeActivityWidget.totalTitle, value: widget.totalText ?? "–")
            HomeStatTile(title: HomeActivityWidget.averageTitle, value: widget.averageText ?? "–")
        }
    }

    private func bars(_ widget: HomeActivityWidget) -> [HomeBarChart.Bar] {
        widget.days.map { day in
            HomeBarChart.Bar(
                id: day.id.isoString,
                label: day.letter,
                level: (day.value ?? 0) / widget.maximum,
                valueText: day.valueText,
                isHighlighted: day.isToday,
                isEmpty: day.value == nil
            )
        }
    }

    static func statisticsMetric(_ metric: HomeActivityMetric) -> StatisticsMetric {
        switch metric {
        case .steps: .steps
        case .distance: .distance
        case .activeEnergy: .activeEnergy
        }
    }
}
