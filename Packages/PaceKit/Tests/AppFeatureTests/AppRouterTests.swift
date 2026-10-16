import AppFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct AppRouterTests {
    private func makeRouter(_ service: HealthServiceStub) -> AppRouter {
        AppRouter(dependencies: AppDependencies(healthAuthorization: service, activityData: service))
    }

    @Test func startsInLaunchingState() {
        let router = makeRouter(HealthServiceStub())

        #expect(router.route.kind == .launching)
    }

    @Test func showsUnavailableScreenWithoutHealthData() async {
        let router = makeRouter(HealthServiceStub { $0.isHealthDataAvailable = false })

        await router.start()

        #expect(router.route.kind == .healthDataUnavailable)
    }

    @Test(arguments: [
        (Result<HealthAuthorizationRequestStatus, HealthDataError>.success(.shouldRequest), AppRoute.Kind.healthPermission),
        (.success(.unknown), .healthPermission),
        (.failure(.queryFailed(reason: "Test")), .healthPermission),
        (.success(.alreadyRequested), .home),
    ])
    func routesByAuthorizationStatus(
        status: Result<HealthAuthorizationRequestStatus, HealthDataError>,
        expected: AppRoute.Kind
    ) async {
        let router = makeRouter(HealthServiceStub { $0.authorizationStatus = status })

        await router.start()

        #expect(router.route.kind == expected)
    }

    @Test func showsHomeAfterPermissionFlowFinished() async throws {
        let router = makeRouter(HealthServiceStub { $0.authorizationStatus = .success(.shouldRequest) })
        await router.start()

        guard case .healthPermission(let permission) = router.route else {
            Issue.record("Expected permission route, got \(router.route.kind)")
            return
        }
        await permission.requestAccess()

        #expect(router.route.kind == .home)
    }

    @Test func startIsIdempotent() async {
        let service = HealthServiceStub { $0.authorizationStatus = .success(.shouldRequest) }
        let router = makeRouter(service)
        await router.start()
        guard case .healthPermission(let permission) = router.route else {
            Issue.record("Expected permission route")
            return
        }
        await permission.requestAccess()

        await router.start()

        #expect(router.route.kind == .home)
    }
}
