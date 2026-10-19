import AppFeature
import Foundation
import HomeFeature
import OnboardingFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct AppRouterTests {
    private struct Environment {
        let health: HealthServiceStub
        let auth: AuthStub
        let profiles: ProfileRepositoryStub
        let cache: InMemoryProfileCache
    }

    private func makeRouter(
        health: HealthServiceStub = HealthServiceStub(),
        auth: AuthStub = AuthStub(),
        profiles: ProfileRepositoryStub = ProfileRepositoryStub(),
        cache: InMemoryProfileCache = InMemoryProfileCache(),
        backend: AppDependencies.Backend? = nil
    ) -> (AppRouter, Environment) {
        let services = BackendServices(
            auth: auth,
            profiles: profiles,
            regions: RegionRepositoryStub(),
            activitySync: ActivitySyncRepositoryStub(),
            leaderboards: LeaderboardRepositoryStub(),
            profileCache: cache
        )
        let dependencies = AppDependencies(
            healthAuthorization: health,
            activityData: health,
            backend: backend ?? .available(services),
            homePreferences: InMemoryHomePreferencesStore(),
            preferences: InMemoryAppPreferencesStore(AppPreferences(language: .fixed(.german)))
        )
        return (AppRouter(dependencies: dependencies), Environment(health: health, auth: auth, profiles: profiles, cache: cache))
    }

    private let session = AuthSession(userID: Fixtures.userID, isAnonymous: true)

    // MARK: Health

    @Test func startsInLaunchingState() {
        let (router, _) = makeRouter()

        #expect(router.route.kind == .launching)
    }

    @Test func showsUnavailableScreenWithoutHealthData() async {
        let (router, _) = makeRouter(health: HealthServiceStub { $0.isHealthDataAvailable = false })

        await router.start()

        #expect(router.route.kind == .healthDataUnavailable)
    }

    @Test(arguments: [
        Result<HealthAuthorizationRequestStatus, HealthDataError>.success(.shouldRequest),
        .success(.unknown),
        .failure(.queryFailed(reason: "Test")),
    ])
    func showsHealthPermissionWhenStatusIsNotSettled(status: Result<HealthAuthorizationRequestStatus, HealthDataError>) async {
        let (router, _) = makeRouter(health: HealthServiceStub { $0.authorizationStatus = status })

        await router.start()

        #expect(router.route.kind == .healthPermission)
    }

    @Test func connectsAfterPermissionFlowFinished() async throws {
        let (router, env) = makeRouter(health: HealthServiceStub { $0.authorizationStatus = .success(.shouldRequest) })
        await router.start()

        guard case .healthPermission(let permission) = router.route else {
            Issue.record("Expected permission route, got \(router.route.kind)")
            return
        }
        await permission.requestAccess()

        try await waitUntil { router.route.kind == .onboarding }
        #expect(env.auth.state.current.signInCalls == 1)
    }

    // MARK: Backend & Bootstrap

    @Test func missingBackendConfigurationShowsHint() async {
        let (router, _) = makeRouter(backend: .unavailable(reason: "Config/Pace.xcconfig fehlt"))

        await router.start()

        guard case .backendUnavailable(let message) = router.route else {
            Issue.record("Expected backendUnavailable, got \(router.route.kind)")
            return
        }
        #expect(message.contains("Pace.xcconfig"))
    }

    @Test func newUserSignsInAnonymouslyAndStartsProfileOnboarding() async {
        let (router, env) = makeRouter()

        await router.start()

        #expect(env.auth.state.current.signInCalls == 1)
        guard case .onboarding(let onboarding) = router.route else {
            Issue.record("Expected onboarding, got \(router.route.kind)")
            return
        }
        guard case .profile = onboarding.step else {
            Issue.record("Expected profile step")
            return
        }
    }

    @Test func finishingOnboardingOpensMainAppWithCachedProfile() async throws {
        let (router, env) = makeRouter()
        await router.start()
        guard case .onboarding(let onboarding) = router.route, case .profile(let setup) = onboarding.step else {
            Issue.record("Expected profile onboarding, got \(router.route.kind)")
            return
        }

        setup.displayName = "Niklas"
        setup.username = "niklas"
        await setup.submit()
        guard case .region(let region) = onboarding.step else {
            Issue.record("Expected region step")
            return
        }
        region.search.select(Fixtures.pfungstadtHierarchy)
        await region.confirm(regionalLeaderboardEnabled: true)

        guard case .main(let main) = router.route else {
            Issue.record("Expected main, got \(router.route.kind)")
            return
        }
        #expect(main.store.profile.municipalityID == Fixtures.pfungstadt.id)
        #expect(main.store.profile.regionalLeaderboardEnabled)
        #expect(env.cache.load(for: Fixtures.userID)?.isComplete == true)
    }

    @Test func existingSessionIsReusedWithoutSigningInAgain() async {
        let (router, env) = makeRouter(auth: AuthStub(storedSession: session))

        await router.start()

        #expect(env.auth.state.current.signInCalls == 0)
        #expect(router.route.kind == .onboarding)
    }

    @Test func profileWithoutRegionStartsRegionOnboarding() async {
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile(municipalityID: nil) }
        let (router, _) = makeRouter(auth: AuthStub(storedSession: session), profiles: profiles)

        await router.start()

        guard case .onboarding(let onboarding) = router.route, case .region = onboarding.step else {
            Issue.record("Expected region onboarding, got \(router.route.kind)")
            return
        }
    }

    @Test func completeProfileOpensMainApp() async {
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile() }
        let (router, _) = makeRouter(auth: AuthStub(storedSession: session), profiles: profiles)

        await router.start()

        guard case .main(let main) = router.route else {
            Issue.record("Expected main, got \(router.route.kind)")
            return
        }
        #expect(main.selectedTab == .home)
        #expect(main.store.profile == Fixtures.profile())
    }

    @Test func mainAppHasFourTabsAndHomeOpensRankingsAndSocial() async {
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile(regionalLeaderboardEnabled: true) }
        let (router, _) = makeRouter(auth: AuthStub(storedSession: session), profiles: profiles)
        await router.start()
        guard case .main(let main) = router.route else {
            Issue.record("Expected main, got \(router.route.kind)")
            return
        }
        try? await main.store.loadHierarchyIfNeeded()

        await main.openRankings(scope: Fixtures.hessen)
        #expect(main.selectedTab == .rankings)
        #expect(main.leaderboard.selectedScope?.id == Fixtures.hessen.id)

        main.openSocial()
        #expect(main.selectedTab == .social)

        // Home leitet über dieselbe Navigation weiter.
        main.dashboard.openRankings(nil)
        try? await waitUntil { main.selectedTab == .rankings }
        #expect(main.selectedTab == .rankings)
        #expect(main.home === main.dashboard.activity)
    }

    @Test func cachedProfileOpensMainAppWithoutNetwork() async {
        let profiles = ProfileRepositoryStub { $0.error = .network }
        let (router, _) = makeRouter(
            auth: AuthStub(storedSession: session),
            profiles: profiles,
            cache: InMemoryProfileCache([Fixtures.profile()])
        )

        await router.start()

        #expect(router.route.kind == .main)
    }

    @Test func connectionFailureCanBeRetried() async {
        let profiles = ProfileRepositoryStub { $0.error = .network }
        let (router, _) = makeRouter(auth: AuthStub(storedSession: session), profiles: profiles)

        await router.start()

        guard case .connectionFailed(let message) = router.route else {
            Issue.record("Expected connectionFailed, got \(router.route.kind)")
            return
        }
        #expect(message.contains("Verbindung"))

        profiles.state.withLock {
            $0.error = nil
            $0.profiles[Fixtures.userID] = Fixtures.profile()
        }
        await router.connect()

        #expect(router.route.kind == .main)
    }

    @Test func disabledAnonymousSignInShowsFailure() async {
        let auth = AuthStub { $0.signInResult = .failure(.anonymousSignInDisabled) }
        let (router, _) = makeRouter(auth: auth)

        await router.start()

        #expect(router.route.kind == .connectionFailed)
    }

    @Test func startIsIdempotent() async {
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = Fixtures.profile() }
        let (router, env) = makeRouter(auth: AuthStub(storedSession: session), profiles: profiles)
        await router.start()
        guard case .main(let firstMain) = router.route else {
            Issue.record("Expected main, got \(router.route.kind)")
            return
        }

        await router.start()

        guard case .main(let secondMain) = router.route else {
            Issue.record("Expected main, got \(router.route.kind)")
            return
        }
        #expect(firstMain === secondMain)
        #expect(env.auth.state.current.signInCalls == 0)
    }
}
