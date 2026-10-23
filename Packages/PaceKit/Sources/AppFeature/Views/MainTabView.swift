import DesignSystem
import HomeFeature
import LeaderboardFeature
import PaceCore
import ProfileFeature
import SocialFeature
import SwiftUI

/// Tab-Navigation der Main App: Home, Rankings, Social, Profil – mit der Pace-Tab-Leiste.
///
/// - Die vier Startseiten liegen in ``PaceTabPager`` nebeneinander und lassen sich interaktiv wechseln (Wischen mit
///   dem Finger, die Tab-Fläche folgt). Gewischt werden kann nur auf den Startseiten – nicht auf Unterseiten, im
///   Anpassen-Modus von Home oder bei offener Tastatur.
/// - Ein Tab wird beim ersten Sichtbarwerden aufgebaut und bleibt danach erhalten, damit Navigation, Scrollposition
///   und Daten beim Wechseln bestehen bleiben.
/// - Inhalt und Tab-Leiste stehen untereinander (`VStack`), die Leiste liegt also nie über Inhalten. Bei offener
///   Tastatur verschwindet sie, damit Eingabefelder (z. B. die Chat-Eingabe) direkt über der Tastatur stehen.
/// - Erneutes Antippen des aktiven Tabs: Startseite nach oben bzw. zurück zur Startseite (``SwiftUI/View/paceTabRoot(isAtRoot:popToRoot:)``).
struct MainTabView: View {
    @Bindable var viewModel: MainViewModel
    @State private var openedTabs: Set<MainViewModel.Tab> = [.home]
    @State private var isKeyboardVisible = false
    /// Je Tab, ob seine Startseite sichtbar ist (gemeldet von der Startseite selbst).
    @State private var rootVisible: [MainViewModel.Tab: Bool] = [:]
    @State private var reselections: [MainViewModel.Tab: Int] = [:]
    @State private var pagerPosition = MainTabPagerPosition()
    @Environment(\.scenePhase) private var scenePhase

    private let tabs = MainViewModel.Tab.allCases

