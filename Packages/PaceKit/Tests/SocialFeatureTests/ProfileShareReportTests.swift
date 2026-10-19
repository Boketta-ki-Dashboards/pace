import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

@MainActor
struct UserProfileViewModelTests {
    private let mia = SocialProfile(publicID: UUID(uuidString: "ffffffff-0000-4000-8000-000000000001")!, username: "mia", displayName: "Mia")
    private let ben = SocialProfile(publicID: UUID(uuidString: "ffffffff-0000-4000-8000-000000000002")!, username: "ben", displayName: "Ben")

    private func make(_ configure: @escaping (inout SocialRepositoryStub.State) -> Void) async -> (SocialViewModel, SocialRepositoryStub) {
        let repository = SocialRepositoryStub(configure: configure)
        let social = SocialViewModel(
            repository: repository,
            ownUsername: { "niklas" },
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) }
        )
        await social.load()
        return (social, repository)
    }

    @Test func aStrangerCanBeAddedAndTheRequestWithdrawn() async throws {
        let (social, repository) = await make { $0.searchableProfiles = [self.mia] }
        let profile = social.userProfile(for: mia)!

        await profile.load()
        #expect(profile.relationship == SocialRelationship.none)
        #expect(profile.loaded?.stepsToday == nil) // Schritte nur unter Freunden
        #expect(profile.chatTarget == nil)

        #expect(await profile.sendRequest())
        #expect(profile.relationship == .outgoingRequest)

        // Die Anfrage taucht beim nächsten Laden auf und lässt sich zurückziehen.
        let requestID = UUID()
        repository.state.withLock { $0.requests = [FriendRequest(id: requestID, direction: .outgoing, profile: self.mia, createdAt: .distantPast)] }
        await social.load()
        await profile.load()
        #expect(profile.requestID == requestID)
        #expect(await profile.withdrawRequest())
        #expect(social.outgoingRequests.isEmpty)
    }

    @Test func anIncomingRequestCanBeAcceptedFromTheProfile() async {
        let requestID = UUID()
        let (social, _) = await make { state in
            state.requests = [FriendRequest(id: requestID, direction: .incoming, profile: self.ben, createdAt: .distantPast)]
        }
        let profile = social.userProfile(for: ben)!
        await profile.load()
        #expect(profile.relationship == .incomingRequest)

        #expect(await profile.respond(accept: true))

        #expect(profile.relationship == .friend)
        #expect(profile.chatTarget == .direct(ben))
        #expect(profile.loaded?.stepsToday == 4_200)
        #expect(social.friends.map(\.profile) == [ben])
    }

    @Test func friendsCanBeRemovedAndBlocked() async {
        let (social, repository) = await make { state in
            state.friends = [Friend(profile: self.mia, friendsSince: .distantPast)]
            state.searchableProfiles = [self.mia]
        }
        let profile = social.userProfile(for: mia)!
        await profile.load()
        #expect(profile.relationship == .friend)

        #expect(await profile.block())

        #expect(profile.loaded?.isBlockedByMe == true)
        #expect(profile.chatTarget == nil)
        #expect(social.friends.isEmpty)
        #expect(repository.state.current.blocked == [mia])

        #expect(await profile.unblock())
        #expect(profile.loaded?.isBlockedByMe == false)
    }

    @Test func unknownPeopleShowADesignedHint() async {
        let (social, _) = await make { _ in }
        let profile = social.userProfile(for: mia)!

        await profile.load()

        #expect(profile.state == .notFound)
        #expect(profile.shareURL.absoluteString == "pace://u/mia")
    }
}

@MainActor
struct ShareProfileViewModelTests {
    private let mia = SocialProfile(publicID: UUID(uuidString: "abababab-0000-4000-8000-000000000001")!, username: "mia", displayName: "Mia")
    private let ben = SocialProfile(publicID: UUID(uuidString: "abababab-0000-4000-8000-000000000002")!, username: "ben", displayName: "Ben")

    private func make(chats: ChatListViewModel?) async -> SocialViewModel {
        let group = SocialRepositoryStub.group(name: "Klasse 8b")
        let repository = SocialRepositoryStub { state in
            state.friends = [Friend(profile: self.mia, friendsSince: .distantPast), Friend(profile: self.ben, friendsSince: .distantPast)]
            state.groups = [group]
        }
        let social = SocialViewModel(repository: repository, chats: chats, ownUsername: { "niklas" })
        await social.load()
        return social
    }

    @Test func recipientsAreFriendsAndOwnGroupsWithoutTheSharedPerson() async throws {
        let social = await make(chats: ChatListViewModel(repository: ChatRepositoryStub(), media: nil))
        let share = social.shareProfile(mia)

        #expect(share.canShareInPace)
        #expect(share.friendRecipients.map(\.title) == ["Ben"])
        #expect(share.groupRecipients.map(\.title) == ["Klasse 8b"])
        #expect(!share.canSend)

        let group = try #require(share.groupRecipients.first)
        share.toggle(share.friendRecipients[0])
        share.toggle(group)
        #expect(share.canSend)
        #expect(Set(share.selectedTargets) == [.direct(ben), group.target])
        #expect(share.sendTitle == "An 2 Chats senden")
        share.toggle(group)
        #expect(share.selectedTargets == [.direct(ben)])
        #expect(share.sendTitle == "An 1 Chat senden")
        #expect(share.shareURL.absoluteString == "pace://u/mia")
        #expect(share.shareText == "Schau dir @mia bei Pace an")
    }

