import Charts
import DesignSystem
import PaceCore
import SwiftUI

/// Tagesdetails (Referenzbild 8): große Wortmarke, „Tagesdetails“ mit Datum, Ring und Ziel des Tages, Kacheln,
/// optionale Herzwerte, Aktivität im Tagesverlauf, Streak und die letzten 7 Tage.
public struct DayDetailsView: View {
    @State private var viewModel: DayDetailsViewModel

    /// Das ViewModel wird nur beim ersten Erscheinen übernommen (wie bei `@State` üblich).
    public init(viewModel: @autoclosure () -> DayDetailsViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            DayDetailsContent(
                backTitle: viewModel.backTitle,
                content: viewModel.content,
                heartRate: DayDetailsContent.HeartRateOffer(
                    isOffered: viewModel.offersHeartRate,
                    isRequesting: viewModel.isRequestingHeartRate,
                    requestFailed: viewModel.heartRateRequestFailed,
                    showsNoValuesNote: viewModel.showsNoHeartRateNote
                ),
                onRequestHeartRate: { [viewModel] in
                    Task { await viewModel.requestHeartRateAccess() }
                },
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
    }
}

/// Reine Darstellung der Tagesdetails inklusive Kopf (ohne Navigation und Scrollen) – auch für Snapshots.
struct DayDetailsContent: View {
    /// Angebot und Zustand der optionalen Herzwerte.
    struct HeartRateOffer: Equatable {
        var isOffered = false
        var isRequesting = false
        var requestFailed = false
        var showsNoValuesNote = false
    }