    var body: some View {
        VStack(spacing: 0) {
            PaceTabPager(
                tabs: tabs,
                selection: $viewModel.selectedTab,
                isPagingEnabled: isPagingEnabled,
                onPositionChange: { position in
                    pagerPosition.update(position)
                    openTabs(visibleAt: position)
                }
            ) { tab in
                page(for: tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isKeyboardVisible {
                MainTabBar(
                    items: tabItems,
                    selection: $viewModel.selectedTab,
                    position: pagerPosition,
                    onReselect: { tab in reselections[tab, default: 0] += 1 }
                )
            }
        }
        .onKeyboardVisibilityChange { isVisible in
            withAnimation(.easeOut(duration: 0.2)) {
                isKeyboardVisible = isVisible
            }
        }
        // Normale Seiten zeigen keine Scrollleisten (wirkt sonst wie eine Webseite); Scrollen bleibt unverändert.
        .scrollIndicators(.hidden)
        .onChange(of: viewModel.selectedTab, initial: true) { _, tab in
            openedTabs.insert(tab)
        }
        .onChange(of: viewModel.selectedTab) { _, tab in
            Task { await viewModel.didSelect(tab) }
        }
        // Ist das Tagesziel erreicht, entfallen die Erinnerungen von heute.
        .onChange(of: viewModel.profile.notifications.todayGoalReached) {
            Task { await viewModel.profile.notifications.reschedule() }
        }
        // Neuer Stand aus Apple Health: „Geschafft!“ (einmal am Tag) und Erinnerungen mit frischem Stand (gedrosselt).
        .onChange(of: viewModel.dashboard.healthKitStepsToday) {
            Task { await viewModel.profile.notifications.progressDidChange() }
        }
        // Bewegungsdaten und Sync laufen für die ganze Main App, nicht nur, solange der Home-Tab offen ist.
        .activityUpdates(viewModel.home)
        // Chatliste und Ungelesen-Badge app-weit aktuell halten (Echtzeit, sonst regelmäßige Abfrage), solange die
        // App im Vordergrund ist – unabhängig davon, welcher Tab offen ist.
        .task(id: scenePhase == .active) { [chats = viewModel.social.chats, scenePhase] in
            guard scenePhase == .active else { return }
            await chats.observe()
        }
    }

    /// Wischen nur auf der Startseite des aktiven Tabs, nicht beim Anpassen von Home und nicht bei offener Tastatur.
    private var isPagingEnabled: Bool {
        (rootVisible[viewModel.selectedTab] ?? true) && !viewModel.dashboard.isEditing && !isKeyboardVisible
    }

    /// Eine Seite im Pager: der Tab, sobald er einmal sichtbar war, sonst nur der Hintergrund.
    private func page(for tab: MainViewModel.Tab) -> some View {
        Group {
            if openedTabs.contains(tab) {
                content(for: tab)
            } else {
                Color.clear.paceScreenBackground()
            }
        }
        .environment(\.paceTabRoot, PaceTabRootContext(
            reselection: reselections[tab] ?? 0,
            reportRoot: { isVisible in
                if rootVisible[tab] != isVisible { rootVisible[tab] = isVisible }
            }
        ))
        .accessibilityHidden(viewModel.selectedTab != tab)
    }

    /// Teilweise sichtbare Tabs beim Wischen aufbauen (einmalig – danach bleiben sie erhalten).
    private func openTabs(visibleAt position: Double) {
        for index in PaceTabPaging.visibleIndices(position, count: tabs.count) where !openedTabs.contains(tabs[index]) {
            openedTabs.insert(tabs[index])
        }
    }

    @ViewBuilder
    private func content(for tab: MainViewModel.Tab) -> some View {
        switch tab {
        case .home: HomeView(viewModel: viewModel.dashboard)
        case .rankings: LeaderboardView(viewModel: viewModel.leaderboard)
        case .social: SocialView(viewModel: viewModel.social)
        case .profile: ProfileView(viewModel: viewModel.profile)
        }
    }

    private var tabItems: [PaceTabItem<MainViewModel.Tab>] {
        [
            PaceTabItem(
                value: .home,
                title: PaceLocalization.text(de: "Home", en: "Home", ru: "Главная"),
                systemImage: "house",
                selectedSystemImage: "house.fill"
            ),
            PaceTabItem(
                value: .rankings,
                title: PaceLocalization.text(de: "Rankings", en: "Rankings", ru: "Рейтинги"),
                systemImage: "chart.bar",
                selectedSystemImage: "chart.bar.fill"
            ),
            PaceTabItem(
                value: .social,
                title: PaceLocalization.text(de: "Social", en: "Social", ru: "Друзья"),
                systemImage: "person.2",
                selectedSystemImage: "person.2.fill",
                // Ungelesene Nachrichten aller Chats.
                badge: viewModel.social.chats.unreadCount
            ),
            PaceTabItem(
                value: .profile,
                title: PaceLocalization.text(de: "Profil", en: "Profile", ru: "Профиль"),
                systemImage: "person",
                selectedSystemImage: "person.fill"
            ),
        ]
    }
}

/// Laufende Pager-Position, getrennt beobachtbar: Nur die Tab-Leiste zeichnet bei jeder Fingerbewegung neu, nicht die
/// Seiten.
@MainActor
@Observable
final class MainTabPagerPosition {
    private(set) var value: Double?

    func update(_ position: Double) {
        guard value.map({ abs($0 - position) > 0.0005 }) ?? true else { return }
        value = position
    }
}

/// Tab-Leiste mit der Fläche an der laufenden Pager-Position.
private struct MainTabBar: View {
    let items: [PaceTabItem<MainViewModel.Tab>]
    @Binding var selection: MainViewModel.Tab
    let position: MainTabPagerPosition
    let onReselect: (MainViewModel.Tab) -> Void

    var body: some View {
        PaceTabBar(items: items, selection: $selection, position: position.value, onReselect: onReselect)
    }
}
