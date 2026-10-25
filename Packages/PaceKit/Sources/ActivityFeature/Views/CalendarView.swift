import DesignSystem
import PaceCore
import SwiftUI

/// Monatskalender (Referenzbild 9): Kopf „‹ Home · pace · Kalender“, Monatsnavigation mit Legende, Raster Mo–So und
/// die Karte des ausgewählten Tages. Tippen auf die Karte (oder erneut auf den ausgewählten Tag) öffnet die
/// Tagesdetails.
public struct CalendarView: View {
    @State private var viewModel: CalendarViewModel
    @State private var detailsDay: LocalDate?

    /// Das ViewModel wird beim ersten Erscheinen übernommen (wie bei `@State` üblich).
    public init(viewModel: CalendarViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            CalendarContent(
                content: viewModel.content,
                monthTitle: viewModel.monthTitle,
                canShowPrevious: viewModel.canShowPrevious,
                canShowNext: viewModel.canShowNext,
                onPrevious: { viewModel.showPrevious() },
                onNext: { viewModel.showNext() },
                onSelect: { day in
                    if day.isSelected {
                        detailsDay = day.date
                    } else {
                        viewModel.select(day.date)
                    }
                },
                onOpenDetails: { date in detailsDay = date },
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
        .onChange(of: viewModel.streak.record) { viewModel.streak.saveRecordIfNeeded() }
        .navigationDestination(item: $detailsDay) { day in
            DayDetailsView(viewModel: viewModel.dayDetails(for: day))
        }
    }
}

/// Reine Darstellung des Kalenders inklusive Kopf (ohne Navigation und Scrollen) – auch für Snapshots.
struct CalendarContent: View {
    let content: CalendarViewModel.Content
    let monthTitle: String
    let canShowPrevious: Bool
    let canShowNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelect: (CalendarDay) -> Void
    let onOpenDetails: (LocalDate) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.m) {
            PaceSubpageHeader(backTitle: CalendarTexts.home, title: CalendarTexts.title)

            monthBar

            switch content {
            case .loading:
                PaceCard {
                    PaceLoadingView(CalendarTexts.loading)
                        .frame(minHeight: 260)
                }
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
                    PaceStatusView(
                        systemImage: "arrow.clockwise",
                        title: CalendarTexts.failedTitle,
                        message: message
                    ) {
                        Button(CalendarTexts.retry, action: onRetry)
                            .buttonStyle(.pacePrimary)
                    }
                }
            case .month(let month):
                CalendarGrid(month: month, onSelect: onSelect, onPrevious: onPrevious, onNext: onNext)
                if let card = month.selectedCard {
                    CalendarDayCardView(card: card) {
                        onOpenDetails(card.date)
                    }
                }
                if !month.bests.isEmpty {
                    PersonalBestsCard(bests: month.bests)
                }
            }
        }
    }

    // MARK: Monatsnavigation und Legende

    private var monthBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaceSpacing.s) {
                monthNavigator
                Spacer(minLength: PaceSpacing.xs)
                legend
            }
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                monthNavigator
                legend
            }
        }
    }

    private var monthNavigator: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(PaceColor.accent)
                    .opacity(canShowPrevious ? 1 : 0.3)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canShowPrevious)
            .accessibilityLabel(CalendarTexts.previousMonth)

            Text(monthTitle)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 116)
                .accessibilityAddTraits(.isHeader)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(PaceColor.accent)
                    .opacity(canShowNext ? 1 : 0.3)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canShowNext)
            .accessibilityLabel(CalendarTexts.nextMonth)
        }
        .padding(.horizontal, PaceSpacing.xxs)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                .strokeBorder(PaceColor.border, lineWidth: 1)
        )
    }

    private var legend: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(PaceColor.goalReachedFill)
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(PaceColor.accent.opacity(0.5), lineWidth: 1)
                )
                .accessibilityHidden(true)
            // Klein wie in Bild 9, damit die Legende neben der Monatsnavigation Platz hat.
            Text(CalendarTexts.goalReached)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(PaceColor.accent)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Wochentage und Tagesfelder. Wischen blättert den Monat (Finger nach rechts = vorheriger, nach links = nächster).
private struct CalendarGrid: View {
    let month: CalendarMonth
    let onSelect: (CalendarDay) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    private let spacing: CGFloat = 6

