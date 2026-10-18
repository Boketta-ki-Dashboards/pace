import ActivityFeature
import DesignSystem
import SwiftUI

/// „Deine Woche“: Montag bis Sonntag als Kacheln, deren Höhe und Farbe die Schritte zeigen. Heute ist hervorgehoben.
///
/// Die Überschrift öffnet die Wochenstatistik, ein Tag die Tagesansicht dieses Tages. Klein zeigt nur die Summen,
/// groß zusätzlich Durchschnitt und Zieltage unter den Balken.
struct WeekOverviewCardView: View {
    let week: WeekOverview?
    var size: HomeModuleSize = .medium
    /// Grund, warum es keine Wochenwerte gibt (kein Zugriff, Fehler); ohne Werte und ohne Grund wird geladen.
    var unavailableText: String?

    var body: some View {
        if size == .small {
            compact
        } else {
            full
        }
    }

    private var compact: some View {
        NavigationLink(value: StatisticsRoute(period: .week, metric: .steps)) {
            PaceCard(padding: PaceSpacing.s) {
                HStack(spacing: PaceSpacing.s) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(PaceColor.accent)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Diese Woche: \(week?.totalText ?? "–") Schritte")
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(week?.goalDaysText ?? unavailableText ?? " ")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet die Wochenstatistik")
    }

    private var full: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                NavigationLink(value: StatisticsRoute(period: .week, metric: .steps)) {
                    PaceCardHeader("Deine Woche", showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(week?.accessibilitySummary ?? "Deine Woche")
                .accessibilityHint("Öffnet die Wochenstatistik")

                if week == nil {
                    if let unavailableText {
                        Text(unavailableText)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }

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

                if size == .large, let week {
                    Divider()
                    HStack {
                        WeekFact(title: "Gesamt", value: week.totalText)
                        WeekFact(title: "Durchschnitt", value: week.averageText)
                    }
                    Text(week.goalDaysText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
    }

    private var days: [WeekOverview.Day] {
        week?.days ?? []
    }
}

private struct WeekFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
            Text(value)
                .font(PaceFont.headline)
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
