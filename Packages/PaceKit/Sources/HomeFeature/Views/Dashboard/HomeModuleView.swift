import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Ein Widget auf Home – mit Kopf, Inhalt in seiner Größe und Kartenhintergrund.
///
/// Im Anpassen-Modus ersetzt ein eigener Kopf („Größe auswählen“, Ziehgriff) die normalen Aktionen; der Inhalt ist
/// dann nicht antippbar, Antippen öffnet stattdessen die Galerie zum Bearbeiten. In der Galerie-Vorschau sieht das
/// Widget aus wie auf Home, reagiert aber nicht.
struct HomeModuleView: View {
    let module: HomeModule
    let viewModel: HomeDashboardViewModel
    let mode: HomeWidgetMode
    /// Anpassen-Modus: Antippen des Inhalts (Bearbeiten in der Galerie).
    var onEdit: () -> Void = {}

    var body: some View {
        if isBare {
            content
                .allowsHitTesting(mode.isInteractive)
        } else {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                if mode == .editing {
                    HomeEditHeader(title: title, module: module, viewModel: viewModel)
                } else if showsHeader {
                    header
                }
                if mode == .editing {
                    content
                        .allowsHitTesting(false)
                        .overlay {
                            Button(action: onEdit) {
                                Color.clear.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(HomeTexts.editWidget + ": " + title)
                        }
                } else {
                    content
                        .allowsHitTesting(mode.isInteractive)
                }
            }
            .padding(PaceSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground()
        }
    }

    private var title: String {
        viewModel.title(for: module)
    }

    /// Ohne Ranking-Sichtbarkeit zeigen Ranking-Widgets einen gesperrten Zustand ohne echte Werte.
    private var isLocked: Bool {
        module.kind.showsRegionalRankings && !viewModel.isRankingVisible
    }

    /// Die vier Karten stehen im normalen Home-Design ohne eigene Karte und ohne Überschrift.
    private var isBare: Bool {
        module.kind == .regionRanks && module.size <= .medium && mode != .editing
    }

    /// Kleine Widgets kommen ohne Kopfzeile aus, wenn ihr Inhalt für sich spricht.
    private var showsHeader: Bool {
        switch module.kind {
        case .regionRanks, .neighborhood, .friends, .groups, .stepsToday,
             .dayComparison, .streakWeek, .records, .activityTimes, .groupProgress:
            true
        case .week, .streak, .activity, .calendar:
            module.size != .small
        }
    }

    // MARK: Kopf

    @ViewBuilder
    private var header: some View {
        switch module.kind {
        case .stepsToday:
            HomeWidgetTitleRow(title) {
                Button {
                    viewModel.present(.stepGoal)
                } label: {
                    Label(HomeTexts.dailyGoalChange, systemImage: "scope")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.pacePressable)
                .allowsHitTesting(mode.isInteractive)
                .fixedSize()
            }
        case .week:
            NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .week, metric: .steps))) {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
            .accessibilityLabel(viewModel.week?.accessibilitySummary ?? title)
            .accessibilityHint(PaceLocalization.text(
                de: "Öffnet die Wochenstatistik", en: "Opens the weekly statistics", ru: "Открывает статистику за неделю"
            ))
        case .streak:
            // Persönliche Flamme → eigene Flammen-Seite (nie Gruppe oder Chat).
            NavigationLink(value: HomeRoute.streak) {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .neighborhood:
            Button {
                viewModel.openRankings(neighborhoodRegion)
            } label: {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .friends, .groups:
            Button {
                viewModel.openSocial()
            } label: {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .calendar:
            NavigationLink(value: HomeRoute.calendar(CalendarRoute())) {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .regionRanks, .activity:
            HomeWidgetTitleRow(title)
        case .dayComparison, .activityTimes:
            // Tippen → Tagesstatistik der Schritte.
            NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .day, metric: .steps))) {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .streakWeek:
            NavigationLink(value: HomeRoute.streak) {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .records:
            NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .month, metric: .steps))) {
                HomeWidgetTitleRow(title) { HomeChevron() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .allowsHitTesting(mode.isInteractive)
        case .groupProgress:
            if case .group(let group, _) = viewModel.groupProgressWidget(for: module) {
                Button {
                    viewModel.openGroup(group.id)
                } label: {
                    HomeWidgetTitleRow(title) { HomeChevron() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .allowsHitTesting(mode.isInteractive)
            } else {
                HomeWidgetTitleRow(title)
            }
        }
    }

    private var neighborhoodRegion: Region? {
        let level = viewModel.standings.effectiveLevel(for: module.regionLevel ?? .municipality)
        return viewModel.standings.scopes.first { $0.level == level }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        if isLocked {
            lockedContent
        } else {
            switch module.kind {
            case .regionRanks:
                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    RegionRanksWidgetContent(
                        cards: viewModel.regionCards(for: module),
                        size: module.size,
                        isLoading: viewModel.standings.isLoading,
                        isInteractive: mode.isInteractive,
                        onSelect: { region in viewModel.openRankings(region) }
                    )
                    if case .failed(let message) = viewModel.standings.state {
                        HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
                    }
                    // Im Anpassen-Modus sichtbar machen, warum weniger als vier Karten erscheinen.
                    if mode == .editing, module.regionLevels.count < RegionLevel.allCases.count {
                        HomeWidgetHint(
                            systemImage: "eye.slash",
                            text: HomeTexts.visibleLevels(module.regionLevels.count, of: RegionLevel.allCases.count)
                        )
                    }
                }
            case .stepsToday:
                StepsTodayWidgetContent(
                    state: viewModel.activity.state,
                    summary: viewModel.stepsToday,
                    size: module.size,
                    details: module.shownDetails,
                    dayBest: module.shows(.dayBest) ? viewModel.dayBest : nil,
                    onRetry: { Task { await viewModel.activity.retry() } }
                )
            case .week:
                WeekWidgetContent(week: viewModel.week, size: module.size, unavailableText: viewModel.weekUnavailableText)
            case .streak:
                NavigationLink(value: HomeRoute.streak) {
                    StreakWidgetContent(
                        widget: viewModel.streakWidget,
                        state: viewModel.streak.history.state,
                        size: module.size,
                        details: module.shownDetails
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityHint(PaceLocalization.text(
                    de: "Öffnet deine Flamme mit Kalender", en: "Opens your flame with calendar", ru: "Открывает твою серию с календарём"
                ))
            case .neighborhood:
                NeighborhoodWidgetContent(
                    standings: viewModel.standings,
                    level: module.regionLevel ?? .municipality,
                    size: module.size,
                    rows: module.neighborhoodRows,
                    showsGap: module.shows(.rankGap),
                    onOpenRankings: { region in viewModel.openRankings(region) }
                )
            case .friends:
                FriendsWidgetContent(
                    widget: viewModel.friendsWidget(for: module),
                    state: viewModel.social.state,
                    size: module.size,
                    details: module.shownDetails,
                    onOpenSocial: { viewModel.openSocial() }
                )
            case .groups:
                GroupsWidgetContent(
                    selection: viewModel.groupSelection(for: module),
                    state: viewModel.social.state,
                    size: module.size,
                    details: module.shownDetails,
                    onOpenGroup: { id in viewModel.openGroup(id) },
                    onOpenSocial: { viewModel.openSocial() }
                )
            case .activity:
                ActivityWidgetContent(
                    widget: viewModel.activityWidget(for: module),
                    size: module.size,
                    unavailableText: viewModel.weekUnavailableText
                )
            case .calendar:
                CalendarWidgetContent(
                    widget: viewModel.calendarWidget(size: module.size),
                    size: module.size,
                    isLoading: viewModel.isHistoryLoading
                )
            case .dayComparison:
                NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .day, metric: .steps))) {
                    DayComparisonWidgetContent(
                        widget: viewModel.dayComparisonWidget,
                        size: module.size,
                        details: module.shownDetails,
                        unavailableText: viewModel.hourlyUnavailableText
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
            case .streakWeek:
                NavigationLink(value: HomeRoute.streak) {
                    StreakWeekWidgetContent(
                        widget: viewModel.streakWidget,
                        state: viewModel.streak.history.state,
                        size: module.size,
                        details: module.shownDetails
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
            case .records:
                NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .month, metric: .steps))) {
                    RecordsWidgetContent(
                        widget: viewModel.recordsWidget(for: module),
                        state: viewModel.streak.history.state,
                        size: module.size
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
            case .activityTimes:
                NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .day, metric: .steps))) {
                    ActivityTimesWidgetContent(
                        widget: viewModel.activityTimesWidget,
                        size: module.size,
                        unavailableText: viewModel.hourlyUnavailableText
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
            case .groupProgress:
                GroupProgressWidgetContent(
                    widget: viewModel.groupProgressWidget(for: module),
                    size: module.size,
                    details: module.shownDetails,
                    onOpenGroup: { id in viewModel.openGroup(id) },
                    onOpenCalendar: { id in viewModel.openGroupCalendar(id) }
                )
            }
        }
    }

    /// „Ranking ausgeschaltet“: die Grundform bleibt erkennbar, darüber liegt eine dezente Unschärfe. Der Platzhalter
    /// enthält keine echten Werte – es werden dafür auch keine geladen.
    @ViewBuilder
    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            PaceLockedCard(
                systemImage: "eye.slash",
                title: HomeTexts.rankingOffTitle,
                message: HomeTexts.rankingOffMessage,
                actionTitle: mode.isInteractive && !viewModel.standings.isUpdatingParticipation ? HomeTexts.enableRankingVisibility : nil,
                action: { viewModel.requestRankingVisibility() }
            ) {
                if module.kind == .regionRanks {
                    RegionRanksPlaceholder(levels: module.regionLevels)
                } else {
                    NeighborhoodPlaceholder(rows: min(module.neighborhoodRows, 3))
                }
            }
            if viewModel.standings.isUpdatingParticipation {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if mode.isInteractive, let error = viewModel.standings.participationError {
                Text(error)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Kopf eines Widgets im Anpassen-Modus: Titel, „Größe auswählen“ und Ziehgriff. Für VoiceOver trägt der Titel die
/// Aktionen (verschieben, Größe, entfernen) als Alternative zum Ziehen.
struct HomeEditHeader: View {
    let title: String
    let module: HomeModule
    let viewModel: HomeDashboardViewModel

    var body: some View {
        HStack(alignment: .center, spacing: PaceSpacing.xs) {
            Text(title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, module.kind.isRemovable ? 20 : 0)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(HomeTexts.size(module.size))
                .accessibilityActions {
                    if viewModel.settings.canMoveUp(module.id) {
                        Button(HomeTexts.moveUp) { viewModel.moveUp(module.id) }
                    }
                    if viewModel.settings.canMoveDown(module.id) {
                        Button(HomeTexts.moveDown) { viewModel.moveDown(module.id) }
                    }
                    ForEach(module.kind.supportedSizes) { size in
                        Button(HomeTexts.size(size)) { viewModel.setSize(size, for: module.id) }
                    }
                    if module.kind.isRemovable {
                        Button(HomeTexts.remove(title)) { viewModel.remove(module.id) }
                    }
                }
            Spacer(minLength: PaceSpacing.xxs)
            Button {
                viewModel.toggleSizeMenu(for: module.id)
            } label: {
                HStack(spacing: 6) {
                    HomeSizeGlyph()
                    Text(HomeTexts.chooseSize)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(PaceColor.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(HomeTexts.chooseSize)
            .accessibilityValue(module.size.title)
            HomeReorderHandle(module: module, viewModel: viewModel)
        }
    }
}

/// Ziehgriff eines Widgets im Anpassen-Modus: Berühren und Ziehen verschiebt das Widget (Finger-genau, mit
/// Auto-Scroll am Rand). Die Geste hat Vorrang vor dem Scrollen, damit die Liste beim Ziehen am Griff stillsteht.
///
/// Bricht das System die Geste ab (dann kommt kein `onEnded`), endet das Ziehen über den Gesten-Zustand trotzdem –
/// sonst liefe das automatische Scrollen weiter.
struct HomeReorderHandle: View {
    let module: HomeModule
    let viewModel: HomeDashboardViewModel

    @Environment(HomeReorderController.self) private var reorder: HomeReorderController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isTouching = false

    var body: some View {
        HomeDragHandle(color: viewModel.draggingModuleID == module.id ? PaceColor.accent : PaceColor.textSecondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isTouching) { _, state, _ in state = true }
                    .onChanged { [reorder, viewModel, id = module.id] value in
                        reorder?.drag(id, toGlobalY: value.location.y, dashboard: viewModel)
                    }
                    .onEnded { _ in endDrag() }
            )
            .onChange(of: isTouching) { _, touching in
                if !touching { endDrag() }
            }
            .onDisappear {
                if reorder?.draggingID == module.id { reorder?.endDrag(animated: false) }
            }
            .accessibilityHidden(true)
    }

    /// Ende über den Zustand des Controllers (nicht des Dashboards) – so kann kein Ziehen hängen bleiben.
    private func endDrag() {
        guard let reorder, reorder.draggingID == module.id else { return }
        reorder.endDrag(animated: !reduceMotion)
    }
}
