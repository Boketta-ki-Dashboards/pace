import Foundation
import OnboardingFeature
import PaceCore
import PaceTestSupport
import Testing

@MainActor
struct ProfileSetupViewModelTests {
    private final class Created {
        var profiles: [UserProfile] = []
    }

    private func makeViewModel(
        _ profiles: ProfileRepositoryStub = ProfileRepositoryStub(),
        created: Created = Created()
    ) -> ProfileSetupViewModel {
        ProfileSetupViewModel(userID: Fixtures.userID, profiles: profiles, availabilityDebounce: .zero) { profile in
            created.profiles.append(profile)
        }
    }

    @Test func emptyFormCannotBeSubmittedAndShowsNoErrors() {
        let viewModel = makeViewModel()

        #expect(viewModel.usernameStatus == .empty)
        #expect(viewModel.usernameMessage == nil)
        #expect(viewModel.displayNameMessage == nil)
        #expect(!viewModel.canSubmit)
    }

    struct InvalidUsername: Sendable, CustomTestStringConvertible {
        let input: String
        let violation: UsernameRules.Violation
        let message: String

        var testDescription: String { input }
    }

    @Test(arguments: [
        InvalidUsername(input: "ab", violation: .tooShort, message: "Mindestens 3 Zeichen."),
        InvalidUsername(input: "abcdefghijklmnopqrstu", violation: .tooLong, message: "Höchstens 20 Zeichen."),
        InvalidUsername(input: "jörg", violation: .invalidCharacters, message: "Nur Buchstaben ohne Umlaute, Ziffern und _ sind erlaubt."),
        InvalidUsername(input: "max mustermann", violation: .invalidCharacters, message: "Nur Buchstaben ohne Umlaute, Ziffern und _ sind erlaubt."),
        InvalidUsername(input: "Admin", violation: .reserved, message: "Dieser Name ist reserviert."),
    ])
    func invalidUsernamesShowGermanMessages(_ invalid: InvalidUsername) {
        let viewModel = makeViewModel()
        viewModel.displayName = "Niklas"

        viewModel.username = invalid.input

        #expect(viewModel.usernameStatus == .invalid(invalid.violation))
        #expect(viewModel.usernameMessage == invalid.message)
        #expect(!viewModel.canSubmit)
    }

    @Test func tooLongDisplayNameIsRejected() {
        let viewModel = makeViewModel()
        viewModel.username = "niklas"

        viewModel.displayName = String(repeating: "a", count: 31)

        #expect(viewModel.displayNameMessage == "Höchstens 30 Zeichen.")
        #expect(!viewModel.canSubmit)
    }

    @Test func availabilityCheckMarksFreeName() async {
        let viewModel = makeViewModel()
        viewModel.username = "niklas"

        await viewModel.checkUsernameAvailability()

        #expect(viewModel.usernameStatus == .available)
        #expect(viewModel.usernameMessage == "Verfügbar")
    }

    @Test func takenNameIsDetectedCaseInsensitively() async {
        let profiles = ProfileRepositoryStub { $0.takenUsernames = ["niklas"] }
        let viewModel = makeViewModel(profiles)
        viewModel.displayName = "Niklas"
        viewModel.username = "NiKlAs"

        await viewModel.checkUsernameAvailability()

        #expect(viewModel.usernameStatus == .taken)
        #expect(viewModel.usernameMessage == "Dieser Benutzername ist schon vergeben.")
        #expect(!viewModel.canSubmit)
    }

    @Test func failedAvailabilityCheckStillAllowsSubmitting() async {
        let profiles = ProfileRepositoryStub { $0.error = .network }
        let viewModel = makeViewModel(profiles)
        viewModel.displayName = "Niklas"
        viewModel.username = "niklas"

        await viewModel.checkUsernameAvailability()

        #expect(viewModel.usernameStatus == .unchecked)
        #expect(viewModel.canSubmit)
    }

    @Test func submitCreatesNormalizedProfile() async throws {
        let profiles = ProfileRepositoryStub()
        let created = Created()
        let viewModel = makeViewModel(profiles, created: created)
        viewModel.displayName = "  Niklas   K.  "
        viewModel.username = " niklas_k "

        await viewModel.submit()

        #expect(profiles.state.current.createCalls == [NewProfile(username: "niklas_k", displayName: "Niklas K.")])
        let profile = try #require(created.profiles.first)
        #expect(profile.username == "niklas_k")
        #expect(profile.municipalityID == nil)
        #expect(!viewModel.isSubmitting)
    }

    @Test func serverSideConflictMarksNameAsTaken() async {
        // Die Verfügbarkeitsprüfung kam nicht dazu; der Server meldet den Konflikt beim Anlegen.
        let profiles = ProfileRepositoryStub { $0.takenUsernames = ["niklas"] }
        let created = Created()
        let viewModel = makeViewModel(profiles, created: created)
        viewModel.displayName = "Niklas"
        viewModel.username = "Niklas"

        await viewModel.submit()

        #expect(created.profiles.isEmpty)
        #expect(viewModel.usernameStatus == .taken)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func networkErrorShowsMessage() async {
        let profiles = ProfileRepositoryStub { $0.error = .network }
        let created = Created()
        let viewModel = makeViewModel(profiles, created: created)
        viewModel.displayName = "Niklas"
        viewModel.username = "niklas"

        await viewModel.submit()

        #expect(created.profiles.isEmpty)
        #expect(viewModel.errorMessage?.contains("Verbindung") == true)
        #expect(viewModel.canSubmit)
    }

    @Test func lostResponseContinuesWithExistingProfile() async throws {
        // Das Profil wurde angelegt, aber die Antwort ging verloren: Ein erneutes Anlegen scheitert.
        let existing = Fixtures.profile(municipalityID: nil)
        let profiles = ProfileRepositoryStub { $0.profiles[Fixtures.userID] = existing }
        let created = Created()
        let viewModel = ProfileSetupViewModel(userID: Fixtures.userID, profiles: FailingCreate(profiles), availabilityDebounce: .zero) {
            created.profiles.append($0)
        }
        viewModel.displayName = "Niklas"
        viewModel.username = "niklas"

        await viewModel.submit()

        #expect(created.profiles == [existing])
        #expect(viewModel.errorMessage == nil)
    }
}

/// Lässt das Anlegen scheitern, als wäre das Profil schon vorhanden; alles andere geht an den Stub.
private struct FailingCreate: ProfileRepository {
    let base: ProfileRepositoryStub

    init(_ base: ProfileRepositoryStub) {
        self.base = base
    }

    func fetchProfile(for userID: UserID) async throws -> UserProfile? {
        try await base.fetchProfile(for: userID)
    }

    func createProfile(_ profile: NewProfile, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("Profil existiert bereits.")
    }

    func updateRegion(municipalityID: RegionID, regionalLeaderboardEnabled: Bool, for userID: UserID) async throws -> UserProfile {
        try await base.updateRegion(municipalityID: municipalityID, regionalLeaderboardEnabled: regionalLeaderboardEnabled, for: userID)
    }

    func updateRegionalLeaderboardEnabled(_ enabled: Bool, for userID: UserID) async throws -> UserProfile {
        try await base.updateRegionalLeaderboardEnabled(enabled, for: userID)
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await base.isUsernameAvailable(username)
    }
}
