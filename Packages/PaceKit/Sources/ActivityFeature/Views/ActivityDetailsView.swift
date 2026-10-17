import DesignSystem
import PaceCore
import SwiftUI

/// Detaillierte Statistiken: heute und die letzten 7 Tage.
public struct ActivityDetailsView: View {
    private let source: any ActivityOverviewSource
    private let formatter: ActivityFormatter

    public init(source: any ActivityOverviewSource, formatter: ActivityFormatter = ActivityFormatter()) {
        self.source = source
        self.formatter = formatter
    }

    public var body: some View {
        Group {
            switch source.detailsState {
            case .loading:
                ScrollView {
                    PaceLoadingView("Statistiken werden geladen …")
                        .containerRelativeFrame(.vertical)
                }
            case .loaded(let overview, let notice):
                ActivityDetailsContent(
                    stats: ActivityStatsViewModel(overview: overview, formatter: formatter),
                    notice: notice
                )
            case .unavailable(let message):
                ScrollView {
                    PaceStatusView(
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Keine Statistiken",
                        message: message,
                        tint: PaceColor.warning
                    ) {
                        Button("Erneut versuchen") {
                            Task { await source.refresh() }
                        }
                        .buttonStyle(.pacePrimary)
                    }
                    .containerRelativeFrame(.vertical)
                }
            }
        }
        .paceScreenBackground()
        .navigationTitle("Aktivität")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { [source] in await source.refresh() }
    }
}

/// Reine Darstellung der Statistiken.
struct ActivityDetailsContent: View {
    let stats: ActivityStatsViewModel
    /// Hinweis über den Statistiken, z. B. dass die letzte Aktualisierung fehlschlug.
    var notice: String?

    private let columns = [GridItem(.flexible(), spacing: PaceSpacing.s), GridItem(.flexible(), spacing: PaceSpacing.s)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaceSpacing.xl) {
                if let notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                todaySection
                weekSection
                if let note = stats.manualStepsNote {
                    Label(note, systemImage: "info.circle")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .padding(PaceSpacing.m)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSectionHeader("Heute", detail: stats.todayTitle)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(stats.todaySteps)
                        .font(PaceFont.metric(size: 44))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                    Text("Schritte")
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.accent)
                    if let healthSteps = stats.todayHealthSteps {
                        Text("In Apple Health: \(healthSteps) Schritte")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .padding(.top, PaceSpacing.xxs)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if !stats.todayMetrics.isEmpty {
                LazyVGrid(columns: columns, spacing: PaceSpacing.s) {
                    ForEach(stats.todayMetrics) { metric in
                        ActivityMetricTile(metric: metric)
                    }
                }
            }
        }
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSectionHeader("Letzte 7 Tage")

            PaceCard {
                WeeklyStepsChart(days: stats.chartDays, average: stats.chartAverage)
                    .frame(height: 180)
            }

            HStack(spacing: PaceSpacing.s) {
                ForEach(stats.weekHighlights, id: \.title) { highlight in
                    PaceCard {
                        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                            Text(highlight.title)
                                .font(PaceFont.caption)
                                .foregroundStyle(PaceColor.textSecondary)
                            Text(highlight.value)
                                .font(PaceFont.title)
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textPrimary)
                            if let detail = highlight.detail {
                                Text(detail)
                                    .font(PaceFont.caption)
                                    .foregroundStyle(PaceColor.textSecondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            PaceCard {
                VStack(spacing: PaceSpacing.s) {
                    ForEach(stats.weekTotals) { total in
                        HStack {
                            Text(total.title)
                                .foregroundStyle(PaceColor.textSecondary)
                            Spacer()
                            Text(total.value)
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textPrimary)
                        }
                        .font(PaceFont.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct ActivityMetricTile: View {
    let metric: ActivityStatsViewModel.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            Label(metric.title, systemImage: metric.kind.systemImage)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
            Text(metric.value)
                .font(PaceFont.title)
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PaceSpacing.m)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension ActivityStatsViewModel.Metric.Kind {
    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "shoeprints.fill"
        case .activeEnergy: "flame.fill"
        case .flights: "figure.stairs"
        case .exercise: "stopwatch.fill"
        }
    }
}
