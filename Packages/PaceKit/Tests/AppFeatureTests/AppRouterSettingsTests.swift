@testable import AppFeature
import Foundation
import HomeFeature
import PaceCore
import PaceTestSupport
import ProfileFeature
import Testing

/// App-Rahmen: Deep Links, Neustart nach dem Löschen des Kontos, Verdrahtung der Einstellungen.
@MainActor
struct AppRouterSettingsTests {
    private struct Environment {
        let auth: AuthStub
        let profiles: ProfileRepositoryStub
        let account: AccountRepositoryStub
        let localData: InMemoryLocalAccountData
        let notifications: NotificationSchedulerStub
        let settings: AppSettings
    }

    private static let session = AuthSession(userID: Fixtures.userID, isAnonymous: true)
    private static let newUser = UserID(UUID(uuidString: "00000000-0000-4000-8000-000000000099")!)

    private func makeRouter(
        preferences: AppPreferences = AppPreferences(language: .fixed(.german)),
        notifications: NotificationSchedulerStub = NotificationSchedulerStub()
    ) -> (AppRouter, Environment) {
        let auth = AuthStub(storedSession: Self.session) { state in
            state.signInResult = .success(AuthSession(userID: Self.newUser, isAnonymous: true))
        }
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile() }
        let account = AccountRepositoryStub()
        let localData = InMemoryLocalAccountData([LocalDataSection(name: "streakRecord", json: Data("{}".utf8))])
        let services = BackendServices(
            auth: auth,
            profiles: profiles,
            regions: RegionRepositoryStub(),
            activitySync: ActivitySyncRepositoryStub(),
            leaderboards: LeaderboardRepositoryStub(),
            social: SocialRepositoryStub(),
            media: MediaRepositoryStub(),
            account: account,
            profileCache: InMemoryProfileCache()
        )
        let health = HealthServiceStub()
        let store = InMemoryAppPreferencesStore(preferences)
        let dependencies = AppDependencies(
            healthAuthorization: health,
            activityData: health,
            backend: .available(services),
            homePreferences: InMemoryHomePreferencesStore(),
            preferences: store,
            notifications: notifications,
            appVersion: "0.1.0 (1)",
            localData: localData
        )
        // Die Sprache wird nicht app-weit angewendet, damit parallel laufende Tests nicht beeinflusst werden.
        let settings = AppSettings(store: store, preferredLanguages: { ["de-DE"] }, applyLanguage: { _ in })
        let router = AppRouter(dependencies: dependencies, settings: settings)
        return (router, Environment(
            auth: auth,
            profiles: profiles,
            account: account,
            localData: localData,
            notifications: notifications,
            settings: settings
        ))
    }

    private func mainApp(_ router: AppRouter) throws -> MainViewModel {
        guard case .main(let main) = router.route else {
            Issue.record("Expected main, got \(router.route.kind)")
            throw UnexpectedStateError()
        }
        return main
    }

    // MARK: Deep Links

    @Test func profileLinkOpensTheSocialTabWhileRunning() async throws {
        let (router, _) = makeRouter()
        await router.start()
        let main = try mainApp(router)

        let handled = router.open(try #require(URL(string: "pace://u/leon")))

        #expect(handled)
        #expect(main.selectedTab == .social)
        #expect(main.social.requestedProfile == "leon")
        #expect(router.pendingLink == nil)
    }

    @Test func linkOpenedBeforeStartIsExecutedAfterwards() async throws {
        let (router, _) = makeRouter()

        #expect(router.open(try #require(URL(string: "pace://u/Marie_2"))))
        #expect(router.pendingLink == .profile(username: "Marie_2"))
        await router.start()

        let main = try mainApp(router)
        #expect(main.selectedTab == .social)
        #expect(main.social.requestedProfile == "Marie_2")
        #expect(router.pendingLink == nil)
    }

    @Test func foreignOrInvalidLinksAreIgnored() async throws {
        let (router, _) = makeRouter()
        await router.start()
        let main = try mainApp(router)

        #expect(!router.open(try #require(URL(string: "https://example.org/u/leon"))))
        #expect(!router.open(try #require(URL(string: "pace://u/a"))))
        #expect(!router.open(try #require(URL(string: "pace://group/123"))))
        #expect(main.selectedTab == .home)
        #expect(main.social.requestedProfile == nil)
    }

    // MARK: Einstellungen

    @Test func socialSettingsOpenPrivacyInTheProfileTab() async throws {
        let (router, _) = makeRouter()
        await router.start()
        let main = try mainApp(router)

        let open = try #require(main.social.openPrivacySettings)
        open()

        #expect(main.selectedTab == .profile)
        #expect(main.profile.path == [.privacy])

        main.profile.openSocial?()
        #expect(main.selectedTab == .social)
    }

    @Test func profileReceivesAllSettingsServices() async throws {
        let (router, env) = makeRouter()
        await router.start()
        let main = try mainApp(router)

        #expect(main.profile.settings === env.settings)
        #expect(main.profile.appVersion == "0.1.0 (1)")
        #expect(main.profile.account.supportsAvatar)
        #expect(main.profile.privacy.blockedUsers.isAvailable)
        #expect(main.profile.notifications.isAvailable)
        #expect(main.profile.dataPrivacy.isAvailable)
        #expect(main.profile.makeFeedback(.idea).isAvailable)
    }

    @Test func enabledReminderIsScheduledAtStart() async throws {
        let notifications = NotificationSchedulerStub { $0.authorization = .authorized }
        let (router, _) = makeRouter(
            preferences: AppPreferences(language: .fixed(.german), streakReminder: StreakReminderSettings(isEnabled: true, hour: 8)),
            notifications: notifications
        )

        await router.start()

        try await waitUntil { notifications.state.withLock { $0.scheduled }.count == 1 }
        #expect(notifications.state.withLock { $0.scheduled }.first?.hour == 8)
    }

    // MARK: Konto gelöscht

    @Test func deletingTheAccountLeadsBackToOnboardingWithANewIdentity() async throws {
        let (router, env) = makeRouter(preferences: AppPreferences(appearance: .dark, language: .fixed(.english)))
        await router.start()
        let main = try mainApp(router)
        let data = main.profile.dataPrivacy

        data.confirmationText = "niklas"
        await data.deleteAccount()

        #expect(router.route.kind == .accountDeleted)
        #expect(env.account.state.withLock { $0.deleteCalls } == 1)
        #expect(env.auth.state.withLock { $0.signOutCalls } == 1)
        #expect(env.localData.erasures == 1)
        #expect(router.settings.appearance == .automatic)
        #expect(router.settings.language == .system)

        await router.startOver()

        #expect(env.auth.state.withLock { $0.signInCalls } == 1)
        guard case .onboarding(let onboarding) = router.route, case .profile = onboarding.step else {
            Issue.record("Expected profile onboarding, got \(router.route.kind)")
            return
        }
    }

    @Test func startOverOnlyWorksAfterDeletion() async throws {
        let (router, _) = makeRouter()
        await router.start()
        let main = try mainApp(router)

        await router.startOver()

        #expect(try mainApp(router) === main)
    }

    @Test func linkOpenedAfterDeletionWaitsForTheNextStart() async throws {
        let (router, _) = makeRouter()
        await router.start()
        let main = try mainApp(router)
        main.profile.dataPrivacy.confirmationText = "niklas"
        await main.profile.dataPrivacy.deleteAccount()

        #expect(router.open(try #require(URL(string: "pace://u/leon"))))
        #expect(router.pendingLink == .profile(username: "leon"))
        #expect(router.route.kind == .accountDeleted)
    }

    // MARK: Texte

    @Test func startupErrorsAreLocalized() {
        let network = BootstrapError.auth(.network)
        #expect(AppRouter.message(for: network) == "Keine Verbindung zu Pace. Prüfe deine Internetverbindung und versuche es erneut.")
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(AppRouter.message(for: network) == "No connection to Pace. Check your internet connection and try again.")
            #expect(AppRouter.message(for: BootstrapError.profile(.unexpected("x"))) == "Pace couldn't be started. Please try again.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(AppRouter.message(for: BootstrapError.auth(.anonymousSignInDisabled)) == "Войти сейчас невозможно. Попробуй позже.")
        }
    }
}
