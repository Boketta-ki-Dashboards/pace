import ActivityFeature
import Foundation
import HealthPermissionFeature
import HomeFeature
import LeaderboardFeature
import Observation
import OnboardingFeature
import PaceCore
import ProfileFeature
import SocialFeature

/// Entscheidet, welcher Screen gezeigt wird, und erzeugt die zugehörigen ViewModels.
///
/// Ablauf: Health-Abfrage → Sitzung (vorhandene nutzen, sonst anonym anmelden) → Profil prüfen →
/// Onboarding (Profil, Region) → Main App.
@MainActor
@Observable
public final class AppRouter {
    public private(set) var route: AppRoute = .launching

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var isConnecting = false

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    /// Bestimmt beim App-Start die erste Route. Weitere Aufrufe haben keine Wirkung.
    public func start() async {
        guard case .launching = route else { return }

        guard dependencies.healthAuthorization.isHealthDataAvailable else {
            route = .healthDataUnavailable
            return
        }

        // Lässt sich der Status nicht ermitteln, zeigen wir den Permission-Screen. Eine erneute Anfrage ist
        // unschädlich: HealthKit zeigt den Dialog nur für Typen, nach denen noch nicht gefragt wurde.
        let status = try? await dependencies.healthAuthorization.authorizationRequestStatus()
        guard case .launching = route else { return }

        switch status {
        case .alreadyRequested:
            await connect()
        case .shouldRequest, .unknown, nil:
            showHealthPermission()
        }
    }

    /// Prüft Sitzung und Profil und zeigt danach Onboarding oder Main App. Auch für „Erneut versuchen“.
    public func connect() async {
        guard !isConnecting else { return }
        guard case .available(let services) = dependencies.backend else {
            if case .unavailable(let reason) = dependencies.backend {
                route = .backendUnavailable(message: reason)
            }
            return
        }

        isConnecting = true
        defer { isConnecting = false }
        route = .connecting

        let bootstrapper = SessionBootstrapper(
            auth: services.auth,
            profiles: services.profiles,
            cache: services.profileCache
        )
        do {
            switch try await bootstrapper.run() {
            case .needsProfile(let userID):
                showOnboarding(.profile(userID), services: services)
            case .needsRegion(let profile):
                showOnboarding(.region(profile), services: services)
            case .ready(let profile):
                showMain(profile: profile, services: services)
            }
        } catch {
            route = .connectionFailed(message: Self.message(for: error))
        }
    }

    private func showHealthPermission() {
        let viewModel = HealthPermissionViewModel(authorization: dependencies.healthAuthorization) { [weak self] in
            Task { await self?.connect() }
        }
        route = .healthPermission(viewModel)
    }

    private func showOnboarding(_ start: OnboardingViewModel.Start, services: BackendServices) {
        let viewModel = OnboardingViewModel(
            start: start,
            profiles: services.profiles,
            regions: services.regions,
            cache: services.profileCache
        ) { [weak self] profile in
            self?.showMain(profile: profile, services: services)
        }
        route = .onboarding(viewModel)
    }

    private func showMain(profile: UserProfile, services: BackendServices) {
        let store = ProfileStore(
            profile: profile,
            profiles: services.profiles,
            regions: services.regions,
            cache: services.profileCache
        )
        let sync = ActivitySyncCoordinator(repository: services.activitySync, userID: profile.id)
        let home = HomeViewModel(activityData: dependencies.activityData, syncing: sync)
        let leaderboard = LeaderboardViewModel(
            store: store,
            leaderboards: services.leaderboards,
            syncing: sync,
            refreshActivity: { [weak home] in await home?.refreshForRanking() }
        )
        let navigation = MainNavigation()
        // Das Tagesziel älterer Versionen wird einmalig in den Zielverlauf übernommen.
        let goals = StepGoalSettings(
            store: dependencies.stepGoals,
            legacyGoal: dependencies.homePreferences.load()?.legacyStepGoal
        )
        let streak = StepStreakTracker(
            history: ActivityHistoryStore(activityData: dependencies.activityData, live: home),
            goals: goals,
            recordStore: dependencies.streakRecords
        )
        let dashboard = HomeDashboardViewModel(
            activity: home,
            standings: RegionalStandingsViewModel(store: store, leaderboards: services.leaderboards, syncing: sync),
            settings: HomeSettings(store: dependencies.homePreferences),
            streak: streak,
            activityData: dependencies.activityData,
            store: store,
            onOpenRankings: { [navigation] scope in navigation.openRankings(scope) },
            onOpenSocial: { [navigation] in navigation.openSocial() }
        )
        let main = MainViewModel(
            dashboard: dashboard,
            leaderboard: leaderboard,
            social: SocialViewModel(),
            profile: ProfileViewModel(store: store, regions: services.regions, appIcons: dependencies.appIcons),
            store: store
        )
        navigation.main = main
        route = .main(main)

        // Start aus dem Cache: Profil und Region im Hintergrund mit dem Server abgleichen.
        Task { [store] in
            try? await store.refresh()
        }
    }

    static func message(for error: Error) -> String {
        switch error as? BootstrapError {
        case .auth(.anonymousSignInDisabled):
            "Die Anmeldung ist derzeit nicht möglich. Bitte versuche es später erneut."
        case .auth(.network), .profile(.network):
            "Keine Verbindung zu Pace. Prüfe deine Internetverbindung und versuche es erneut."
        default:
            "Pace konnte nicht gestartet werden. Bitte versuche es erneut."
        }
    }
}

/// Verbindet Aktionen auf Home mit dem Tab-Wechsel, ohne dass Home die Main App kennt.
@MainActor
private final class MainNavigation {
    weak var main: MainViewModel?

    func openRankings(_ scope: Region?) {
        guard let main else { return }
        Task { await main.openRankings(scope: scope) }
    }

    func openSocial() {
        main?.openSocial()
    }
}
