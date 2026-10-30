import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Social-Profil 2.0 (Auftrag 6): Bio, Interessen, Banner, freiwillige Auszeichnungen – alles optional, alte Profile
/// unverändert, ohne Server-Migration kontrolliert ausgeblendet.
struct ProfileBioRulesTests {
    @Test func normalizesAndValidatesLikeTheServer() {
        #expect(ProfileBioRules.normalized("  Jeden Tag ein bisschen aktiver.  \n\n") == "Jeden Tag ein bisschen aktiver.")
        #expect(ProfileBioRules.normalized("Zeile 1   \r\nZeile 2") == "Zeile 1\nZeile 2")
        #expect(ProfileBioRules.normalized(" \n ") == nil)
        #expect(ProfileBioRules.problem("Fitness, Fußball und lange Spaziergänge. 🚶‍♀️⚽️") == nil)
        #expect(ProfileBioRules.problem(String(repeating: "a", count: 160)) == nil)
        #expect(ProfileBioRules.problem(String(repeating: "a", count: 161)) == .tooLong)
        #expect(ProfileBioRules.problem("1\n2\n3\n4") == nil)
        #expect(ProfileBioRules.problem("1\n2\n3\n4\n5") == .tooManyLines)
        #expect(ProfileBioRules.problem("Hallo\u{200B}Welt") == .invalidCharacters)
        #expect(ProfileBioRules.problem("Richtung\u{202E}wechsel") == .invalidCharacters)
        #expect(ProfileBioRules.problem("Tab\tTab") == .invalidCharacters)
        // Emoji mit Zero-Width-Joiner zählt wie auf dem Server nach Unicode-Zeichen.
        #expect(ProfileBioRules.length("🚶‍♀️") == 4)
    }

    @Test func catalogsUseStableIDsAndLimits() {
        #expect(ProfileInterest.parse(["walking", "walking", "galaxy", "running", "hiking", "fitness", "cycling", "football"])
            == [.walking, .running, .hiking, .fitness, .cycling])
        #expect(ProfileInterest.everydayMovement.rawValue == "everyday_movement")
        #expect(ProfileAchievement.parse(["streak_30", "unknown", "streak_30"]) == [.streak30])
        #expect(ProfileAchievement.earned(longestStreak: 6, bestDaySteps: 9_999).isEmpty)
        #expect(ProfileAchievement.earned(longestStreak: 31, bestDaySteps: 12_000) == [.streak30, .bestDay10k])
        #expect(ProfileAchievement.earned(longestStreak: 400, bestDaySteps: 31_000) == [.streak365, .bestDay30k])
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ProfileInterest.walking.title == "Прогулки")
            #expect(ProfileAchievement.streak7.title == "7 дней подряд")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ProfileInterest.wellbeing.title == "Health & wellbeing")
        }
    }
}

@MainActor
struct ProfileDetailsViewModelTests {
    private func makeViewModel(
        _ repository: ProfileDetailsRepositoryStub?,
        media: MediaRepositoryStub? = MediaRepositoryStub(),
        earned: [ProfileAchievement] = [.streak30]
    ) -> ProfileDetailsViewModel {
        ProfileDetailsViewModel(repository: repository, media: media, earnedAchievements: { earned })
    }

    @Test func existingProfilesWithoutDetailsStayAsTheyWere() async {
        let repository = ProfileDetailsRepositoryStub()
        let viewModel = makeViewModel(repository)
        await viewModel.load()
        #expect(viewModel.isAvailable)
        #expect(viewModel.details == .empty)
        #expect(!viewModel.hasContent)
    }

    @Test func serverWithoutMigrationHidesTheFeature() async {
        let viewModel = makeViewModel(ProfileDetailsRepositoryStub { $0.error = .unavailable })
        await viewModel.load()
        #expect(viewModel.availability == .unavailable)
        viewModel.beginEditing()
        viewModel.draftBio = "Hallo"
        #expect(!viewModel.canSave)
        // Ohne Repository (nicht angebunden) ebenso.
        let offline = makeViewModel(nil)
        await offline.load()
        #expect(offline.availability == .unavailable)
    }