    @Test func withoutChatsOnlyTheLinkCanBeShared() async {
        let social = await make(chats: nil)
        let share = social.shareProfile(mia)
        share.toggle(share.friendRecipients[0])

        #expect(!share.canShareInPace)
        #expect(!share.canSend)
        #expect(await share.send() == false)
        #expect(!share.didSend)
    }

    @Test func aFailedShareIsExplainedHonestly() async {
        // Bis das Chat-Backend die Profilnachricht kann, meldet es „nicht eingerichtet“ – das wird nicht als Erfolg gezeigt.
        let social = await make(chats: ChatListViewModel(repository: ChatRepositoryStub(), media: nil))
        let share = social.shareProfile(mia)
        share.toggle(share.friendRecipients[0])

        let sent = await share.send()

        if sent {
            #expect(share.didSend)
            #expect(social.notice == .init(text: SocialText.profileShared, isError: false))
        } else {
            #expect(!share.didSend)
            #expect(share.errorMessage != nil)
            share.dismissError()
            #expect(share.errorMessage == nil)
        }
    }
}

@MainActor
struct ReportSettingsRankingTests {
    private let mia = SocialProfile(publicID: UUID(uuidString: "cdcdcdcd-0000-4000-8000-000000000001")!, username: "mia", displayName: "Mia")

    private func make(_ configure: @escaping (inout SocialRepositoryStub.State) -> Void = { _ in }) async -> (SocialViewModel, SocialRepositoryStub) {
        let repository = SocialRepositoryStub(configure: configure)
        let social = SocialViewModel(repository: repository, calendar: Fixtures.activityCalendar, now: { Fixtures.date(2026, 10, 16, 12) })
        await social.load()
        return (social, repository)
    }

    @Test func aReportNeedsAReasonAndTrimsTheDetails() async {
        let (social, repository) = await make()
        let report = social.reportForm(.user(mia))
        #expect(report.subject.title == "Nutzer melden")
        #expect(report.subject.subtitle == "Mia · @mia")
        #expect(!report.canSend)

        report.reason = .harassment
        report.details = "  beleidigende Nachrichten  "
        #expect(report.canSend)
        #expect(await report.send())

        #expect(report.didSend)
        let sent = repository.state.current.reports.first
        #expect(sent?.0 == .user(publicID: mia.publicID))
        #expect(sent?.1 == .harassment)
        #expect(sent?.2 == "beleidigende Nachrichten")
        #expect(social.notice?.isError == false)

        let group = social.reportForm(.group(id: UUID(), name: "Laufteam"))
        #expect(group.subject.title == "Gruppe melden")
        group.reason = .spam
        group.details = String(repeating: "x", count: ReportViewModel.maximumDetailsLength + 1)
        #expect(!group.canSend)
        #expect(group.remainingCharacters == -1)
    }

    @Test func aFailedReportIsNotShownAsSent() async {
        let (social, repository) = await make()
        repository.state.withLock { $0.actionError = .network }
        let report = social.reportForm(.group(id: UUID(), name: "Laufteam"))
        report.reason = .other

        #expect(await report.send() == false)
        #expect(!report.didSend)
        #expect(social.notice == .init(text: SocialError.network.message, isError: true))
    }

    @Test func blockedUsersCanBeUnblockedInTheSettings() async {
        let (social, repository) = await make { $0.blocked = [self.mia] }
        let settings = social.settings()

        await settings.load()
        #expect(settings.blocked == .loaded([mia]))

        #expect(await settings.unblock(mia))
        #expect(settings.blocked == .loaded([]))
        #expect(repository.state.current.blocked.isEmpty)
    }

    @Test func settingsAreHonestWithoutBackendAndOpenTheProfilePrivacy() async {
        let offline = SocialViewModel(repository: nil).settings()
        await offline.load()
        #expect(offline.blocked == .unavailable(SocialError.unavailable.message))

        let (social, repository) = await make()
        repository.state.withLock { $0.error = .unavailable }
        let settings = social.settings()
        await settings.load()
        #expect(settings.blocked == .unavailable(SocialText.featureUnavailable))

        #expect(!settings.canOpenPrivacySettings)
        var opened = false
        social.openPrivacySettings = { opened = true }
        #expect(settings.canOpenPrivacySettings)
        settings.openPrivacySettings()
        #expect(opened)
    }

    @Test func theFriendsRankingSwitchesBetweenTodayAndThisWeek() async {
        func entry(_ rank: Int, _ name: String, _ steps: Int, me: Bool = false) -> LeaderboardEntry {
            LeaderboardEntry(rank: rank, publicUserID: UUID(), username: name.lowercased(), displayName: name, competitionSteps: steps, isCurrentUser: me)
        }
        let today = [entry(1, "Mia", 9_000), entry(2, "Niklas", 8_000, me: true)]
        let week = [entry(1, "Niklas", 60_000, me: true), entry(2, "Mia", 52_000)]
        let (social, repository) = await make { state in
            state.ranking = today
            state.weeklyRanking = week
        }
        let ranking = social.friendsRanking()
        #expect(ranking.entries == today) // sofort aus dem geladenen Stand
        #expect(ranking.hasFriends)

        await ranking.select(.weekly)
        #expect(ranking.period == .weekly)
        #expect(ranking.entries == week)
        #expect(repository.state.current.friendRankingPeriods.last == .weekly)

        await ranking.select(.daily)
        #expect(ranking.entries == today)
    }
}
