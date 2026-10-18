import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Home-Dashboard: Wortmarke und Begrüßung, danach die vom Nutzer gewählten Module in seiner Reihenfolge und Größe.
///
/// Die Aktualisierungs-Auslöser für Bewegungsdaten hängen an der ganzen Main App (`activityUpdates(_:)`), damit sie
/// auch laufen, während ein anderer Tab offen ist.
public struct HomeView: View {
    @Bindable private var viewModel: HomeDashboardViewModel

    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: HomeDashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    HomeHeaderView(
                        greeting: viewModel.greeting,
                        onCustomize: { viewModel.present(.customize) },
                        onNotifications: { viewModel.present(.notifications) }
                    )
                    .padding(.bottom, PaceSpacing.xxs)

                    ForEach(viewModel.modules) { module in
                        moduleView(module)
                    }
                }
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
            }
            .refreshable { [viewModel] in await viewModel.refresh() }
            .paceScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: StatisticsRoute.self) { route in
                StatisticsView(viewModel: viewModel.statistics(for: route))
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
        .onChange(of: viewModel.streak.record) {
            viewModel.streak.saveRecordIfNeeded()
        }
        .onChange(of: viewModel.stepsToday?.steps) {
            Task { await viewModel.stepsDidChange() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Zurück in der App: Schritte lesen, dann Platzierungen auffrischen, falls älter als eine Minute.
            guard newPhase == .active else { return }
            Task { await viewModel.returnedToForeground() }
        }
        .sheet(item: $viewModel.presentedSheet) { sheet in
            switch sheet {
            case .customize:
                HomeCustomizeSheet(settings: viewModel.settings)
            case .stepGoal:
                StepGoalSheet(goals: viewModel.goals)
            case .notifications:
                NotificationsSheet()
            }
        }
    }

    @ViewBuilder
    private func moduleView(_ module: HomeModule) -> some View {
        switch module.kind {
        case .regionRanks:
            RegionRankCardsView(standings: viewModel.standings, size: module.size) { scope in
                viewModel.openRankings(scope)
            }
        case .stepsToday:
            StepsTodayCardView(
                state: viewModel.activity.state,
                summary: viewModel.stepsToday,
                size: module.size,
                onEditGoal: { viewModel.present(.stepGoal) },
                onRetry: { Task { await viewModel.activity.retry() } }
            )
        case .week:
            WeekOverviewCardView(week: viewModel.week, size: module.size)
        case .streak:
            StreakCardView(summary: viewModel.streakSummary, state: viewModel.streak.history.state, size: module.size)
        case .neighborhood:
            NeighborhoodCardView(
                standings: viewModel.standings,
                level: module.regionLevel ?? .municipality,
                size: module.size
            ) { scope in
                viewModel.openRankings(scope)
            }
        case .friends:
            FriendsPreviewCardView(social: viewModel.social, size: module.size) { viewModel.openSocial() }
        case .groups:
            GroupsPreviewCardView(social: viewModel.social, size: module.size) { viewModel.openSocial() }
        }
    }
}
