import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Home-Dashboard: Wortmarke und Begrüßung, danach die Widgets des Nutzers in seiner Reihenfolge und Größe.
///
/// „Anpassen“ schaltet Home direkt in den Anpassen-Modus (kein eigenes Sheet); neue Widgets kommen über die
/// Widget-Galerie hinzu. Die Aktualisierungs-Auslöser für Bewegungsdaten hängen an der ganzen Main App
/// (`activityUpdates(_:)`), damit sie auch laufen, während ein anderer Tab offen ist.
public struct HomeView: View {
    @Bindable private var viewModel: HomeDashboardViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [HomeRoute] = []
    @State private var reorder = HomeReorderController()

    public init(viewModel: HomeDashboardViewModel) {
        self.viewModel = viewModel
    }

    private func open(_ route: HomeRoute) {
        let opened = PaceNavigationRules.opening(route, in: path)
        if opened != path { path = opened }
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                HomeDashboardContent(
                    viewModel: viewModel,
                    onAddWidget: { open(.gallery(HomeWidgetGalleryRoute())) },
                    onEditModule: { id in open(.gallery(HomeWidgetGalleryRoute(editingID: id))) }
                )
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
                .paceTabRoot(isAtRoot: path.isEmpty) { path = [] }
                // Bezugssystem für das Umsortieren: Rahmen der Widgets im Inhalt, Inhaltsoberkante global.
                .coordinateSpace(.named(HomeReorderController.contentSpace))
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minY
                } action: { [reorder] minY in
                    reorder.reportContentMinY(minY)
                }
                .background {
                    HomeScrollViewFinder { [reorder] scrollView in
                        reorder.attach(scrollView)
                    }
                    .accessibilityHidden(true)
                }
            }
            .scrollIndicators(.hidden)
            // Nur senkrecht: kein waagerechtes Nachfedern (zusätzlich zur Sperre im Inhalt, ``paceTabRoot``).
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // Während ein Widget am Griff gezogen wird, scrollt nur noch das automatische Scrollen am Rand.
            .scrollDisabled(reorder.isDragging)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { [reorder] frame in
                reorder.reportViewport(frame)
            }
            .refreshable { [viewModel] in await viewModel.refresh() }
            .environment(reorder)
            .paceScreenBackground()
            .paceRootPage()
            .overlay(alignment: .bottom) {
                undoBanner
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .statistics(let route):
                    StatisticsView(viewModel: viewModel.statistics(for: route), backTitle: HomeTexts.home)
                case .calendar(let route):
                    HomeCalendarScreen(viewModel: viewModel.calendar(for: route))
                case .gallery(let route):
                    HomeWidgetGalleryScreen(dashboard: viewModel, route: route)
                case .notifications:
                    HomeNotificationsScreen(viewModel: viewModel) { notification in
                        // Systemmitteilungen öffnen ihre eigene Seite; alles andere führt in den Social-Tab.
                        if case .system(let message) = notification.kind {
                            viewModel.open(notification)
                            open(.systemMessage(message.kind))
                        } else {
                            path = []
                            viewModel.open(notification)
                        }
                    }
                case .systemMessage:
                    WelcomeMessageScreen(viewModel: viewModel) { path = [] }
                case .streak:
                    StreakDetailView(viewModel: viewModel.streakDetail(), backTitle: HomeTexts.home)
                }
            }
        }
        // Dieselbe Seite nie doppelt (z. B. schnelles Doppeltippen auf ein Widget): zurück zur vorhandenen.
        .onChange(of: path) { _, newPath in
            let deduplicated = newPath.reduce(into: [HomeRoute]()) { result, route in
                result = PaceNavigationRules.opening(route, in: result)
            }
            if deduplicated != newPath {
                path = deduplicated
            }
        }
        .task(id: viewModel.standingsReloadKey) { [viewModel] in
            await viewModel.loadIfNeeded()
        }
        .task(id: viewModel.showsStreak) { [viewModel] in
            await viewModel.loadStreakIfNeeded()
        }
        .task(id: viewModel.showsSocial) { [viewModel] in
            await viewModel.loadSocialIfNeeded()
        }
        // Tagesvergleich und Aktivitätszeiten: Stundenwerte nur bei neuem Tag oder neuem HealthKit-Stand.
        .task(id: viewModel.hourlyReloadKey) { [viewModel] in
            await viewModel.loadHourlyIfNeeded()
        }
        .task { [viewModel] in
            await viewModel.loadNotificationsIfNeeded()
        }
        .onChange(of: viewModel.isEditing) { _, isEditing in
            if !isEditing { reorder.endDrag() }
        }
        // Seite verlassen (z. B. Galerie geöffnet) oder App verlassen: kein Ziehen und kein Auto-Scroll bleibt übrig.
        .onDisappear { [reorder] in reorder.endDrag(animated: false) }
        .onChange(of: viewModel.streak.record) {
            viewModel.streak.saveRecordIfNeeded()
        }
        .onChange(of: viewModel.healthKitStepsToday) {
            Task { await viewModel.stepsDidChange() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                reorder.endDrag(animated: false)
                return
            }
            // Zurück in der App: Schritte lesen, dann Platzierungen auffrischen, falls älter als eine Minute.
            Task {
                await viewModel.returnedToForeground()
                await viewModel.loadNotificationsIfNeeded()
            }
        }
        .sheet(item: $viewModel.presentedSheet) { sheet in
            switch sheet {
            case .stepGoal:
                StepGoalSheet(goals: viewModel.goals)
            }
        }
        .confirmationDialog(
            HomeTexts.enableRankingVisibility,
            isPresented: $viewModel.isConfirmingRankingVisibility,
            titleVisibility: .visible
        ) {
            Button(HomeTexts.enableRankingVisibility) {
                Task { await viewModel.enableRankingVisibility() }
            }
            Button(HomeTexts.cancel, role: .cancel) {}
        } message: {
            Text(HomeTexts.enableRankingVisibilityMessage)
        }
    }

    /// „„Deine Woche“ entfernt · Rückgängig“ – einige Sekunden nach dem Entfernen eines Widgets.
    @ViewBuilder
    private var undoBanner: some View {
        if let removed = viewModel.lastRemoved {
            HStack(spacing: PaceSpacing.s) {
                Text(HomeTexts.removed(removed.module.title))
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: PaceSpacing.xs)
                Button(HomeTexts.undo) {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        viewModel.undoRemove()
                    }
                }
                .font(.system(.callout, weight: .semibold))
                .buttonStyle(.paceSoft)
            }
            .padding(.leading, PaceSpacing.m)
            .padding(.trailing, PaceSpacing.xs)
            .padding(.vertical, PaceSpacing.xs)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.s)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: removed.module.id) { [viewModel] in
                await viewModel.expireUndo(for: removed, after: .seconds(6))
            }
        }
    }
}

