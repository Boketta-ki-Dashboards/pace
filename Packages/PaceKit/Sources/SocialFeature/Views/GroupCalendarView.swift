import DesignSystem
import PaceCore
import SwiftUI

/// Gruppenkalender (aus den Gruppendetails): Monatsraster, darunter die Tagesrangliste des ausgewählten Tags.
struct GroupCalendarView: View {
    let viewModel: GroupCalendarViewModel
    let onOpen: (SocialRoute) -> Void

    var body: some View {
        GroupCalendarContent(viewModel: viewModel, onOpenProfile: { onOpen(.profile($0)) })
            .socialSubpageScroll()
            .refreshable { [viewModel] in await viewModel.load(force: true) }
            .task { [viewModel] in await viewModel.load() }
    }
}

/// Inhalt des Gruppenkalenders mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct GroupCalendarContent: View {
    let viewModel: GroupCalendarViewModel
    var onOpenProfile: (SocialProfile) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: viewModel.groupName, title: SocialText.groupCalendar)
            monthBar
            switch viewModel.state {
            case .loading:
                grid
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            case .failed(let message):
                SocialFailedCard(message: message) { [viewModel] in
                    Task { await viewModel.load(force: true) }
                }
            case .unavailable(let message):
                SocialEmptyCard(systemImage: "calendar", title: SocialText.groupCalendar, message: message)
            case .loaded:
                grid
                legend
                dayCard
            }
        }
    }

    // MARK: Monat

    private var monthBar: some View {
        HStack(spacing: PaceSpacing.s) {
            HStack(spacing: 0) {
                monthButton("chevron.left", label: GroupCalendarTexts.previousMonth, enabled: viewModel.canShowPrevious) {
                    Task { await viewModel.showPrevious() }
                }
                Text(viewModel.monthTitle)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 116)
                    .accessibilityAddTraits(.isHeader)
                monthButton("chevron.right", label: GroupCalendarTexts.nextMonth, enabled: viewModel.canShowNext) {
                    Task { await viewModel.showNext() }
                }
            }
            .padding(.horizontal, PaceSpacing.xxs)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
            Spacer(minLength: 0)
            if viewModel.canShowToday {
                Button(GroupCalendarTexts.today) {
                    Task { await viewModel.showToday() }
                }
                .buttonStyle(.paceCompact)
            }
        }
    }

    private func monthButton(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(PaceColor.accent)
                .opacity(enabled ? 1 : 0.3)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Raster

    private var grid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(viewModel.weekdays.enumerated()), id: \.offset) { weekday in
                    Text(weekday.element.short)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(weekday.element.long)
                }
            }
            .padding(.bottom, PaceSpacing.xxs)
            .accessibilityHidden(true)
            ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { week in
                HStack(spacing: 6) {
                    ForEach(Array(week.element.enumerated()), id: \.offset) { column in
                        if let cell = column.element {
                            GroupCalendarCell(cell: cell, accessibilityLabel: viewModel.accessibilityLabel(for: cell)) {
                                viewModel.select(cell.day)
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: GroupCalendarCell.height)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var legend: some View {
        HStack(spacing: PaceSpacing.m) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PaceColor.goalReachedFill)
                    .frame(width: 14, height: 14)
                Text(GroupCalendarTexts.flameSecured)
            }
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(PaceColor.accent)
                Text(GroupCalendarTexts.bestOfDay)
            }
        }
        .font(.system(.caption, weight: .medium))
        .foregroundStyle(PaceColor.textSecondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Ausgewählter Tag

    @ViewBuilder
    private var dayCard: some View {
        if let title = viewModel.selectedTitle, let state = viewModel.selectedState {
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    Text(title)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let day = viewModel.selected, day.hasData || day.isToday {
                        summary(day)
                        Divider()
                        rankingList(day)
                    } else {
                        Text(viewModel.emptyText(for: state))
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
            }
        }
    }

    private func summary(_ day: GroupCalendarDay) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            HStack(spacing: PaceSpacing.xs) {
                Image(systemName: day.secured ? "flame.fill" : "flame")
                    .foregroundStyle(day.secured ? PaceColor.accent : PaceColor.textSecondary)
                    .accessibilityHidden(true)
                Text(viewModel.flameText(day))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(day.secured ? PaceColor.accent : PaceColor.textPrimary)
            }
            if let goal = viewModel.goalText(day) {
                Text(goal)
            }
            Text(viewModel.reachedText(day))
            Text(viewModel.requiredText(day))
        }
        .font(PaceFont.callout)
        .foregroundStyle(PaceColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rankingList(_ day: GroupCalendarDay) -> some View {
        if day.ranking.isEmpty {
            Text(viewModel.emptyText(for: .noData))
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
        } else {
            VStack(spacing: PaceSpacing.xxs) {
                ForEach(day.ranking) { entry in
                    rankingRow(entry, isBest: entry.id == day.best?.id)
                }
            }
        }
    }

    private func rankingRow(_ entry: GroupCalendarEntry, isBest: Bool) -> some View {
        Button {
            if !entry.isCurrentUser, let profile = entry.profile {
                onOpenProfile(profile)
            }
        } label: {
            HStack(spacing: PaceSpacing.s) {
                Text(verbatim: "\(entry.rank.paceFormatted).")
                    .font(.system(.subheadline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textSecondary)
                    .frame(minWidth: 28, alignment: .trailing)
                PaceAvatar(
                    name: entry.shownName,
                    seed: entry.profile?.publicID.uuidString ?? "hidden-\(entry.rank)",
                    size: 32,
                    image: entry.profile?.avatar
                )
                Text(entry.isCurrentUser ? GroupCalendarTexts.you(entry.shownName) : entry.shownName)
                    .italic(entry.isHidden)
                    .font(entry.isCurrentUser ? PaceFont.headline : PaceFont.body)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                if isBest {
                    Image(systemName: "trophy.fill")
                        .font(.footnote)
                        .foregroundStyle(PaceColor.accent)
                        .accessibilityLabel(GroupCalendarTexts.bestOfDay)
                }
                Spacer(minLength: PaceSpacing.xs)
                Text(PaceLocalization.steps(entry.competitionSteps))
                    .font(.system(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: entry.reached ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.reached ? PaceColor.accent : PaceColor.track)
                    .accessibilityLabel(entry.reached ? GroupCalendarTexts.goalReached : GroupCalendarTexts.goalNotReached)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, PaceSpacing.xs)
            .background(
                entry.isCurrentUser ? PaceColor.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .disabled(entry.isCurrentUser || entry.isHidden)
        .accessibilityElement(children: .combine)
    }
}

/// Ein Tag im Gruppenkalender: Tageszahl, mintgrün bei gesicherter Flamme, kleiner Pokal bei einem Tagesbesten.
/// Auswahl = Rahmen mit Abstand außen (wie im persönlichen Kalender), heute = kleiner Punkt.
struct GroupCalendarCell: View {
    static let height: CGFloat = 54
    static let cornerRadius: CGFloat = 10

    let cell: GroupCalendarViewModel.Cell
    let accessibilityLabel: String
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(verbatim: "\(cell.day.day)")
                    .font(.system(size: 16, weight: cell.state == .secured || cell.isToday ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                indicator
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: cell.state == .noData ? [3, 3] : [])))
            .overlay {
                if cell.isSelected {
                    RoundedRectangle(cornerRadius: Self.cornerRadius + 2, style: .continuous)
                        .strokeBorder(PaceColor.accent, lineWidth: 2)
                        .padding(-4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if cell.isToday {
                    Circle()
                        .fill(cell.state == .secured ? PaceColor.onGoalReached : PaceColor.accent)
                        .frame(width: 6, height: 6)
                        .padding(5)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pacePressable)
        .disabled(!cell.isSelectable)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(cell.isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var indicator: some View {
        if cell.best != nil {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(cell.state == .secured ? PaceColor.onGoalReached : PaceColor.accent)
        } else {
            Color.clear
        }
    }

    private var background: Color {
        switch cell.state {
        case .secured: PaceColor.goalReachedFill
        case .future, .beforeGroup: PaceColor.fieldBackground.opacity(0.3)
        case .open, .missed, .noData, .notLoaded: PaceColor.fieldBackground.opacity(0.6)
        }
    }

    private var borderColor: Color {
        switch cell.state {
        case .secured, .future, .beforeGroup: Color.clear
        case .open: PaceColor.accent.opacity(0.6)
        case .missed, .noData, .notLoaded: PaceColor.border
        }
    }

    private var numberColor: Color {
        switch cell.state {
        case .secured: PaceColor.onGoalReached
        case .future, .beforeGroup: PaceColor.textSecondary.opacity(0.6)
        case .open, .missed, .noData, .notLoaded: PaceColor.textPrimary
        }
    }
}

enum GroupCalendarTexts {
    static var previousMonth: String { PaceLocalization.text(de: "Vorheriger Monat", en: "Previous month", ru: "Предыдущий месяц") }
    static var nextMonth: String { PaceLocalization.text(de: "Nächster Monat", en: "Next month", ru: "Следующий месяц") }
    static var today: String { PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня") }
    static var flameSecured: String { PaceLocalization.text(de: "Flamme gesichert", en: "Flame secured", ru: "Огонь сохранён") }
    static var bestOfDay: String { PaceLocalization.text(de: "Tagesbeste", en: "Best of the day", ru: "Лучший дня") }
    static var goalReached: String { PaceLocalization.text(de: "Ziel erreicht", en: "Goal reached", ru: "Цель выполнена") }
    static var goalNotReached: String { PaceLocalization.text(de: "Ziel nicht erreicht", en: "Goal not reached", ru: "Цель не выполнена") }
    static func you(_ name: String) -> String {
        PaceLocalization.text(de: "\(name) (du)", en: "\(name) (you)", ru: "\(name) (ты)")
    }
}
