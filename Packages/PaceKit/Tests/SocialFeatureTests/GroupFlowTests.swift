import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

@MainActor
struct CreateGroupViewModelTests {
    private let mia = SocialProfile(publicID: UUID(uuidString: "dddddddd-0000-4000-8000-000000000001")!, username: "mia", displayName: "Mia")
    private let ben = SocialProfile(publicID: UUID(uuidString: "dddddddd-0000-4000-8000-000000000002")!, username: "ben", displayName: "Ben")

    private func makeSocial(
        _ repository: SocialRepositoryStub,
        media: MediaRepositoryStub? = nil
    ) async -> SocialViewModel {
        let social = SocialViewModel(
            repository: repository,
            media: media,
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) }
        )
        await social.load()
        return social
    }

    private func friends() -> SocialRepositoryStub {
        SocialRepositoryStub { state in
            state.friends = [Friend(profile: self.mia, friendsSince: .distantPast), Friend(profile: self.ben, friendsSince: .distantPast)]
        }
    }

    @Test func invalidInputIsRejectedBeforeTheServer() async {
        let repository = friends()
        let social = await makeSocial(repository)
        let form = social.createGroupForm()
        #expect(form.nameError == nil) // noch nichts eingegeben

        form.name = "ab"
        #expect(form.nameError == SocialError.invalidName.message)
        #expect(await form.create() == nil)
        #expect(social.notice == .init(text: SocialError.invalidName.message, isError: true))

        form.name = "Abendrunde"
        form.description = String(repeating: "x", count: 201)
        #expect(form.descriptionError == SocialError.invalidDescription.message)
        #expect(form.remainingDescriptionCharacters == -1)
        #expect(await form.create() == nil)
        #expect(!repository.state.current.calls.contains("createGroup"))
    }

    @Test func goalStaysInTheServerRangeInSteps() async {
        let social = await makeSocial(friends())
        let form = social.createGroupForm()
        #expect(form.dailyGoal == 8_000)

        form.increaseGoal()
        #expect(form.dailyGoal == 8_500)
        form.setGoal(120_000)
        #expect(form.dailyGoal == 100_000)
        #expect(!form.canIncreaseGoal)
        form.setGoal(10)
        #expect(form.dailyGoal == 1_000)
        #expect(!form.canDecreaseGoal)
        form.setGoal(7_740)
        #expect(form.dailyGoal == 7_500)
    }

    @Test func createsTheGroupWithInvitesAndPrivacy() async throws {
        let repository = friends()
        let social = await makeSocial(repository)
        let form = social.createGroupForm()
        form.name = "  Abendrunde  "
        form.description = "Gemeinsam jeden Tag ein Stück weiter."
        form.kind = .work
        form.privacy = .code
        form.toggleInvitee(ben.publicID)
        form.toggleInvitee(mia.publicID)
        form.toggleInvitee(ben.publicID)
        #expect(form.invitees == [mia])
        form.toggleInvitee(ben.publicID)
        #expect(form.invitees == [mia, ben])

        let group = try #require(await form.create())

        #expect(group.name == "Abendrunde")
        #expect(group.kind == .work)
        #expect(group.privacy == .code)
        #expect(social.groups.map(\.id) == [group.id]) // erscheint in Social
        let invited = repository.state.current.outgoingInvitations[group.id]?.map(\.profile) ?? []
        #expect(Set(invited) == [mia, ben])
        #expect(!repository.state.current.calls.contains("invite")) // der Server hat beim Anlegen schon eingeladen
        #expect(social.notice == .init(text: "Gruppe „Abendrunde“ erstellt.", isError: false))
        let detail = try #require(social.detail(groupID: group.id))
        #expect(detail.notice == social.notice) // die Details zeigen dasselbe direkt nach dem Öffnen
    }

    @Test func theImageIsUploadedAfterCreatingIntoTheGroupFolder() async throws {
        let repository = friends()
        let media = MediaRepositoryStub()
        let social = await makeSocial(repository, media: media)
        let form = social.createGroupForm()
        #expect(form.canPickImage)
        form.name = "Abendrunde"
        #expect(form.setImage(.init(data: Data(repeating: 1, count: 1_000))))

        let group = try #require(await form.create())

        #expect(media.state.current.uploads == [.groupImage(groupID: group.id)])
        let calls = repository.state.current.calls
        let created = try #require(calls.firstIndex(of: "createGroup"))
        let imageSet = try #require(calls.firstIndex(of: "setGroupImage"))
        #expect(created < imageSet)
        #expect(group.imagePath?.hasPrefix(group.id.uuidString.lowercased()) == true)
    }

    @Test func aFailedImageUploadKeepsTheGroupAndSaysWhatIsMissing() async throws {
        let repository = friends()
        let media = MediaRepositoryStub { $0.error = .network }
        let social = await makeSocial(repository, media: media)
        let form = social.createGroupForm()
        form.name = "Abendrunde"
        form.setImage(.init(data: Data(repeating: 1, count: 100)))

        let group = try #require(await form.create())

        #expect(social.groups.map(\.id) == [group.id])
        #expect(group.imagePath == nil)
        #expect(social.notice?.isError == true)
        #expect(social.notice?.text.contains(SocialText.imageNotSaved) == true)
    }

    @Test func imagesMustFitTheLimitAndNeedStorage() async {
        let withoutMedia = await makeSocial(friends())
        #expect(!withoutMedia.createGroupForm().canPickImage)

        let social = await makeSocial(friends(), media: MediaRepositoryStub())
        let form = social.createGroupForm()
        #expect(!form.setImage(.init(data: Data(count: SocialViewModel.groupImageMaximumBytes + 1))))
        #expect(form.imageError == SocialText.imageTooLarge)
        #expect(form.image == nil)
        #expect(!form.setImage(.init(data: Data(count: 10), contentType: "application/pdf")))
        #expect(form.setImage(.init(data: Data(count: 10))))
        #expect(form.imageError == nil)
        form.removeImage()
        #expect(form.image == nil)
    }

    @Test func serverErrorsAreShownAndNothingIsCreated() async {
        let repository = friends()
        repository.state.withLock { $0.actionError = .limitReached }
        let social = await makeSocial(repository)
        let form = social.createGroupForm()
        form.name = "Abendrunde"

        #expect(await form.create() == nil)
        #expect(social.notice == .init(text: SocialError.limitReached.message, isError: true))
        #expect(social.groups.isEmpty)
        #expect(!form.isCreating)
    }
}

