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

    /// Review: „Profil bearbeiten“ zeigt sofort den bekannten Stand (nie leer, ohne Änderung kein Speichern); was während
    /// des erneuten Ladens getippt wird, bleibt. Ohne Eingabe übernimmt der Entwurf den neuen Serverstand.
    @Test func editingStartsFromKnownStateAndKeepsTypingDuringReload() async {
        let repository = ProfileDetailsRepositoryStub { $0.own = ProfileDetails(bio: "Alt", interests: [.walking]) }
        let viewModel = makeViewModel(repository)
        await viewModel.load()
        repository.state.withLock { $0.own = ProfileDetails(bio: "Neu", interests: [.walking, .running]) }

        repository.gate.close("ownDetails")
        let typing = Task { await viewModel.prepareEditing() }
        while repository.gate.waitingCount("ownDetails") == 0 { await Task.yield() }
        #expect(viewModel.draftBio == "Alt")
        #expect(!viewModel.canSave)
        viewModel.draftBio = "Getippt"
        repository.gate.open("ownDetails")
        await typing.value
        #expect(viewModel.draftBio == "Getippt", "Eingabe während des Ladens bleibt")
        #expect(viewModel.details.bio == "Neu")

        let untouched = makeViewModel(repository)
        await untouched.prepareEditing()
        #expect(untouched.draftBio == "Neu")
        #expect(untouched.draftInterests == [.walking, .running])
    }

    /// Review: Speichern und Banner-Änderungen laufen nacheinander – keine Anfrage überschreibt die andere, das Banner
    /// bleibt beim Speichern der Bio erhalten. Nach dem Speichern erscheint „Gespeichert“.
    @Test func writesRunOneAfterAnother() async {
        let repository = ProfileDetailsRepositoryStub()
        let media = MediaRepositoryStub()
        let viewModel = makeViewModel(repository, media: media)
        await viewModel.load()
        viewModel.beginEditing()
        viewModel.draftBio = "Neu"

        repository.gate.close("save")
        let upload = Task { await viewModel.uploadBanner(jpegData: Data([1])) }
        while repository.gate.waitingCount("save") == 0 { await Task.yield() }
        #expect(viewModel.isBusy)
        #expect(!viewModel.canSave, "Speichern wartet, solange das Banner gespeichert wird")
        let savedWhileBusy = await viewModel.save()
        #expect(!savedWhileBusy)
        await viewModel.removeBanner()
        repository.gate.open("save")
        let uploaded = await upload.value
        #expect(uploaded != nil)
        #expect(media.state.withLock { $0.deleted.isEmpty }, "nichts gelöscht, solange nichts ersetzt wurde")

        let saved = await viewModel.save()
        #expect(saved)
        #expect(viewModel.didSave)
        #expect(viewModel.details.bio == "Neu")
        #expect(viewModel.details.bannerPath == uploaded?.path)
        viewModel.draftBio = "Noch neuer"
        #expect(viewModel.hasChanges)
    }

    /// Review: Veröffentlichte Auszeichnungen werden nur aufgewertet – ein Bestwert außerhalb des geladenen Verlaufs
    /// geht nicht verloren, ohne neue Stufe wird nichts gespeichert.
    @Test func publishedAchievementsAreOnlyUpgraded() async {
        #expect(ProfileAchievement.upgraded([.streak100], with: [.streak30, .bestDay10k]) == [.streak100, .bestDay10k])
        let repository = ProfileDetailsRepositoryStub { $0.own = ProfileDetails(showsAchievements: true, achievements: [.streak7, .bestDay20k]) }
        let viewModel = makeViewModel(repository, earned: [.streak30])
        await viewModel.load()
        await viewModel.refreshPublishedAchievements()
        #expect(viewModel.details.achievements == [.streak30, .bestDay20k])
        viewModel.beginEditing()
        #expect(!viewModel.hasChanges)
        let savesBefore = repository.state.withLock { $0.saved.count }
        await viewModel.refreshPublishedAchievements()
        #expect(repository.state.withLock { $0.saved.count } == savesBefore, "ohne neue Stufe nichts speichern")
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
