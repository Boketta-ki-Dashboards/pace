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
/// Onboarding (Profil, Region) → Main App. Nach dem Löschen des Kontos: Hinweis → neuer Start (Onboarding).
@MainActor
@Observable
public final class AppRouter {
    public private(set) var route: AppRoute = .launching
    /// Darstellung, Sprache und Erinnerungen. Wird sofort beim Start geladen, damit die erste Ansicht schon in der
    /// gewählten Sprache und Darstellung erscheint.
    public let settings: AppSettings
    /// Profil-, Gruppen- und Chatbilder; `nil` ohne Backend.
    public let media: (any MediaRepository)?

    /// Link, der vor dem Start der Main App geöffnet wurde (z. B. `pace://u/niklas` beim Kaltstart); wird danach
    /// ausgeführt.
    public private(set) var pendingLink: PaceLink?

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var isConnecting = false

    /// - Parameter settings: Nur für Tests: Einstellungen, die die Sprache nicht app-weit anwenden. Standard: aus
    ///   `dependencies.preferences`, angewendet auf die ganze App.
    public init(dependencies: AppDependencies, settings: AppSettings? = nil) {
        self.dependencies = dependencies
        self.settings = settings ?? AppSettings(store: dependencies.preferences)
        if case .available(let services) = dependencies.backend {
            media = services.media
        } else {
            media = nil
        }
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

    // MARK: Links

    /// Öffnet einen Link aus `onOpenURL`. Läuft die Main App noch nicht, wird er gemerkt und nach dem Start ausgeführt.
    /// - Returns: `false`, wenn es kein gültiger Pace-Link ist.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let link = PaceLink(url: url) else { return false }
        if case .main(let main) = route {
            main.open(link)
        } else {
            pendingLink = link
        }
        return true
    }

    // MARK: Konto gelöscht

    /// Nach dem vollständigen Löschen des Kontos (Server und Gerät): Die Main App wird verlassen.
    func didDeleteAccount() {
        pendingLink = nil
        route = .accountDeleted
    }

    /// „Neu beginnen“ nach dem Löschen: neuer Start mit neuer anonymer Identität und Onboarding.
    public func startOver() async {
        guard case .accountDeleted = route else { return }
        route = .launching
        await start()
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
        let home = HomeViewModel(activityData: dependencies.activityData, syncing: sync, liveSteps: dependencies.liveSteps)
        let leaderboard = LeaderboardViewModel(
            store: store,
            leaderboards: services.leaderboards,
            syncing: sync,
            refreshActivity: { [weak home] in await home?.refreshForRanking() },
            social: services.social
        )
        let navigation = MainNavigation()
        let social = SocialViewModel(
            repository: services.social,
            chats: ChatListViewModel(
                repository: services.chat,
                media: services.media,
                social: services.social,
                ownPublicID: { [store] in store.profile.publicID }
            ),
            media: services.media,
            ownUsername: { [store] in store.profile.username }
        )
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
            social: social,
            activityData: dependencies.activityData,
            store: store,
            onOpenRankings: { [navigation] scope in navigation.openRankings(scope) },
            onOpenSocial: { [navigation] in navigation.openSocial() }
        )
        let profile = ProfileViewModel(
            store: store,
            regions: services.regions,
            appIcons: dependencies.appIcons,
            streak: streak,
            statistics: { [dashboard] route in dashboard.statistics(for: route) },
            services: ProfileSettingsServices(
                settings: settings,
                profiles: services.profiles,
                notifications: dependencies.notifications,
                todayProgress: { [weak home, goals] in
                    home?.overview.map { overview in
                        GoalProgressSnapshot(
                            day: overview.today.date,
                            steps: overview.today.competitionSteps,
                            goal: goals.goal(on: overview.today.date),
                            measuredAt: overview.updatedAt
                        )
                    }
                },
                account: services.account,
                media: services.media,
                social: services.social,
                auth: services.auth,
                localData: dependencies.localData,
                appVersion: dependencies.appVersion,
                onAccountDeleted: { [weak self] in self?.didDeleteAccount() }
            )
        )
        profile.openSocial = { [navigation] in navigation.openSocial() }
        // Neue Chatnachricht, während Pace geöffnet ist: lokaler Hinweis (kein Push – dafür fehlt APNs).
        social.chats.onIncomingMessage = { [notifications = profile.notifications] conversation in
            let hint = ChatFormatting.incomingNotification(for: conversation)
            Task { await notifications.announceIncomingMessage(hint) }
        }
        let main = MainViewModel(
            dashboard: dashboard,
            leaderboard: leaderboard,
            social: social,
            profile: profile,
            store: store
        )
        navigation.main = main
        social.openPrivacySettings = { [navigation] in navigation.openProfileSettings(.privacy) }
        // Spitznamen gelten überall sofort, auch in Rankings → Freunde und Gruppen.
        social.onNicknameChange = { [weak leaderboard] profile in leaderboard?.nicknameDidChange(profile) }
        route = .main(main)

        if let link = pendingLink {
            pendingLink = nil
            main.open(link)
        }

        // Erinnerung an das Tagesziel beim Start neu planen (Sprache, Uhrzeit, heutiges Ziel).
        Task { [notifications = profile.notifications] in
            await notifications.refreshAuthorization()
            await notifications.reschedule()
        }

        // Start aus dem Cache: Profil und Region im Hintergrund mit dem Server abgleichen.
        Task { [store] in
            try? await store.refresh()
        }
    }

    static func message(for error: Error) -> String {
        switch error as? BootstrapError {
        case .auth(.anonymousSignInDisabled):
            PaceLocalization.text(
                de: "Die Anmeldung ist derzeit nicht möglich. Bitte versuche es später erneut.",
                en: "Signing in isn't possible right now. Please try again later.",
                ru: "Войти сейчас невозможно. Попробуй позже."
            )
        case .auth(.network), .profile(.network):
            PaceLocalization.text(
                de: "Keine Verbindung zu Pace. Prüfe deine Internetverbindung und versuche es erneut.",
                en: "No connection to Pace. Check your internet connection and try again.",
                ru: "Нет соединения с Pace. Проверь подключение к интернету и попробуй снова."
            )
        case .auth(.rateLimited), .profile(.rateLimited):
            PaceLocalization.text(
                de: "Zu viele Versuche in kurzer Zeit. Bitte versuche es später erneut.",
                en: "Too many attempts in a short time. Please try again later.",
                ru: "Слишком много попыток за короткое время. Попробуй позже."
            )
        default:
            PaceLocalization.text(
                de: "Pace konnte nicht gestartet werden. Bitte versuche es erneut.",
                en: "Pace couldn't be started. Please try again.",
                ru: "Не удалось запустить Pace. Попробуй снова."
            )
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

    func openProfileSettings(_ route: ProfileRoute) {
        main?.openProfileSettings(route)
    }
}
