import Foundation
import PaceCore
import PaceTestSupport
import SocialFeature
import Testing

@MainActor
struct SocialViewModelTests {
    private let mia = SocialProfile(publicID: UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!, username: "mia", displayName: "Mia")
    private let ben = SocialProfile(publicID: UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000003")!, username: "ben", displayName: "Ben")

    private func makeViewModel(_ repository: SocialRepositoryStub?) -> SocialViewModel {
        SocialViewModel(
            repository: repository,
            ownUsername: { "niklas" },
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) }
        )
    }

    @Test func withoutBackendTheAreaIsHonestlyUnavailable() async {
        let viewModel = makeViewModel(nil)

        await viewModel.load()

        #expect(!viewModel.isAvailable)
        #expect(viewModel.state == .unavailable(SocialError.unavailable.message))
        #expect(viewModel.detail(for: SocialRepositoryStub.group()) == nil)
    }

    @Test func missingServerMigrationIsShownAsUnavailable() async {
        let viewModel = makeViewModel(SocialRepositoryStub { $0.error = .unavailable })

        await viewModel.load()

        #expect(viewModel.state == .unavailable(SocialError.unavailable.message))
        #expect(!viewModel.isAvailable)
    }

    @Test func loadsFriendsRequestsRankingGroupsAndInvitations() async {
        let group = SocialRepositoryStub.group()
        let repository = SocialRepositoryStub { state in
            state.friends = [Friend(profile: self.mia, friendsSince: .distantPast)]
            state.requests = [
                FriendRequest(id: UUID(), direction: .incoming, profile: self.ben, createdAt: .distantPast),
                FriendRequest(id: UUID(), direction: .outgoing, profile: self.mia, createdAt: .distantPast),
            ]
            state.groups = [group]
            state.invitations = [GroupInvitation(
                id: UUID(), groupID: UUID(), groupName: "Team", groupKind: .work, memberCount: 3,
                inviterUsername: "ben", inviterDisplayName: "Ben", createdAt: .distantPast
            )]
        }
        let viewModel = makeViewModel(repository)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.friends.map(\.profile) == [mia])
        #expect(viewModel.incomingRequests.map(\.profile) == [ben])
        #expect(viewModel.outgoingRequests.map(\.profile) == [mia])
        #expect(viewModel.groups == [group])
        #expect(viewModel.invitations.count == 1)
        #expect(viewModel.shareText?.contains("@niklas") == true)

        // Innerhalb einer Minute kein erneutes Laden.
        let calls = repository.state.current.calls.count
        await viewModel.loadIfNeeded()
        #expect(repository.state.current.calls.count == calls)
    }

    @Test func searchFindsExactUsernamesAndSendsRequests() async throws {
        let repository = SocialRepositoryStub { $0.profiles["mia"] = self.mia }
        let viewModel = makeViewModel(repository)

        viewModel.searchText = "  @Mia "
        await viewModel.searchProfile()
        guard case .found(let result) = viewModel.search else { throw UnexpectedStateError() }
        #expect(result.profile == mia)
        #expect(result.relationship == .none)

        await viewModel.sendRequest(to: mia)
        #expect(viewModel.notice == .init(text: "Anfrage an Mia gesendet.", isError: false))
        guard case .found(let updated) = viewModel.search else { throw UnexpectedStateError() }
        #expect(updated.relationship == .outgoingRequest)

        viewModel.searchText = "x"
        await viewModel.searchProfile()
        if case .notFound = viewModel.search {} else { Issue.record("Ungültiger Name sollte nicht gesucht werden") }

        viewModel.searchText = "unbekannt"
        await viewModel.searchProfile()
        #expect(viewModel.search == .notFound("Niemand mit dem Benutzernamen @unbekannt gefunden."))
    }

    @Test func acceptingARequestMakesAFriend() async {
        let request = FriendRequest(id: UUID(), direction: .incoming, profile: ben, createdAt: .distantPast)
        let repository = SocialRepositoryStub { $0.requests = [request] }
        let viewModel = makeViewModel(repository)
        await viewModel.load()

        await viewModel.respond(to: request, accept: true)

        #expect(viewModel.friends.map(\.profile) == [ben])
        #expect(viewModel.requests.isEmpty)
        #expect(viewModel.notice?.isError == false)
        #expect(viewModel.busyIDs.isEmpty)
    }

    @Test func anActionDuringARunningLoadShowsItsResult() async throws {
        let request = FriendRequest(id: UUID(), direction: .incoming, profile: ben, createdAt: .distantPast)
        let repository = SocialRepositoryStub { $0.requests = [request] }
        let viewModel = makeViewModel(repository)
        await viewModel.load()

        // Ein Neuladen läuft: Die Anfragen hat es schon gelesen, die Gruppen sind noch unterwegs.
        repository.gate.close("myGroups")
        let refresh = Task { await viewModel.load() }
        try await waitUntil { repository.gate.waitingCount("myGroups") == 1 }

        let accept = Task { await viewModel.respond(to: request, accept: true) }
        try await waitUntil { repository.state.current.calls.contains("respondToFriendRequest") }
        try await Task.sleep(for: .milliseconds(20)) // die Aktion wartet jetzt auf das laufende Laden
        repository.gate.open("myGroups")
        await accept.value
        await refresh.value

        // Nicht der Stand von vor dem Annehmen.
        #expect(viewModel.requests.isEmpty)
        #expect(viewModel.friends.map(\.profile) == [ben])
    }

    @Test func aConnectionErrorDisappearsAfterTheNextSuccessfulLoad() async {
        let repository = SocialRepositoryStub { $0.friends = [Friend(profile: self.mia, friendsSince: .distantPast)] }
        let viewModel = makeViewModel(repository)
        await viewModel.load()

        repository.state.withLock { $0.error = .network }
        await viewModel.load()
        #expect(viewModel.notice == .init(text: SocialError.network.message, isError: true))
        #expect(viewModel.friends.count == 1)

        repository.state.withLock { $0.error = nil }
        await viewModel.load()
        #expect(viewModel.notice == nil)
    }

    @Test func aRepeatedAcceptAfterALostAnswerCountsAsJoined() async {
        let group = SocialRepositoryStub.group(name: "Laufteam")
        let invitation = GroupInvitation(
            id: UUID(), groupID: group.id, groupName: group.name, groupKind: group.kind, memberCount: 3,
            inviterUsername: "mia", inviterDisplayName: "Mia", createdAt: .distantPast
        )
        // Die erste Zusage kam an, ihre Antwort nicht: Der Server kennt die Einladung nicht mehr, man ist Mitglied.
        let repository = SocialRepositoryStub { state in
            state.groups = [group]
            state.actionError = .notFound
        }
        let viewModel = makeViewModel(repository)

        await viewModel.respond(to: invitation, accept: true)
        #expect(viewModel.notice == .init(text: "Du bist „Laufteam“ beigetreten.", isError: false))

        repository.state.withLock { $0.groups = [] }
        await viewModel.respond(to: invitation, accept: true)
        #expect(viewModel.notice == .init(text: SocialError.notFound.message, isError: true))
    }

    @Test func rateLimitsAreShownAndDataStays() async {
        let repository = SocialRepositoryStub { state in
            state.friends = [Friend(profile: self.mia, friendsSince: .distantPast)]
            state.actionError = .rateLimited
        }
        let viewModel = makeViewModel(repository)
        await viewModel.load()

        await viewModel.sendRequest(to: ben)

        #expect(viewModel.notice == .init(text: SocialError.rateLimited.message, isError: true))
        #expect(viewModel.friends.count == 1)
    }

    @Test func joiningNormalizesTheCodeAndCreatingValidates() async {
        let group = SocialRepositoryStub.group(inviteCode: "K7M2Q9XA")
        let repository = SocialRepositoryStub { $0.groups = [group] }
        let viewModel = makeViewModel(repository)

        #expect(await viewModel.join(inviteCode: " k7m2-q9xa ") == group)
        #expect(repository.state.current.calls.contains("joinGroup:K7M2Q9XA"))
        #expect(await viewModel.join(inviteCode: "XYZ") == nil)
        #expect(viewModel.notice == .init(text: SocialError.invalidInviteCode.message, isError: true))

        #expect(await viewModel.createGroup(GroupDraft(name: "ab")) == nil)
        #expect(viewModel.notice == .init(text: SocialError.invalidName.message, isError: true))
        let created = await viewModel.createGroup(GroupDraft(name: "  Laufteam  ", kind: .work, dailyGoal: 9_000))
        #expect(created?.name == "Laufteam")
        #expect(created?.timeZone == "Europe/Berlin")
        #expect(viewModel.groups.count == 2)
    }
}

