import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Auftrag 7, Teil E: Beim Verlassen des Profil-Tabs zurück auf die Startseite – aber nie mit ungespeicherten
/// Änderungen (Profil bearbeiten, angefangene Rückmeldung).
@MainActor
struct ProfileTabResetTests {
    private func makeViewModel(details: ProfileDetailsRepositoryStub = ProfileDetailsRepositoryStub()) async throws -> ProfileViewModel {
        let profile = Fixtures.profile()
        let store = ProfileStore(
            profile: profile,
            profiles: ProfileRepositoryStub { $0.profiles[profile.id] = profile },
            regions: RegionRepositoryStub(),
            cache: InMemoryProfileCache()
        )
        return ProfileViewModel(
            store: store,
            regions: RegionRepositoryStub(),
            searchDebounce: .zero,
            services: ProfileSettingsServices(profileDetails: details)
        )
    }

    @Test func readingPagesAreClosedAndTheMainPageStartsAtTheTop() async throws {
        let viewModel = try await makeViewModel()
        for path in [[ProfileRoute.dataHelpLegal, .appearance], [.privacy], [.activityHealth], [.account], [.notifications], [.help]] {
            viewModel.path = path
            let requests = viewModel.scrollToTopRequest
            #expect(viewModel.didLeaveTab())
            #expect(viewModel.path.isEmpty, "\(path)")
            #expect(viewModel.scrollToTopRequest == requests + 1)
        }
        // Schon auf der Startseite: nur nach oben.
        #expect(viewModel.didLeaveTab())
        #expect(viewModel.path.isEmpty)
    }

    @Test func unsavedProfileChangesStayOpenAndSurviveLeavingTheEditor() async throws {
        let details = ProfileDetailsRepositoryStub { $0.own = ProfileDetails(bio: "Alt") }
        let viewModel = try await makeViewModel(details: details)
        await viewModel.load()
        viewModel.path = [.editProfile]
        await viewModel.details.prepareEditing()
        #expect(viewModel.didLeaveTab(), "ohne Änderung: zurück zur Startseite")

        viewModel.path = [.editProfile]
        await viewModel.details.prepareEditing()
        viewModel.details.draftBio = "Neu, noch nicht gespeichert"
        #expect(!viewModel.didLeaveTab(), "ungespeicherte Änderung: Seite bleibt offen")
        #expect(viewModel.path == [.editProfile])

        // Mit „Zurück“ verlassen und später wieder geöffnet: Der Entwurf ist noch da und lässt sich verwerfen.
        viewModel.path = []
        await viewModel.details.prepareEditing()
        #expect(viewModel.details.draftBio == "Neu, noch nicht gespeichert")
        viewModel.details.discardChanges()
        #expect(viewModel.details.draftBio == "Alt")
        #expect(!viewModel.details.hasChanges)
    }

    @Test func startedFeedbackKeepsTheTabOpenUntilSentOrCleared() async throws {
        let viewModel = try await makeViewModel()
        let route = ProfileRoute.feedback(.problem)
        viewModel.path = [.dataHelpLegal, .help, route]
        viewModel.setDraft(true, for: route)
        #expect(!viewModel.didLeaveTab())
        #expect(viewModel.path.count == 3)
        viewModel.setDraft(false, for: route)
        #expect(viewModel.didLeaveTab())
        #expect(viewModel.path.isEmpty)
    }

    @Test func openingAProfilePageFromAnotherTabKeepsAStartedFeedback() async throws {
        let viewModel = try await makeViewModel()
        let feedback = ProfileRoute.feedback(.problem)
        viewModel.path = [.dataHelpLegal, .help, feedback]
        viewModel.setDraft(true, for: feedback)
        // Z. B. Social → Privatsphäre: Die angefangene Rückmeldung bleibt darunter liegen.
        viewModel.show(.privacy)
        #expect(viewModel.path == [.dataHelpLegal, .help, feedback, .privacy])
        // Pace-Bot → „Problem melden“: zurück zur schon offenen Rückmeldung, nichts geht verloren.
        viewModel.show(feedback)
        #expect(viewModel.path == [.dataHelpLegal, .help, feedback])
        // Ohne Entwurf wie bisher: direkt die gewünschte Seite.
        viewModel.setDraft(false, for: feedback)
        viewModel.show(.privacy)
        #expect(viewModel.path == [.privacy])
    }

    @Test func newlyEarnedAchievementsAreNoUserEditButTypedTermsAre() async throws {
        let details = ProfileDetailsRepositoryStub {
            $0.own = ProfileDetails(showsAchievements: true, achievements: [.streak7], supportsExtendedProfile: true)
        }
        let profile = Fixtures.profile()
        let store = ProfileStore(
            profile: profile,
            profiles: ProfileRepositoryStub { $0.profiles[profile.id] = profile },
            regions: RegionRepositoryStub(),
            cache: InMemoryProfileCache()
        )
        let viewModel = ProfileViewModel(
            store: store,
            regions: RegionRepositoryStub(),
            searchDebounce: .zero,
            services: ProfileSettingsServices(profileDetails: details)
        )
        await viewModel.load()
        viewModel.path = [.editProfile]
        await viewModel.details.prepareEditing()
        // Eine neu erreichte Stufe hält den Tab nicht offen (die App trägt sie selbst nach).
        #expect(!viewModel.details.hasUserEdits)
        #expect(viewModel.didLeaveTab())
        // Ein eingetippter, noch nicht hinzugefügter Begriff schon.
        viewModel.path = [.editProfile]
        viewModel.details.customInterestInput = "Breakdance"
        #expect(viewModel.details.hasUserEdits)
        #expect(!viewModel.didLeaveTab())
    }
}