    @Test func bioAndInterestsCanBeAddedChangedAndRemoved() async {
        let repository = ProfileDetailsRepositoryStub()
        let viewModel = makeViewModel(repository)
        await viewModel.load()
        viewModel.beginEditing()
        viewModel.draftBio = "  Auf dem Weg zu meiner ersten 100-Tage-Serie.  "
        for interest in [ProfileInterest.walking, .fitness, .football, .outdoor, .challenges, .running] {
            viewModel.toggleInterest(interest)
        }
        // Höchstens fünf.
        #expect(viewModel.draftInterests == [.walking, .fitness, .football, .outdoor, .challenges])
        #expect(!viewModel.canAddInterest)
        #expect(await viewModel.save())
        #expect(viewModel.details.bio == "Auf dem Weg zu meiner ersten 100-Tage-Serie.")
        #expect(viewModel.details.interests.count == 5)

        // Ändern und entfernen.
        viewModel.beginEditing()
        viewModel.toggleInterest(.football)
        viewModel.removeBio()
        #expect(await viewModel.save())
        #expect(viewModel.details.bio == nil)
        #expect(viewModel.details.interests == [.walking, .fitness, .outdoor, .challenges])
        // Nach erneutem Laden (Neustart) dieselben Angaben.
        let reloaded = makeViewModel(repository)
        await reloaded.load()
        #expect(reloaded.details == viewModel.details)
    }

    @Test func invalidBioIsNotSaved() async {
        let repository = ProfileDetailsRepositoryStub()
        let viewModel = makeViewModel(repository)
        await viewModel.load()
        viewModel.beginEditing()
        viewModel.draftBio = String(repeating: "x", count: 161)
        #expect(viewModel.bioProblem == .tooLong)
        #expect(viewModel.bioLength == 161)
        #expect(!viewModel.canSave)
        #expect(!(await viewModel.save()))
        #expect(repository.state.withLock { $0.saved.isEmpty })
    }

    @Test func achievementsArePublishedOnlyWhenSwitchedOn() async {
        let repository = ProfileDetailsRepositoryStub()
        let viewModel = makeViewModel(repository, earned: [.streak30, .bestDay10k])
        await viewModel.load()
        #expect(viewModel.details.visibleAchievements.isEmpty)
        viewModel.beginEditing()
        viewModel.draftShowsAchievements = true
        #expect(await viewModel.save())
        #expect(viewModel.details.visibleAchievements == [.streak30, .bestDay10k])
        // Ausschalten: nichts mehr veröffentlicht.
        viewModel.beginEditing()
        viewModel.draftShowsAchievements = false
        #expect(await viewModel.save())
        #expect(viewModel.details.achievements.isEmpty)
        #expect(!viewModel.details.showsAchievements)
    }

    @Test func bannerUploadReplacesAndRemoves() async throws {
        let repository = ProfileDetailsRepositoryStub()
        let media = MediaRepositoryStub()
        let viewModel = makeViewModel(repository, media: media)
        await viewModel.load()
        let first = try #require(await viewModel.uploadBanner(jpegData: Data([1, 2, 3])))
        #expect(viewModel.details.bannerPath == first.path)
        #expect(first.bucket == .avatars)
        let second = try #require(await viewModel.uploadBanner(jpegData: Data([4, 5, 6])))
        #expect(viewModel.details.bannerPath == second.path)
        // Das alte Banner wird gelöscht.
        #expect(media.state.withLock { $0.deleted } == [first])
        await viewModel.removeBanner()
        #expect(viewModel.details.bannerPath == nil)
        #expect(media.state.withLock { $0.deleted } == [first, second])
    }

    @Test func failedSaveDeletesTheUploadedBanner() async {
        let repository = ProfileDetailsRepositoryStub()
        let media = MediaRepositoryStub()
        let viewModel = makeViewModel(repository, media: media)
        await viewModel.load()
        repository.state.withLock { $0.error = .invalid }
        #expect(await viewModel.uploadBanner(jpegData: Data([1])) == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(media.state.withLock { $0.deleted.count } == 1)
    }
}