@MainActor
struct GroupDetailSettingsTests {
    private let me = SocialProfile(publicID: UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000001")!, username: "niklas", displayName: "Niklas")
    private let mia = SocialProfile(publicID: UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000002")!, username: "mia", displayName: "Mia")
    private let ben = SocialProfile(publicID: UUID(uuidString: "eeeeeeee-0000-4000-8000-000000000003")!, username: "ben", displayName: "Ben")

    private func ranking(for group: GroupSummary) -> GroupRanking {
        GroupRanking(
            totalParticipants: 3,
            groupToday: Fixtures.day(2026, 10, 16),
            dailyGoal: group.dailyGoal,
            entries: [
                GroupRankingEntry(rank: 1, profile: mia, competitionSteps: 12_480, isCurrentUser: false, role: .member, reachedGoalToday: true),
                GroupRankingEntry(rank: 2, profile: me, competitionSteps: 8_432, isCurrentUser: true, role: .owner, reachedGoalToday: true),
                GroupRankingEntry(rank: 3, profile: ben, competitionSteps: 2_000, isCurrentUser: false, role: .member, reachedGoalToday: false),
            ]
        )
    }

    private func make(
        role: GroupRole = .owner,
        memberCount: Int = 12,
        reached: Int = 4,
        media: MediaRepositoryStub? = nil
    ) async -> (GroupDetailViewModel, SocialViewModel, SocialRepositoryStub) {
        let group = SocialRepositoryStub.group(name: "Smoking red", role: role, memberCount: memberCount, reached: reached)
        let repository = SocialRepositoryStub { state in
            state.groups = [group]
            state.groupRankings[group.id] = self.ranking(for: group)
        }
        let social = SocialViewModel(repository: repository, media: media)
        await social.load()
        let detail = social.detail(for: group)!
        await detail.load()
        return (detail, social, repository)
    }

    @Test func progressUsesTheServerCountsAndTheThirdRule() async {
        let (detail, _, _) = await make(memberCount: 12, reached: 4)

        #expect(detail.todayText == "4 von 12 Mitgliedern haben heute das Ziel erreicht")
        #expect(detail.requiredGoalsText == "4 von 4 benötigten Zielen")
        #expect(detail.flameStatusText == "Flamme gesichert")
        #expect(detail.thirdRuleText == "Mindestens ⅓ der Mitglieder, aufgerundet: heute 4 von 12.")
        #expect(detail.memberPills.count == 12)
        #expect(detail.memberPills.filter { $0 }.count == 4)
        #expect(detail.requiredProgress == 1)
    }

    @Test func missingGoalsAreCountedAndNotMixedUp() async {
        let (detail, _, _) = await make(memberCount: 10, reached: 1)

        #expect(detail.countedGoals == 1)
        #expect(detail.missingGoals == 3)
        #expect(detail.flameStatusText == "Noch 3 Ziele")
        #expect(detail.requiredGoalsText == "1 von 4 benötigten Zielen")
        #expect(detail.todayText == "1 von 10 Mitgliedern hat heute das Ziel erreicht")
        #expect(abs(detail.requiredProgress - 0.25) < 0.0001)
    }

    @Test func membersListTheOwnerFirstAndOnlyTheOwnerRemovesOthers() async {
        let (detail, social, repository) = await make()

        #expect(detail.members.map(\.profile) == [me, ben, mia])
        let meEntry = detail.members[0]
        let benEntry = detail.members[1]
        #expect(!detail.canRemove(meEntry))
        #expect(detail.canRemove(benEntry))

        #expect(await detail.remove(benEntry))
        #expect(detail.members.map(\.profile) == [me, mia])
        #expect(detail.notice == .init(text: SocialText.memberRemoved("Ben"), isError: false))
        #expect(repository.state.current.calls.contains("removeMember"))
        #expect(social.state == .loaded)

        let (memberView, _, _) = await make(role: .member)
        #expect(!memberView.canRemove(memberView.members[1]))
    }

    @Test func detailsAndPrivacyAreSavedTogether() async {
        let (detail, social, repository) = await make()

        #expect(await detail.updateDetails(name: " Abendrunde ", description: "Neu", kind: .friends, privacy: .inviteOnly))

        #expect(detail.group.name == "Abendrunde")
        #expect(detail.group.privacy == .inviteOnly)
        #expect(repository.state.current.calls.contains("updateGroupDetails"))
        #expect(social.groups.first?.name == "Abendrunde") // auch auf der Hauptseite
        #expect(await detail.updateDetails(name: "x", description: "", kind: .friends, privacy: .code) == false)
        #expect(detail.notice == .init(text: SocialError.invalidName.message, isError: true))
    }

    @Test func goalsOutsideTheRangeAreRejected() async {
        let (detail, _, repository) = await make()

        #expect(await detail.setGoal(500) == false)
        #expect(detail.notice == .init(text: SocialError.invalidGoal.message, isError: true))
        #expect(!repository.state.current.calls.contains("setGroupGoal"))

        #expect(await detail.setGoal(9_000))
        #expect(detail.notice == .init(text: "Das neue Gruppenziel gilt ab morgen.", isError: false))
    }

    @Test func theGroupImageCanBeChangedAndRemoved() async {
        let media = MediaRepositoryStub()
        let (detail, _, _) = await make(media: media)
        #expect(detail.canChangeImage)

        #expect(await detail.setImage(.init(data: Data(repeating: 2, count: 2_000))))
        #expect(detail.group.imagePath != nil)
        #expect(media.state.current.uploads == [.groupImage(groupID: detail.group.id)])

        #expect(await detail.removeImage())
        #expect(detail.group.imagePath == nil)

        let (withoutStorage, _, _) = await make()
        #expect(!withoutStorage.canChangeImage)
        #expect(await withoutStorage.setImage(.init(data: Data(count: 10))) == false)
        #expect(withoutStorage.notice == .init(text: SocialText.imageStorageUnavailable, isError: true))
    }

    @Test func deletingShowsTheResultOnTheMainPage() async {
        let (detail, social, _) = await make()

        #expect(await detail.delete())

        #expect(detail.state == .gone)
        #expect(social.groups.isEmpty)
        #expect(social.notice == .init(text: "Gruppe „Smoking red“ gelöscht.", isError: false))
        #expect(social.detail(groupID: detail.group.id) == nil)
    }

    @Test func invitationsCanBeWithdrawn() async throws {
        let (detail, _, _) = await make()
        let friend = Friend(profile: SocialProfile(publicID: UUID(), username: "lea", displayName: "Lea"), friendsSince: .distantPast)
        #expect(await detail.invite(friend))
        let invitation = try #require(detail.outgoingInvitations.first)

        #expect(await detail.cancel(invitation))
        #expect(detail.outgoingInvitations.isEmpty)
        #expect(detail.notice == .init(text: "Einladung zurückgezogen.", isError: false))
    }

    @Test func groupTextsInEnglishAndRussian() async {
        let (detail, _, _) = await make(memberCount: 12, reached: 4)

        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(detail.todayText == "4 of 12 members reached the goal today")
            #expect(detail.requiredGoalsText == "4 of 4 required goals")
            #expect(SocialText.streakTitle(12) == "12-day streak")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(detail.flameStatusText == "Огонь сохранён")
            #expect(SocialText.goalsMissing(1) == "Ещё 1 цель")
            #expect(SocialText.goalsMissing(3) == "Ещё 3 цели")
            #expect(SocialText.goalsMissing(5) == "Ещё 5 целей")
        }
    }
}