@MainActor
struct GroupDetailViewModelTests {
    private let mia = SocialProfile(publicID: UUID(), username: "mia", displayName: "Mia")
    private let ben = SocialProfile(publicID: UUID(), username: "ben", displayName: "Ben")

    @Test func loadsRankingDaysAndInvitableFriends() async {
        let group = SocialRepositoryStub.group(memberCount: 6, reached: 1)
        let repository = SocialRepositoryStub { state in
            state.groups = [group]
            state.friends = [Friend(profile: self.mia, friendsSince: .distantPast), Friend(profile: self.ben, friendsSince: .distantPast)]
            state.groupRankings[group.id] = GroupRanking(
                totalParticipants: 1,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: [GroupRankingEntry(rank: 1, profile: self.mia, competitionSteps: 9_000, isCurrentUser: false, role: .member, reachedGoalToday: true)]
            )
        }
        let social = SocialViewModel(repository: repository)
        await social.load()
        let detail = social.detail(for: group)!

        await detail.load()

        #expect(detail.state == .loaded)
        #expect(detail.invitableFriends.map(\.profile) == [ben]) // Mia ist schon Mitglied
        #expect(detail.todayText == "1 von 2 nötigen Mitgliedern hat das Ziel erreicht")

        await detail.invite(Friend(profile: ben, friendsSince: .distantPast))
        #expect(detail.outgoingInvitations.map(\.profile) == [ben])
        #expect(detail.invitableFriends.isEmpty)

        await detail.select(.weekly)
        #expect(repository.state.current.calls.contains("groupRanking:weekly"))
    }

