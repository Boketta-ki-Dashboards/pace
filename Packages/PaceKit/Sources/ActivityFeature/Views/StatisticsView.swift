import DesignSystem
import PaceCore
import SwiftUI

/// Statistik für Tag, Woche und Monat: Schritte, Distanz und aktive Kalorien mit Diagramm, Kennzahlen und Bestwerten.
public struct StatisticsView: View {
    @State private var viewModel: StatisticsViewModel

    /// Das ViewModel wird nur beim ersten Erscheinen übernommen (wie bei `@State` üblich).
    public init(viewModel: @autoclosure () -> StatisticsViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    public var body: some View {
        Group {
            switch viewModel.content {
            case .loading:
                ScrollView {
                    PaceLoadingView("Statistik wird geladen …")
                        .containerRelativeFrame(.vertical)
                }
            case .noReadAccess:
                ScrollView {
                    PaceStatusView(
                        systemImage: "hand.raised.fill",
                        title: "Keine Schrittdaten lesbar",
                        message: "Pace hat keinen Zugriff auf deine Schritte. Erlaube den Zugriff in der Health-App unter "
                            + "„Datenschutz“ → „Apps“ → „Pace“.",
                        tint: PaceColor.warning
                    )
                    .containerRelativeFrame(.vertical)
                }
            case .failed(let message):
                ScrollView {
                    PaceStatusView(
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Keine Statistik",
                        message: message,
                        tint: PaceColor.warning
                    ) {
                        Button("Erneut versuchen") {
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.pacePrimary)
                    }
                    .containerRelativeFrame(.vertical)
                }
            case .report(let report):
                ScrollView {
                    StatisticsContent(
                        report: report,
                        hourly: viewModel.hourly,
                        onSelectPeriod: { viewModel.select($0) },
                        onSelectMetric: { viewModel.select($0) },
                        onPrevious: { viewModel.showPrevious() },
                        onNext: { viewModel.showNext() },
                        onSelectDay: { viewModel.showDay($0) }
                    )
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
                }
            }
        }
        .paceScreenBackground()
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { [viewModel] in await viewModel.refresh() }
        .task { [viewModel] in await viewModel.loadIfNeeded() }
        .task(id: viewModel.hourlyKey) { [viewModel] in await viewModel.loadHourly() }
        .onChange(of: viewModel.streak.record) { viewModel.streak.saveRecordIfNeeded() }
    }
}

/// Reine Darstellung eines Statistikberichts.
struct StatisticsContent: View {
    let report: StatisticsReport
    let hourly: StatisticsViewModel.HourlyState
    /// Main-Actor-isoliert und damit `Sendable`, wie es `Binding` verlangt.
    let onSelectPeriod: @MainActor (StatisticsPeriod) -> Void
    let onSelectMetric: (StatisticsMetric) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectDay: (LocalDate) -> Void

