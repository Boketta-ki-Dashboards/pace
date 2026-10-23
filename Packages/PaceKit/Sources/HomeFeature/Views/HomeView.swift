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
    @State private var path = NavigationPath()
    @State private var reorder = HomeReorderController()

    public init(viewModel: HomeDashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                HomeDashboardContent(
                    viewModel: viewModel,
                    onAddWidget: { path.append(HomeWidgetGalleryRoute()) },
                    onEditModule: { id in path.append(HomeWidgetGalleryRoute(editingID: id)) }
                )
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
                .paceTabRoot(isAtRoot: path.isEmpty) { path = NavigationPath() }
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
            .navigationDestination(for: StatisticsRoute.self) { route in
                StatisticsView(viewModel: viewModel.statistics(for: route), backTitle: HomeTexts.home)
            }
            .navigationDestination(for: CalendarRoute.self) { route in
                HomeCalendarScreen(viewModel: viewModel.calendar(for: route))
            }
            .navigationDestination(for: HomeWidgetGalleryRoute.self) { route in
                HomeWidgetGalleryScreen(dashboard: viewModel, route: route)
            }
            .navigationDestination(for: HomeNotificationsRoute.self) { _ in
                HomeNotificationsScreen(viewModel: viewModel) { notification in
                    path = NavigationPath()
                    viewModel.open(notification)
                }
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
        .task { [viewModel] in
            await viewModel.loadNotificationsIfNeeded()
        }
        .onChange(of: viewModel.isEditing) { _, isEditing in
            if !isEditing { reorder.endDrag() }
        }
        .onChange(of: viewModel.streak.record) {
            viewModel.streak.saveRecordIfNeeded()
        }
        .onChange(of: viewModel.healthKitStepsToday) {
            Task { await viewModel.stepsDidChange() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Zurück in der App: Schritte lesen, dann Platzierungen auffrischen, falls älter als eine Minute.
            guard newPhase == .active else { return }
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

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HomeHeaderView(viewModel: viewModel, onAddWidget: onAddWidget)
                .padding(.bottom, PaceSpacing.xxs)

            ForEach(viewModel.modules) { module in
                HomeEditableModule(module: module, viewModel: viewModel, onEdit: onEditModule)
                    .zIndex(viewModel.draggingModuleID == module.id ? 2 : viewModel.sizeMenuModuleID == module.id ? 1 : 0)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: viewModel.modules.map(\.id))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.isEditing)
        .sensoryFeedback(.selection, trigger: viewModel.modules.map(\.id))
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