    @Test func aSlowOlderRankingDoesNotReplaceTheSelectedPeriod() async throws {
        let group = SocialRepositoryStub.group()
        func ranking(_ steps: Int) -> GroupRanking {
            GroupRanking(
                totalParticipants: 1,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: [GroupRankingEntry(rank: 1, profile: mia, competitionSteps: steps, isCurrentUser: false, role: .member, reachedGoalToday: true)]
            )
        }
        let daily = ranking(9_000), weekly = ranking(52_000)
        let repository = SocialRepositoryStub { state in
            state.groups = [group]
            state.groupRankings[group.id] = daily
            state.weeklyGroupRankings[group.id] = weekly
        }
        let detail = GroupDetailViewModel(group: group, repository: repository, social: nil)

        // Das erste Laden (Heute) hängt, währenddessen wählt man „Diese Woche“.
        repository.gate.close("groupRanking:daily")
        let load = Task { await detail.load() }
        try await waitUntil { repository.gate.waitingCount("groupRanking:daily") == 1 }
        await detail.select(.weekly)
        #expect(detail.ranking == weekly)

        repository.gate.open("groupRanking:daily")
        await load.value
        #expect(detail.period == .weekly)
        #expect(detail.ranking == weekly)
        #expect(detail.state == .loaded)
    }

    @Test func retryingAfterAnErrorShowsTheLoadingState() async throws {
        let group = SocialRepositoryStub.group()
        let repository = SocialRepositoryStub { state in
            state.groups = [group]
            state.error = .network
        }
        let detail = GroupDetailViewModel(group: group, repository: repository, social: nil)
        await detail.load()
        #expect(detail.state == .failed(SocialError.network.message))

        repository.state.withLock { $0.error = nil }
        repository.gate.close("groupRanking:daily")
        let retry = Task { await detail.load() }
        try await waitUntil { repository.gate.waitingCount("groupRanking:daily") == 1 }
        #expect(detail.state == .loading)
        repository.gate.open("groupRanking:daily")
        await retry.value
        #expect(detail.state == .loaded)
    }

    @Test func leavingMarksTheGroupAsGone() async {
        let group = SocialRepositoryStub.group()
        let repository = SocialRepositoryStub { $0.groups = [group] }
        let social = SocialViewModel(repository: repository)
        await social.load()
        let detail = social.detail(for: group)!

        #expect(await detail.leave())
        #expect(detail.state == .gone)
        #expect(social.groups.isEmpty)
    }

    @Test func ownerOnlyActionsShowTheServerAnswer() async {
        let group = SocialRepositoryStub.group(role: .member)
        let repository = SocialRepositoryStub { state in
            state.groups = [group]
            state.actionError = .notAllowed
        }
        let detail = GroupDetailViewModel(group: group, repository: repository, social: nil)

        #expect(await detail.setGoal(9_000) == false)
        #expect(detail.notice == .init(text: SocialError.notAllowed.message, isError: true))
        #expect(await detail.update(name: "x", description: "", kind: .work) == false)
        #expect(detail.notice == .init(text: SocialError.invalidName.message, isError: true))
    }

    @Test func requiredMembersRoundUpToAThird() {
        let cases = [(0, 0), (1, 1), (2, 1), (3, 1), (4, 2), (6, 2), (10, 4), (12, 4), (20, 7)]
        for (members, required) in cases {
            #expect(GroupStreakRules.requiredMembers(forMemberCount: members) == required, "\(members) Mitglieder")
        }
    }
}

@MainActor
struct FriendProfileViewModelTests {
    @Test func showsOnlyNamesAndStepsAndCanRemove() async {
        let mia = SocialProfile(publicID: UUID(), username: "mia", displayName: "Mia")
        let repository = SocialRepositoryStub { $0.friends = [Friend(profile: mia, friendsSince: .distantPast)] }
        let viewModel = FriendProfileViewModel(profile: mia, repository: repository, social: nil, calendar: Fixtures.activityCalendar)

        await viewModel.load()
        guard case .loaded(let details) = viewModel.state else {
            Issue.record("Profil erwartet")
            return
        }
        #expect(details.stepsToday == 4_200)

        await viewModel.remove()
        #expect(viewModel.state == .removed)

        await viewModel.load()
        #expect(viewModel.state == .removed) // kein Freund mehr → nicht sichtbar
    }
}
