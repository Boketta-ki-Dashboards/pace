import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Home-Dashboard: Wortmarke und Begrüßung, danach die vom Nutzer gewählten Bereiche in seiner Reihenfolge.
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

                    ForEach(viewModel.visibleSections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
            }
            .refreshable { [viewModel] in await viewModel.refresh() }
            .paceScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: StandingsTrigger(key: viewModel.standingsReloadKey, isShown: viewModel.showsStandings)) { [viewModel] in
            await viewModel.loadIfNeeded()
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
                StepGoalSheet(settings: viewModel.settings)
            case .notifications:
                NotificationsSheet()
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section {
        case .regionRanks:
            RegionRankCardsView(standings: viewModel.standings) { scope in
                viewModel.openRankings(scope)
            }
        case .stepsToday:
            StepsTodayCardView(
                state: viewModel.activity.state,
                summary: viewModel.stepsToday,
                onEditGoal: { viewModel.present(.stepGoal) },
                onRetry: { Task { await viewModel.activity.retry() } }
            ) {
                ActivityDetailsView(source: viewModel.activity)
            }
        case .week:
            WeekOverviewCardView(week: viewModel.week) {
                ActivityDetailsView(source: viewModel.activity)
            }
        case .neighborhood:
            NeighborhoodCardView(standings: viewModel.standings) { scope in
                viewModel.openRankings(scope)
            }
        case .friends:
            FriendsPreviewCardView { viewModel.openSocial() }
        case .groups:
            GroupsPreviewCardView { viewModel.openSocial() }
        }
    }
}

/// Lädt Platzierungen neu, wenn sich Gemeinde oder Teilnahme ändern oder ein Bereich sie wieder anzeigt.
private struct StandingsTrigger: Hashable {
    let key: RegionalStandingsViewModel.ReloadKey
    let isShown: Bool
}
