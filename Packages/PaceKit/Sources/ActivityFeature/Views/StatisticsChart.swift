import Charts
import DesignSystem
import PaceCore
import SwiftUI

/// Balkendiagramm der Statistik: Stunden (Tag) oder Tage (Woche, Monat), mit Ziel- und Durchschnittslinie.
/// In Woche und Monat öffnet ein Tipp auf einen Balken den Tag.
struct StatisticsChart: View {
    let report: StatisticsReport
    let onSelectDay: (LocalDate) -> Void

    var body: some View {
        Chart {
            ForEach(report.bars) { bar in
                BarMark(
                    x: .value("Zeit", bar.id),
                    y: .value(report.metric.title, bar.value ?? 0)
                )
                .foregroundStyle(color(for: bar))
                .cornerRadius(report.period == .week ? 6 : 3)
                .accessibilityLabel(bar.accessibilityLabel)
                .accessibilityValue(accessibilityValue(for: bar))
                .accessibilityHidden(bar.value == nil)
            }

            if let goal = report.goalLine {
                RuleMark(y: .value("Ziel", goal))
                    .foregroundStyle(PaceColor.accentStrong.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Ziel")
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.accentStrong)
                    }
                    .accessibilityHidden(true)
            }

            if let average = report.averageLine {
                RuleMark(y: .value("Durchschnitt", average))
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Ø")
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let bar = report.bars.first(where: { $0.id == id }) {
                        Text(bar.label)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geometry[plotFrame].origin.x
                        guard let id = proxy.value(atX: x, as: String.self),
                              let day = report.bars.first(where: { $0.id == id })?.day,
                              report.bars.first(where: { $0.id == id })?.value != nil
                        else { return }
                        onSelectDay(day)
                    }
                    .allowsHitTesting(report.period != .day)
            }
        }
        .accessibilityActions {
            // VoiceOver: Tage auch ohne Tippen auf einen Balken öffnen.
            ForEach(report.bars.filter { $0.day != nil && $0.value != nil }) { bar in
                Button("\(bar.accessibilityLabel) öffnen") {
                    if let day = bar.day { onSelectDay(day) }
                }
            }
        }
    }

    /// Nicht jede Beschriftung passt: Monat jeder 5. Tag, Stunden alle 6 Stunden, Woche jeder Tag.
    private var axisValues: [String] {
        switch report.period {
        case .week:
            return report.bars.map(\.id)
        case .month:
            return report.bars.enumerated().filter { $0.offset == 0 || ($0.offset + 1) % 5 == 0 }.map(\.element.id)
        case .day:
            return report.bars.enumerated().filter { $0.offset % 6 == 0 }.map(\.element.id)
        }
    }

    private func color(for bar: StatisticsReport.Bar) -> Color {
        if bar.value == nil { return .clear }
        if report.metric == .steps, report.period != .day {
            return bar.reachedGoal ? PaceColor.accentStrong : (bar.isCurrent ? PaceColor.accent : PaceColor.chartLow)
        }
        return bar.isCurrent ? PaceColor.accentStrong : PaceColor.accent.opacity(0.7)
    }

    private func accessibilityValue(for bar: StatisticsReport.Bar) -> String {
        guard let value = bar.value else { return "" }
        let raw = report.metric == .distance ? value * 1_000 : value
        let text = report.metric.formatWithUnit(raw, formatter: ActivityFormatter())
        return bar.reachedGoal ? "\(text), Ziel erreicht" : text
    }
}
