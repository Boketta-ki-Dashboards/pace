import DesignSystem
import PaceCore
import SwiftUI

/// Statistik für Tag, Woche und Monat: Schritte, Distanz und aktive Kalorien mit Diagramm, Kennzahlen und Bestwerten.
/// Unterseite mit Pace-Kopf („‹ Home · pace · Statistik“); die Tagesansicht führt zu den ausführlichen Tagesdetails.
public struct StatisticsView: View {
    @State private var viewModel: StatisticsViewModel
    @State private var detailsDay: LocalDate?
    private let backTitle: String?

    /// Das ViewModel wird nur beim ersten Erscheinen übernommen (wie bei `@State` üblich).
    /// - Parameter backTitle: Ziel des Zurück-Links, z. B. „Home“ oder „Profil“; ohne Angabe „Zurück“.
    public init(viewModel: @autoclosure () -> StatisticsViewModel, backTitle: String? = nil) {
        _viewModel = State(initialValue: viewModel())
        self.backTitle = backTitle
    }

    public var body: some View {
        ScrollView {
            StatisticsContent(
                report: report,
                hourly: viewModel.hourly,
                backTitle: backTitle,
                state: state,
                onSelectPeriod: { viewModel.select($0) },
                onSelectMetric: { viewModel.select($0) },
                onPrevious: { viewModel.showPrevious() },
                onNext: { viewModel.showNext() },
                onSelectDay: { viewModel.showDay($0) },
                onOpenDayDetails: { day in detailsDay = day },
                onRetry: { [viewModel] in
                    Task { await viewModel.refresh() }
                }
            )
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.l)
        }
        .paceScreenBackground()
        .paceSubpage()
        .refreshable { [viewModel] in await viewModel.refresh() }
        .task { [viewModel] in await viewModel.loadIfNeeded() }
        .task(id: viewModel.hourlyKey) { [viewModel] in await viewModel.loadHourly() }
        .onChange(of: viewModel.streak.record) { viewModel.streak.saveRecordIfNeeded() }
        .navigationDestination(item: $detailsDay) { day in
            DayDetailsView(viewModel: viewModel.dayDetails(for: day))
        }
    }

    private var report: StatisticsReport? {
        guard case .report(let report) = viewModel.content else { return nil }
        return report
    }

    private var state: StatisticsContent.Phase {
        switch viewModel.content {
        case .loading: .loading
        case .noReadAccess: .noReadAccess
        case .failed(let message): .failed(message)
        case .report: .ready
        }
    }
}

/// Reine Darstellung eines Statistikberichts inklusive Kopf (ohne Navigation und Scrollen) – auch für Snapshots.
struct StatisticsContent: View {
    enum Phase: Equatable {
        case loading
        case noReadAccess
        case failed(String)
        case ready
    }

