import HealthPermissionFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct HealthPermissionViewModelTests {
    @Test func finishesAfterSuccessfulRequest() async {
        let service = HealthServiceStub()
        var finishCount = 0
        let viewModel = HealthPermissionViewModel(authorization: service) { finishCount += 1 }

        await viewModel.requestAccess()

        #expect(service.recordedCalls.authorizationRequests == 1)
        #expect(finishCount == 1)
        #expect(viewModel.state == .idle)
    }

    @Test func showsErrorAndStaysWhenRequestFails() async {
        let service = HealthServiceStub {
            $0.requestAuthorizationResult = .failure(.authorizationRequestFailed(reason: "Missing entitlement"))
        }
        var finishCount = 0
        let viewModel = HealthPermissionViewModel(authorization: service) { finishCount += 1 }

        await viewModel.requestAccess()

        #expect(finishCount == 0)
        guard case .failed = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
    }

    @Test func canRetryAfterFailure() async {
        let service = HealthServiceStub { $0.requestAuthorizationResult = .failure(.protectedDataUnavailable) }
        var finishCount = 0
        let viewModel = HealthPermissionViewModel(authorization: service) { finishCount += 1 }

        await viewModel.requestAccess()
        service.update { $0.requestAuthorizationResult = .success(()) }
        await viewModel.requestAccess()

        #expect(service.recordedCalls.authorizationRequests == 2)
        #expect(finishCount == 1)
        #expect(viewModel.state == .idle)
    }
}