    let backTitle: String
    let content: DayDetailsViewModel.Content
    var heartRate = HeartRateOffer()
    var onRequestHeartRate: () -> Void = {}
    var onRetry: () -> Void = {}

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: PaceSpacing.s, alignment: .top),
            GridItem(.flexible(), spacing: PaceSpacing.s, alignment: .top),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            switch content {
            case .report(let report):
                header(subtitle: report.dateText)
                progressCard(report)
                tiles(report)
                hourlyCard(report.hourly)
                streakCard(report.streak)
                recentDaysCard(report.recentDays)
                ForEach(report.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .loading:
                header(subtitle: nil)
                PaceCard {
                    PaceLoadingView(CalendarTexts.dayDetailsLoading)
                        .frame(minHeight: 260)
                }
            case .noReadAccess:
                header(subtitle: nil)
                PaceCard {
                    PaceStatusView(
                        systemImage: "figure.walk",
                        title: CalendarTexts.noAccessTitle,
                        message: CalendarTexts.noAccessMessage
                    )
                }
            case .failed(let message):
                header(subtitle: nil)
                PaceCard {
                    PaceStatusView(systemImage: "arrow.clockwise", title: CalendarTexts.failedTitle, message: message) {
                        Button(CalendarTexts.retry, action: onRetry)
                            .buttonStyle(.pacePrimary)
                    }
                }
            }
        }
    }

    private func header(subtitle: String?) -> some View {
        PaceSubpageHeader(backTitle: backTitle, title: CalendarTexts.dayDetailsTitle, subtitle: subtitle, titleSize: .medium)
            .padding(.bottom, PaceSpacing.xs)
    }

    // MARK: Große Karte

    @ViewBuilder
    private func progressCard(_ report: DayDetailsReport) -> some View {
        if let progress = report.progress {
            DayProgressCard(progress: progress)
        }
    }

    // MARK: Kacheln

    private func tiles(_ report: DayDetailsReport) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            LazyVGrid(columns: columns, spacing: PaceSpacing.s) {
                ForEach(report.tiles + report.heartTiles) { tile in
                    DayDetailsTileView(tile: tile)
                }
            }
            if !report.heartTiles.isEmpty {
                Text(CalendarTexts.heartRateSource)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .padding(.horizontal, PaceSpacing.xxs)
            } else if heartRate.isOffered {
                heartRateOfferButton
            }
            if heartRate.requestFailed {
                Text(CalendarTexts.heartRateRequestFailed)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if heartRate.showsNoValuesNote, report.heartTiles.isEmpty {
                Text(CalendarTexts.noHeartRate)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heartRateOfferButton: some View {
        Button(action: onRequestHeartRate) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CalendarTexts.showHeartRate)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(CalendarTexts.showHeartRateDetail)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: PaceSpacing.xs)
                if heartRate.isRequesting {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(PaceSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
        .disabled(heartRate.isRequesting)
    }

    // MARK: Tagesverlauf

    private func hourlyCard(_ hourly: DayDetailsReport.Hourly) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Text(CalendarTexts.hourlyTitle)
                    .font(PaceFont.cardTitle)
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                switch hourly {
                case .loaded(let bars):
                    HourlyActivityChart(bars: bars)
                        .frame(height: 140)
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 140)
                case .failed:
                    Text(CalendarTexts.hourlyFailed)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                case .unavailable:
                    Text(CalendarTexts.hourlyUnavailable)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
    }

    // MARK: Streak

    private func streakCard(_ streak: DayDetailsReport.Streak) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Text(CalendarTexts.streakTitle)
                    .font(PaceFont.cardTitle)
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: PaceSpacing.s) {
                        streakCurrent(streak)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle()
                            .fill(PaceColor.border)
                            .frame(width: 1, height: 56)
                        streakRecord(streak)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        streakCurrent(streak)
                        Divider()
                        streakRecord(streak)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CalendarTexts.streakTitle + ": " + streak.accessibilityLabel)
        }
    }

    private func streakCurrent(_ streak: DayDetailsReport.Streak) -> some View {
        HStack(spacing: PaceSpacing.s) {
            PaceStreakFlame(isActive: streak.isActive, isTodayReached: streak.isTodayReached, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak.valueText)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(streak.caption)
                    .font(.system(.subheadline))
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func streakRecord(_ streak: DayDetailsReport.Streak) -> some View {
        HStack(alignment: .top, spacing: PaceSpacing.xs) {
            Image(systemName: "crown.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PaceColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(streak.recordText)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                Text(streak.hint)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Letzte 7 Tage

    private func recentDaysCard(_ days: [DayDetailsReport.RecentDay]) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Text(CalendarTexts.lastSevenDaysTitle)
                    .font(PaceFont.cardTitle)
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: 2) {
                    ForEach(days) { day in
                        RecentDayView(day: day)
                            .frame(maxWidth: .infinity)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
        }
    }
}

/// Große Karte: Ring mit Prozent, Schritte, Ziel des Tages, Balken, Rest bis zum Ziel.
private struct DayProgressCard: View {
    let progress: DayGoalProgress

    private let formatter = ActivityFormatter()

    var body: some View {
        PaceCard {
            HStack(alignment: .center, spacing: PaceSpacing.m) {
                PaceProgressRing(progress: progress.fraction, label: progress.percentText(formatter: formatter), lineWidth: 12)
                    .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.stepsText(formatter: formatter))
                        .font(PaceFont.metric(size: 44))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(progress.stepsUnit)
                        .font(.system(.title3, weight: .medium))
                        .foregroundStyle(PaceColor.textSecondary)
                    Text(progress.goalOnDayText(formatter: formatter))
                        .font(.system(.subheadline))
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, PaceSpacing.xxs)
                    PaceProgressBar(progress: progress.fraction, height: 10)
                    Text(progress.remainingText(formatter: formatter))
                        .font(.system(.footnote, weight: progress.isReached ? .semibold : .regular))
                        .foregroundStyle(progress.isReached ? PaceColor.accent : PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                progress.accessibilityText(formatter: formatter) + ". " + progress.goalOnDayText(formatter: formatter)
                    + ". " + progress.remainingText(formatter: formatter)
            )
        }
    }
}

/// Kachel mit Symbol, Wert und Bezeichnung – Bezeichnungen brechen um statt abgeschnitten zu werden.
private struct DayDetailsTileView: View {
    let tile: DayDetailsReport.Tile

    var body: some View {
        HStack(alignment: .center, spacing: PaceSpacing.s) {
            Image(systemName: tile.kind.systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(PaceColor.accent)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(tile.value)
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tile.isAvailable ? PaceColor.textPrimary : PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit = tile.unit {
                        Text(unit)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                    }
                }
                Text(tile.title)
                    .font(.system(.subheadline))
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.vertical, PaceSpacing.s)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .paceCardBackground(cornerRadius: PaceRadius.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
    }
}

extension DayDetailsReport.Tile.Kind {
    var systemImage: String {
        switch self {
        case .distance: "mappin.and.ellipse"
        case .activeEnergy: "flame"
        case .flights: "figure.stairs"
        case .exercise: "clock"
        case .restingHeartRate: "heart"
        case .walkingHeartRate: "waveform.path.ecg"
        }
    }
}

/// Stundenbalken mit gestrichelten Hilfslinien; beschriftet alle drei Stunden ab 6 Uhr.
private struct HourlyActivityChart: View {
    let bars: [DayDetailsReport.HourBar]

    private static let axisHours = ["06", "09", "12", "15", "18", "21"]

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("hour", Self.label(bar.hour)),
                    y: .value("steps", bar.value ?? 0)
                )
                .foregroundStyle(bar.isCurrent ? PaceColor.accentStrong : PaceColor.accent)
                .cornerRadius(2)
                .accessibilityLabel(Texts.hour(bar.hour))
                .accessibilityValue(PaceLocalization.steps(Int((bar.value ?? 0).rounded())))
                .accessibilityHidden(bar.value == nil)
            }
        }
        .chartXAxis {
            AxisMarks(values: Self.axisHours) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let steps = value.as(Double.self) {
                        Text(verbatim: Int(steps.rounded()).paceFormatted)
                    }
                }
            }
        }
    }

    /// `06`, `12`, `21`
    static func label(_ hour: Int) -> String {
        hour < 10 ? "0\(hour)" : "\(hour)"
    }
}

/// Ein Tag der letzten Woche: Ring bzw. gefüllter Kreis mit Haken, Wochentag, Wert.
private struct RecentDayView: View {
    let day: DayDetailsReport.RecentDay

    var body: some View {
        VStack(spacing: 6) {
            symbol
                .frame(width: 34, height: 34)
            Text(day.weekday)
                .font(.system(.footnote, weight: day.isSelected ? .semibold : .regular))
                .foregroundStyle(day.isSelected ? PaceColor.textPrimary : PaceColor.textSecondary)
                .lineLimit(1)
            Text(day.valueText)
                .font(.system(.caption, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
    }

    @ViewBuilder
    private var symbol: some View {
        switch day.status {
        case .reached:
            Circle()
                .fill(PaceColor.goalReachedFill)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PaceColor.onGoalReached)
                )
        case .inProgress(let fraction):
            ZStack {
                Circle().stroke(PaceColor.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(PaceColor.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(2)
        case .noData, .future:
            Circle()
                .stroke(PaceColor.track, style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
                .padding(2)
        }
    }
}
