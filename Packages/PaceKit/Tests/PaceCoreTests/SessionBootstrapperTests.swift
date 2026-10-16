import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct SessionBootstrapperTests {
    private let session = AuthSession(userID: Fixtures.userID, isAnonymous: true)

    private func makeBootstrapper(
        auth: AuthStub,
        profiles: ProfileRepositoryStub = ProfileRepositoryStub(),
        cache: InMemoryProfileCache = InMemoryProfileCache()
    ) -> SessionBootstrapper {
        SessionBootstrapper(auth: auth, profiles: profiles, cache: cache)
    }

    @Test func usesStoredSessionWithoutSigningIn() async throws {
        let auth = AuthStub(storedSession: session)

        _ = try await makeBootstrapper(auth: auth).run()

        #expect(auth.state.current.signInCalls == 0)
    }

    @Test func signsInAnonymouslyWithoutStoredSession() async throws {
        let auth = AuthStub()

        let outcome = try await makeBootstrapper(auth: auth).run()

        #expect(auth.state.current.signInCalls == 1)
        #expect(outcome == .needsProfile(Fixtures.userID))
    }

    @Test func missingProfileNeedsProfileSetup() async throws {
        let outcome = try await makeBootstrapper(auth: AuthStub(storedSession: session)).run()

        #expect(outcome == .needsProfile(Fixtures.userID))
    }

    @Test func profileWithoutRegionNeedsRegion() async throws {
        let profile = Fixtures.profile(municipalityID: nil)
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = profile }

        let outcome = try await makeBootstrapper(auth: AuthStub(storedSession: session), profiles: profiles).run()

        #expect(outcome == .needsRegion(profile))
    }

    @Test func completeProfileIsReadyAndCached() async throws {
        let profile = Fixtures.profile()
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = profile }
        let cache = InMemoryProfileCache()

        let outcome = try await makeBootstrapper(auth: AuthStub(storedSession: session), profiles: profiles, cache: cache).run()

        #expect(outcome == .ready(profile))
        #expect(cache.load(for: Fixtures.userID) == profile)
    }

    @Test func cachedCompleteProfileStartsWithoutNetwork() async throws {
        let profile = Fixtures.profile()
        let profiles = ProfileRepositoryStub { $0.error = .network }

        let outcome = try await makeBootstrapper(
            auth: AuthStub(storedSession: session),
            profiles: profiles,
            cache: InMemoryProfileCache([profile])
        ).run()

        #expect(outcome == .ready(profile))
        #expect(profiles.state.current.fetchCalls == 0)
    }

    @Test func cachedIncompleteProfileIsFetchedAgain() async throws {
        let incomplete = Fixtures.profile(municipalityID: nil)
        let complete = Fixtures.profile()
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = complete }

        let outcome = try await makeBootstrapper(
            auth: AuthStub(storedSession: session),
            profiles: profiles,
            cache: InMemoryProfileCache([incomplete])
        ).run()

        #expect(outcome == .ready(complete))
    }

    @Test func anonymousSignInFailureIsReported() async {
        let auth = AuthStub { $0.signInResult = .failure(.anonymousSignInDisabled) }

        await #expect(throws: BootstrapError.auth(.anonymousSignInDisabled)) {
            try await makeBootstrapper(auth: auth).run()
        }
    }

    @Test func profileLoadFailureIsReported() async {
        let profiles = ProfileRepositoryStub { $0.error = .network }

        await #expect(throws: BootstrapError.profile(.network)) {
            try await makeBootstrapper(auth: AuthStub(storedSession: session), profiles: profiles).run()
        }
    }
}
