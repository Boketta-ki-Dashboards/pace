import ActivityFeature
import DesignSystem
import SwiftUI

/// „Deine Woche“: Montag bis Sonntag.
///
/// - Klein: Summe der Woche und Zieltage in einer Zeile.
/// - Mittel: sieben Kacheln wie im Home-Design (Höhe und Farbe zeigen die Schritte, heute dunkel).
/// - Groß: dazu Gesamt, Durchschnitt und Zieltage.
/// - Max: Balkendiagramm mit Achse und Werten, dazu die Kennzahlen.
struct WeekWidgetContent: View {
    let week: WeekOverview?
    let size: HomeModuleSize
    let unavailableText: String?

    var body: some View {
        if let week {
            switch size {
            case .small: compact(week)
            case .medium: tiles(week)
            case .large:
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    tiles(week)
                    facts(week)
                }
            case .max:
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    WeekAxisChart(week: week)
                    facts(week)
                }
            }
        } else if let unavailableText {
            HomeWidgetHint(systemImage: "info.circle", text: unavailableText)
        } else {
            HomeWidgetLoading()
        }
    }

    private func compact(_ week: WeekOverview) -> some View {
        NavigationLink(value: StatisticsRoute(period: .week, metric: .steps)) {
            HStack(spacing: PaceSpacing.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(PaceLocalization.text(
                        de: "Diese Woche: \(week.totalText)",
                        en: "This week: \(week.totalText)",
                        ru: "На этой неделе: \(week.totalText)"
                    ))
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    Text(week.goalDaysText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PaceSpacing.xs)
                HomeRowChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ week: WeekOverview) -> some View {
        HStack(alignment: .bottom, spacing: PaceSpacing.s) {
            ForEach(week.days) { day in
                if day.isFuture {
                    WeekDayTile(day: day)
                        .accessibilityHidden(true)
                } else {
                    NavigationLink(value: StatisticsRoute(period: .day, metric: .steps, day: day.date)) {
                        WeekDayTile(day: day)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(day.accessibilityLabel)
                    .accessibilityHint(PaceLocalization.text(
                        de: "Öffnet die Details dieses Tages", en: "Opens this day's details", ru: "Открывает подробности дня"
                    ))
                }
            }
        }
    }

    private func facts(_ week: WeekOverview) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            HStack(spacing: PaceSpacing.xs) {
                HomeStatTile(title: PaceLocalization.text(de: "Gesamt", en: "Total", ru: "Всего"), value: week.totalText)
                HomeStatTile(title: PaceLocalization.text(de: "Durchschnitt", en: "Average", ru: "В среднем"), value: week.averageText)
            }
            Label(week.goalDaysText, systemImage: "checkmark.circle")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
        }
    }
}

/// Eine Tageskachel der Woche.
private struct WeekDayTile: View {
    let day: WeekOverview.Day

    private let minimumHeight: CGFloat = 30
    private let maximumHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: PaceSpacing.xs) {
            Group {
                if day.isFuture {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PaceColor.chartLow.opacity(0.35))
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(day.isToday ? PaceColor.accentStrong : PaceColor.chartLow.opacity(0.6 + 0.4 * day.level))
                }
            }
            .frame(height: day.isFuture ? minimumHeight + 8 : minimumHeight + (maximumHeight - minimumHeight) * day.level)
            .frame(maxWidth: .infinity)

            Text(day.letter)
                .font(PaceFont.caption)
                .fontWeight(day.isToday ? .bold : .regular)
                .foregroundStyle(day.isToday ? PaceColor.textPrimary : PaceColor.textSecondary)
        }
        .frame(height: maximumHeight + 26, alignment: .bottom)
    }
}

/// Wochendiagramm mit Achse (0 bis zum Maximum), wie in der großen Darstellung des Anpassen-Designs.
private struct WeekAxisChart: View {
    let week: WeekOverview

    private let chartHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(axisValues.reversed(), id: \.self) { value in
                    Text(value.paceFormatted)
                        .font(PaceFont.micro)
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(maxHeight: .infinity, alignment: value == 0 ? .bottom : .top)
                }
            }
            .frame(height: chartHeight)
            .padding(.bottom, 24)
            .accessibilityHidden(true)

            HomeBarChart(
                bars: week.days.map { day in
                    HomeBarChart.Bar(
                        id: day.id.isoString,
                        label: day.shortName,
                        level: Double(day.steps ?? 0) / Double(axisMaximum),
                        valueText: day.steps.map(\.paceFormatted),
                        isHighlighted: day.isToday,
                        isEmpty: day.isFuture
                    )
                },
                height: chartHeight
            )
            .overlay(alignment: .top) {
                // Ziellinie des heutigen Ziels.
                if let goal = week.days.first(where: \.isToday)?.goal, goal <= axisMaximum {
                    Rectangle()
                        .fill(PaceColor.accent.opacity(0.6))
                        .frame(height: 1)
                        .offset(y: chartHeight * (1 - Double(goal) / Double(axisMaximum)))
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.accessibilitySummary)
    }

    /// Abstand der Achsenwerte: runde Schritte, sodass drei davon das Maximum der Woche abdecken (z. B. 4.000).
    private var axisStep: Int {
        let steps = [1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 8_000, 10_000, 15_000, 20_000, 30_000]
        return steps.first { $0 * 3 >= week.scale } ?? (week.scale + 2) / 3
    }

    /// Obere Achsengrenze, z. B. 12.000.
    private var axisMaximum: Int {
        axisStep * 3
    }

    private var axisValues: [Int] {
        [0, axisStep, axisStep * 2, axisMaximum]
    }
}
