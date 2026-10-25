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
                    x: .value("time", bar.id),
                    y: .value(report.metric.title, bar.value ?? 0)
                )
                .foregroundStyle(color(for: bar))
                .cornerRadius(PaceChartStyle.cornerRadius(barCount: report.bars.count))
                .accessibilityLabel(bar.accessibilityLabel)
                .accessibilityValue(accessibilityValue(for: bar))
                .accessibilityHidden(bar.value == nil)
            }

            if let goal = report.goalLine {
                RuleMark(y: .value("goal", goal))
                    .foregroundStyle(PaceColor.accentStrong.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(PaceLocalization.text(de: "Ziel", en: "Goal", ru: "Цель"))
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.accentStrong)
                            .chartLineLabel()
                    }
                    .accessibilityHidden(true)
            }

            if let average = report.averageLine {
                RuleMark(y: .value("average", average))
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(verbatim: "Ø")
                            .font(PaceFont.micro.weight(.semibold))
                            .foregroundStyle(PaceColor.textSecondary)
                            .chartLineLabel()
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let bar = report.bars.first(where: { $0.id == id }) {
                        Text(bar.label)
                            .font(PaceChartStyle.axisFont)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: PaceChartStyle.gridStroke)
                    .foregroundStyle(PaceColor.border)
                AxisValueLabel()
                    .font(PaceChartStyle.axisFont)
            }
        }
        // Feste, runde Achse je Zeitraum: kein Springen der Höhen, Ziel- und Durchschnittslinie immer im Bild.
        .chartYScale(domain: 0...report.chartMaximum)
        .chartPlotStyle { plot in
            plot.padding(.top, PaceChartStyle.plotTopPadding)
        }
        // Daten innerhalb eines Diagramms ändern sich ohne Morphing; Wechsel des Zeitraums übernimmt die Karte.
        .transaction { $0.animation = nil }
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
                Button(PaceLocalization.text(
                    de: "\(bar.accessibilityLabel) öffnen",
                    en: "Open \(bar.accessibilityLabel)",
                    ru: "Открыть: \(bar.accessibilityLabel)"
                )) {
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
        return bar.reachedGoal
            ? "\(text), " + PaceLocalization.text(de: "Ziel erreicht", en: "goal reached", ru: "цель достигнута")
            : text
    }
}

private extension View {
    /// Hinterlegt die Beschriftung einer Linie, damit sie auch über Balken lesbar bleibt.
    func chartLineLabel() -> some View {
        padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(PaceColor.surface.opacity(0.9), in: Capsule())
    }
}

/// Gemeinsamer Stil der Balkendiagramme (Statistik, Kalender, Widgets): Achsen, Raster, Ecken, Abstände. Farben
/// bleiben die der Kennzahlen.
enum PaceChartStyle {
    static var axisFont: Font { PaceFont.micro }
    static var gridStroke: StrokeStyle { StrokeStyle(lineWidth: 0.5, dash: [2, 3]) }
    /// Platz über dem höchsten Balken für die Beschriftung von Ziel und Durchschnitt.
    static let plotTopPadding: CGFloat = 6
    /// Höhe der Diagrammfläche – auch für Platzhalter (Laden, keine Daten), damit nichts springt.
    static let dayHeight: CGFloat = 180
    static let periodHeight: CGFloat = 200

    /// Schmale Balken (Monat, Stunden) mit kleineren Ecken, breite (Woche) mit größeren.
    static func cornerRadius(barCount: Int) -> CGFloat {
        barCount <= 7 ? 6 : 3
    }
}