    var body: some View {
        let weeks = month.weeks
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(month.weekdays) { weekday in
                    Text(weekday.title)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, PaceSpacing.xxs)
            .accessibilityHidden(true)

            ForEach(weeks.indices, id: \.self) { index in
                HStack(spacing: spacing) {
                    ForEach(weeks[index].indices, id: \.self) { column in
                        if let day = weeks[index][column] {
                            CalendarDayCell(day: day) {
                                onSelect(day)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: CalendarDayCell.cornerRadius, style: .continuous)
                                .fill(PaceColor.fieldBackground.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .frame(height: CalendarDayCell.height)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .pacePeriodSwipe(
            canShowPrevious: month.canShowPrevious,
            canShowNext: month.canShowNext,
            onPrevious: onPrevious,
            onNext: onNext
        )
    }
}

/// Ein Tagesfeld: Ring mit Tageszahl und Schritten (nicht erreicht), volle grüne Fläche (erreicht), neutral (Zukunft),
/// gestrichelter Ring (keine Daten). Heute = kleiner Punkt.
///
/// Die Auswahl ist ein eigener Zustand: ein Akzentrahmen mit Abstand außen um das Feld. Er verändert das Feld selbst
/// nicht – ein ausgewählter Tag sieht also nie wie „Ziel erreicht“ aus – und bleibt durch den Abstand auch um ein
/// mintgrün gefülltes Feld und im Dark Mode klar sichtbar.
private struct CalendarDayCell: View {
    static let height: CGFloat = 60
    static let cornerRadius: CGFloat = 10
    /// Abstand und Strichstärke des Auswahlrahmens (zusammen kleiner als der Rasterabstand von 6 pt).
    static let selectionGap: CGFloat = 2
    static let selectionLineWidth: CGFloat = 2

    let day: CalendarDay
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Button(action: onTap) {
            VStack(spacing: 3) {
                number
                Text(day.stepsText)
                    .font(.system(size: 10.5, weight: day.status == .reached ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(stepsColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
            .overlay {
                if day.isSelected {
                    RoundedRectangle(cornerRadius: Self.cornerRadius + Self.selectionGap, style: .continuous)
                        .strokeBorder(PaceColor.accent, lineWidth: Self.selectionLineWidth)
                        .padding(-(Self.selectionGap + Self.selectionLineWidth))
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if day.isToday {
                    Circle()
                        .fill(day.status == .reached ? PaceColor.onGoalReached : PaceColor.accent)
                        .frame(width: 6, height: 6)
                        .padding(5)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pacePressable)
        .disabled(!day.isSelectable)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityHint(day.isSelected ? CalendarTexts.openDetailsHint : "")
        .accessibilityAddTraits(day.isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var number: some View {
        switch day.status {
        case .reached:
            Text(day.dayText)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.onGoalReached)
                .frame(height: 30)
        case .inProgress(let fraction):
            ring(fraction: fraction, dashed: false)
        case .noData:
            ring(fraction: 0, dashed: true)
        case .future:
            ring(fraction: 0, dashed: false)
        }
    }

    private func ring(fraction: Double, dashed: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(PaceColor.track, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [2, 3] : []))
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(PaceColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(day.dayText)
                .font(.system(size: 14, weight: day.isToday ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(day.status == .future ? PaceColor.textSecondary : PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 30, height: 30)
    }

    private var background: Color {
        day.status == .reached ? PaceColor.goalReachedFill : PaceColor.fieldBackground.opacity(0.6)
    }

    private var borderColor: Color {
        day.status == .reached ? Color.clear : PaceColor.border
    }

    private var stepsColor: Color {
        switch day.status {
        case .reached: PaceColor.onGoalReached
        case .inProgress: PaceColor.textPrimary
        case .noData, .future: PaceColor.textSecondary
        }
    }
}

/// Karte des ausgewählten Tages unter dem Raster; antippbar → Tagesdetails.
private struct CalendarDayCardView: View {
    let card: CalendarMonth.DayCard
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .top, spacing: PaceSpacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let steps = card.stepsText {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(steps)
                                    .font(PaceFont.metric(size: 40))
                                    .monospacedDigit()
                                    .foregroundStyle(PaceColor.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(card.stepsUnit)
                                    .font(.system(.title3, weight: .semibold))
                                    .foregroundStyle(PaceColor.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        Text(card.goalText)
                            .font(.system(.subheadline))
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    if card.stepsText != nil {
                        PaceProgressRing(progress: card.fraction, label: card.percentText, lineWidth: 9)
                            .frame(width: 92, height: 92)
                    }
                }
                if card.stepsText != nil {
                    PaceProgressBar(progress: card.fraction, height: 10)
                }
                Text(card.detailText)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(card.isReached ? PaceColor.accent : PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PaceSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground()
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityHint(CalendarTexts.openDetailsHint)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            CalendarContent(
                content: .loading,
                monthTitle: "Oktober 2026",
                canShowPrevious: true,
                canShowNext: false,
                onPrevious: {},
                onNext: {},
                onSelect: { _ in },
                onOpenDetails: { _ in },
                onRetry: {}
            )
            .padding(.horizontal, PaceSpacing.m)
        }
        .paceScreenBackground()
    }
}

/// „Deine Bestwerte“ unter den Tagesdetails: bester Tag der Woche und des Monats, bester Tag insgesamt, längste Serie.
/// Ist der ausgewählte Tag selbst ein Bestwert, ist er hervorgehoben.
struct PersonalBestsCard: View {
    let bests: [PersonalBest]

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                PaceCardHeader(PaceLocalization.text(de: "Deine Bestwerte", en: "Your bests", ru: "Твои рекорды"))
                ForEach(bests) { best in
                    HStack(spacing: PaceSpacing.s) {
                        Image(systemName: best.kind == .longestStreak ? "flame.fill" : "trophy.fill")
                            .foregroundStyle(best.kind == .longestStreak ? PaceColor.streak : PaceColor.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(best.title)
                                .font(PaceFont.callout)
                                .foregroundStyle(PaceColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = best.detail {
                                Text(best.isThisDay
                                    ? detail + " · " + PaceLocalization.text(de: "dieser Tag", en: "this day", ru: "этот день")
                                    : detail)
                                    .font(PaceFont.caption.weight(best.isThisDay ? .semibold : .regular))
                                    .foregroundStyle(best.isThisDay ? PaceColor.accentStrong : PaceColor.textSecondary)
                            }
                        }
                        Spacer(minLength: PaceSpacing.xs)
                        Text(best.value)
                            .font(PaceFont.headline)
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(minHeight: 40)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