/// Inhalt von Home ohne Navigation und Scrollen (auch für Snapshot-Tests): Kopf und Widgets.
struct HomeDashboardContent: View {
    let viewModel: HomeDashboardViewModel
    var onAddWidget: () -> Void = {}
    var onEditModule: (HomeModule.ID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HomeReorderController.self) private var reorder: HomeReorderController?

    /// Gezogen oder gerade abgelegt: liegt über den anderen Widgets.
    private func isLifted(_ module: HomeModule) -> Bool {
        viewModel.draggingModuleID == module.id || reorder?.settlingID == module.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HomeHeaderView(viewModel: viewModel, onAddWidget: onAddWidget)
                .padding(.bottom, PaceSpacing.xxs)

            ForEach(viewModel.modules) { module in
                HomeEditableModule(module: module, viewModel: viewModel, onEdit: onEditModule)
                    .zIndex(isLifted(module) ? 2 : viewModel.sizeMenuModuleID == module.id ? 1 : 0)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: viewModel.modules.map(\.id))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.isEditing)
        .sensoryFeedback(.selection, trigger: viewModel.modules.map(\.id))
        // Beim Ziehen: kurzes Feedback, wenn das Widget einen neuen Platz erreicht.
        .sensoryFeedback(.selection, trigger: reorder?.targetIndex) { old, new in old != nil && new != nil }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.draggingModuleID) { _, newValue in newValue != nil }
    }
}

/// Kalender mit stabilem ViewModel (entsteht einmal pro Aufruf der Seite).
private struct HomeCalendarScreen: View {
    @State private var viewModel: CalendarViewModel

    init(viewModel: @autoclosure () -> CalendarViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    var body: some View {
        CalendarView(viewModel: viewModel)
    }
}