    private let columns = [GridItem(.flexible(), spacing: PaceSpacing.s), GridItem(.flexible(), spacing: PaceSpacing.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            Picker("Zeitraum", selection: Binding(get: { report.period }, set: { onSelectPeriod($0) })) {
                ForEach(StatisticsPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)

            MetricSelector(selected: report.metric, onSelect: onSelectMetric)

            PeriodNavigator(report: report, onPrevious: onPrevious, onNext: onNext)

            summaryCard
            chartCard

            if !report.tiles.isEmpty {
                LazyVGrid(columns: columns, spacing: PaceSpacing.s) {
                    ForEach(report.tiles) { tile in
                        StatisticsTileView(tile: tile)
                    }
                }
            }

            if !report.bests.isEmpty {
                bestsCard
            }

            ForEach(report.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                if let value = report.valueText {
                    HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                        Text(value)
                            .font(PaceFont.metric(size: 44))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(report.unitText)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.accent)
                            .lineLimit(1)
                    }
                } else {
                    Text(StatisticsReport.unavailable.capitalizedFirst)
                        .font(PaceFont.title)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                if let progress = report.progress {
                    PaceProgressBar(progress: progress)
                        .padding(.vertical, PaceSpacing.xxs)
                }
                if let secondary = report.secondaryText {
                    Text(secondary)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                HStack(spacing: PaceSpacing.xs) {
                    if report.goalReached == true, report.metric == .steps {
                        Label("Ziel erreicht", systemImage: "checkmark.seal.fill")
                            .font(PaceFont.caption.weight(.semibold))
                            .foregroundStyle(PaceColor.accentStrong)
                    }
                    if let comparison = report.comparison {
                        ComparisonBadge(comparison: comparison)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var chartCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                if report.period == .day {
                    Text("Verlauf über den Tag")
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    if !report.bars.isEmpty {
                        StatisticsChart(report: report, onSelectDay: onSelectDay)
                            .frame(height: 180)
                    } else if hourly == .failed {
                        Text("Die Stundenwerte konnten nicht geladen werden.")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                } else if report.isMetricAvailable {
                    StatisticsChart(report: report, onSelectDay: onSelectDay)
                        .frame(height: 200)
                    Text("Tippe auf einen Tag für Details.")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                } else {
                    Text("Keine Daten für \(report.metric.title).")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private var bestsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Bestwerte")
                Text("In den letzten 12 Monaten")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                ForEach(report.bests) { best in
                    PaceTile {
                        HStack(spacing: PaceSpacing.s) {
                            Image(systemName: best.title == "Längste Serie" ? "flame.fill" : "trophy.fill")
                                .foregroundStyle(PaceColor.accent)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(best.title)
                                    .font(PaceFont.callout)
                                    .foregroundStyle(PaceColor.textSecondary)
                                if let detail = best.detail {
                                    Text(detail)
                                        .font(PaceFont.caption)
                                        .foregroundStyle(PaceColor.textSecondary)
                                }
                            }
                            Spacer(minLength: PaceSpacing.xs)
                            Text(best.value)
                                .font(PaceFont.headline)
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.vertical, PaceSpacing.xxs)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Auswahl der Kennzahl als Chips.
private struct MetricSelector: View {
    let selected: StatisticsMetric
    let onSelect: (StatisticsMetric) -> Void

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            ForEach(StatisticsMetric.allCases) { metric in
                let isSelected = metric == selected
                Button {
                    onSelect(metric)
                } label: {
                    Label(metric.title, systemImage: metric.systemImage)
                        .font(PaceFont.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, PaceSpacing.s)
                        .padding(.vertical, PaceSpacing.xs)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isSelected ? PaceColor.onAccent : PaceColor.textPrimary)
                        .background(isSelected ? PaceColor.accentStrong : PaceColor.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? .clear : PaceColor.border, lineWidth: 1))
                }
                .buttonStyle(.pacePressable)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Titel des Zeitraums mit Pfeilen zum vorherigen und nächsten Zeitraum.
private struct PeriodNavigator: View {
    let report: StatisticsReport
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(!report.canShowPrevious)
            .accessibilityLabel("Vorheriger Zeitraum")

            VStack(spacing: 0) {
                Text(report.title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle = report.subtitle {
                    Text(subtitle)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(!report.canShowNext)
            .accessibilityLabel("Nächster Zeitraum")
        }
        .foregroundStyle(PaceColor.accent)
    }
}

/// Veränderung gegenüber dem vorherigen Zeitraum.
private struct ComparisonBadge: View {
    let comparison: StatisticsReport.Comparison

    var body: some View {
        Label(comparison.text, systemImage: symbol)
            .font(PaceFont.caption.weight(.semibold))
            .foregroundStyle(comparison.direction == .down ? PaceColor.textSecondary : PaceColor.accentStrong)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var symbol: String {
        switch comparison.direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .same: "equal"
        }
    }
}

/// Eine Kennzahl als Kachel; „nicht verfügbar“ statt 0, wenn die Daten nicht lesbar sind.
private struct StatisticsTileView: View {
    let tile: StatisticsReport.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            Label(tile.title, systemImage: tile.kind.systemImage)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tile.value)
                .font(tile.isAvailable ? PaceFont.headline : PaceFont.callout)
                .monospacedDigit()
                .foregroundStyle(tile.isAvailable ? PaceColor.textPrimary : PaceColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail = tile.detail {
                Text(detail)
                    .font(PaceFont.micro)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(PaceSpacing.s)
        .paceCardBackground(cornerRadius: PaceRadius.tile)
        .accessibilityElement(children: .combine)
    }
}

extension StatisticsReport.Tile.Kind {
    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "shoeprints.fill"
        case .activeEnergy: "flame.fill"
        case .flights: "figure.stairs"
        case .exercise: "stopwatch.fill"
        case .goal: "scope"
        case .progress: "chart.pie.fill"
        case .average: "divide"
        case .goalDays: "checkmark.circle"
        case .bestDay: "trophy"
        case .previous: "clock.arrow.circlepath"
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