    let report: StatisticsReport?
    let hourly: StatisticsViewModel.HourlyState
    var backTitle: String?
    var state: Phase = .ready
    /// Main-Actor-isoliert und damit `Sendable`, wie es `Binding` verlangt.
    let onSelectPeriod: @MainActor (StatisticsPeriod) -> Void
    let onSelectMetric: (StatisticsMetric) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectDay: (LocalDate) -> Void
    var onOpenDayDetails: ((LocalDate) -> Void)?
    var onRetry: () -> Void = {}

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: PaceSpacing.s, alignment: .top),
            GridItem(.flexible(), spacing: PaceSpacing.s, alignment: .top),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle ?? StatisticsTexts.back, title: StatisticsTexts.title)
                .padding(.bottom, PaceSpacing.xs)

            if let report, state == .ready {
                reportBody(report)
            } else {
                statusCard
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch state {
        case .noReadAccess:
            PaceCard {
                PaceStatusView(
                    systemImage: "figure.walk",
                    title: CalendarTexts.noAccessTitle,
                    message: CalendarTexts.noAccessMessage
                )
            }
        case .failed(let message):
            PaceCard {
                PaceStatusView(systemImage: "arrow.clockwise", title: StatisticsTexts.failedTitle, message: message) {
                    Button(CalendarTexts.retry, action: onRetry)
                        .buttonStyle(.pacePrimary)
                }
            }
        case .loading, .ready:
            PaceCard {
                PaceLoadingView(StatisticsTexts.loading)
                    .frame(minHeight: 260)
            }
        }
    }

    @ViewBuilder
    private func reportBody(_ report: StatisticsReport) -> some View {
        PaceSegmentedControl(
            options: StatisticsPeriod.allCases.map { (value: $0, title: $0.title) },
            selection: Binding(get: { report.period }, set: { onSelectPeriod($0) })
        )

        MetricSelector(selected: report.metric, onSelect: onSelectMetric)

        PeriodNavigator(report: report, onPrevious: onPrevious, onNext: onNext)

        summaryCard(report)
        chartCard(report)

        if report.period == .day, let onOpenDayDetails {
            dayDetailsLink(day: report.anchor, action: onOpenDayDetails)
        }

        if !report.tiles.isEmpty {
            LazyVGrid(columns: columns, spacing: PaceSpacing.s) {
                ForEach(report.tiles) { tile in
                    StatisticsTileView(tile: tile)
                }
            }
        }

        if !report.bests.isEmpty {
            bestsCard(report)
        }

        ForEach(report.notes, id: \.self) { note in
            Label(note, systemImage: "info.circle")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryCard(_ report: StatisticsReport) -> some View {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: PaceSpacing.xs) {
                    if report.goalReached == true, report.metric == .steps {
                        Label(StatisticsTexts.goalReached, systemImage: "checkmark.seal.fill")
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

    private func chartCard(_ report: StatisticsReport) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                if report.period == .day {
                    Text(CalendarTexts.hourlyTitle)
                        .font(PaceFont.cardTitle)
                        .foregroundStyle(PaceColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if !report.isMetricAvailable {
                        Text(StatisticsTexts.noData(for: report.metric))
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if !report.bars.isEmpty {
                        StatisticsChart(report: report, onSelectDay: onSelectDay)
                            .frame(height: 180)
                    } else if hourly == .failed {
                        Text(CalendarTexts.hourlyFailed)
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
                    Text(StatisticsTexts.tapDayHint)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                } else {
                    Text(StatisticsTexts.noData(for: report.metric))
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private func dayDetailsLink(day: LocalDate, action: @escaping (LocalDate) -> Void) -> some View {
        Button {
            action(day)
        } label: {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(StatisticsTexts.allDayDetails)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(StatisticsTexts.allDayDetailsDetail)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PaceSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(PaceSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
    }

    private func bestsCard(_ report: StatisticsReport) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(StatisticsTexts.bests)
                Text(StatisticsTexts.lastTwelveMonths)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                ForEach(report.bests) { best in
                    PaceTile {
                        HStack(spacing: PaceSpacing.s) {
                            Image(systemName: best.kind == .streak ? "flame.fill" : "trophy.fill")
                                .foregroundStyle(best.kind == .streak ? PaceColor.streak : PaceColor.accent)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(best.title)
                                    .font(PaceFont.callout)
                                    .foregroundStyle(PaceColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
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
                                .layoutPriority(1)
                        }
                        .padding(.vertical, PaceSpacing.xxs)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Texte der Statistik-Ansicht.
enum StatisticsTexts {
    static var title: String { PaceLocalization.text(de: "Statistik", en: "Statistics", ru: "Статистика") }
    static var back: String { PaceLocalization.text(de: "Zurück", en: "Back", ru: "Назад") }
    static var loading: String {
        PaceLocalization.text(de: "Statistik wird geladen …", en: "Loading statistics …", ru: "Статистика загружается…")
    }
    static var failedTitle: String { PaceLocalization.text(de: "Keine Statistik", en: "No statistics", ru: "Нет статистики") }
    static var goalReached: String { PaceLocalization.text(de: "Ziel erreicht", en: "Goal reached", ru: "Цель достигнута") }
    static var tapDayHint: String {
        PaceLocalization.text(de: "Tippe auf einen Tag für Details.", en: "Tap a day for details.", ru: "Нажми на день, чтобы увидеть подробности.")
    }
    static var bests: String { PaceLocalization.text(de: "Bestwerte", en: "Personal bests", ru: "Лучшие результаты") }
    static var lastTwelveMonths: String {
        PaceLocalization.text(de: "In den letzten 12 Monaten", en: "In the last 12 months", ru: "За последние 12 месяцев")
    }
    static var allDayDetails: String { PaceLocalization.text(de: "Alle Tagesdetails", en: "All day details", ru: "Все подробности дня") }
    static var allDayDetailsDetail: String {
        PaceLocalization.text(
            de: "Ziel des Tages, Kacheln, Streak und die letzten 7 Tage",
            en: "Goal of the day, tiles, streak and the last 7 days",
            ru: "Цель дня, показатели, серия и последние 7 дней"
        )
    }
    static var previousPeriod: String { PaceLocalization.text(de: "Vorheriger Zeitraum", en: "Previous period", ru: "Предыдущий период") }
    static var nextPeriod: String { PaceLocalization.text(de: "Nächster Zeitraum", en: "Next period", ru: "Следующий период") }

    static func noData(for metric: StatisticsMetric) -> String {
        let title = metric.title
        return PaceLocalization.text(de: "Keine Daten für \(title).", en: "No data for \(title).", ru: "Нет данных: \(title).")
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
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, PaceSpacing.xs)
                        .padding(.vertical, PaceSpacing.xs)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                        .background(isSelected ? PaceColor.selectionFill : PaceColor.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? PaceColor.accent.opacity(0.4) : PaceColor.border, lineWidth: 1))
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
                    .opacity(report.canShowPrevious ? 1 : 0.3)
            }
            .disabled(!report.canShowPrevious)
            .accessibilityLabel(StatisticsTexts.previousPeriod)

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
                    .opacity(report.canShowNext ? 1 : 0.3)
            }
            .disabled(!report.canShowNext)
            .accessibilityLabel(StatisticsTexts.nextPeriod)
        }
        .foregroundStyle(PaceColor.accent)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                .strokeBorder(PaceColor.border, lineWidth: 1)
        )
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

/// Eine Kennzahl als Kachel; „nicht verfügbar“ statt 0, wenn die Daten nicht lesbar sind. Titel brechen um statt
/// abgeschnitten zu werden (z. B. „Trainingsminuten“, „Stockwerke“).
private struct StatisticsTileView: View {
    let tile: StatisticsReport.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xxs) {
                // Feste Breite, damit die Titel aller Kacheln auf derselben Linie beginnen.
                Image(systemName: tile.kind.systemImage)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                // Einzelne lange Wörter verkleinern statt mitten im Wort trennen.
                Text(tile.title)
                    .lineLimit(tile.title.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(PaceFont.caption)
            .foregroundStyle(PaceColor.textSecondary)
            Text(tile.value)
                .font(tile.isAvailable ? .system(.title3, weight: .bold) : PaceFont.callout)
                .monospacedDigit()
                .foregroundStyle(tile.isAvailable ? PaceColor.textPrimary : PaceColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail = tile.detail {
                Text(detail)
                    .font(PaceFont.micro)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(PaceSpacing.s)
        .paceCardBackground(cornerRadius: PaceRadius.tile)
        .accessibilityElement(children: .combine)
    }
}

extension StatisticsReport.Tile.Kind {
    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "mappin.and.ellipse"
        case .activeEnergy: "flame"
        case .flights: "figure.stairs"
        case .exercise: "clock"
        case .goal: "scope"
        case .progress: "chart.pie"
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
