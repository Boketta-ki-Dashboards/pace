import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

@MainActor
struct FriendSearchViewModelTests {
    private let leon = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!, username: "leon_fischer", displayName: "Leon Fischer")
    private let leona = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000002")!, username: "leona_w", displayName: "Leona Weber")
    private let leo = SocialProfile(publicID: UUID(uuidString: "cccccccc-0000-4000-8000-000000000003")!, username: "leo", displayName: "Leo Müller")

    private func make(
        debounce: Duration = .milliseconds(20),
        configure: @escaping (inout SocialRepositoryStub.State) -> Void = { _ in }
    ) async -> (FriendSearchViewModel, SocialViewModel, SocialRepositoryStub) {
        let repository = SocialRepositoryStub { state in
            state.searchableProfiles = [self.leon, self.leona, self.leo]
            configure(&state)
        }
        let social = SocialViewModel(
            repository: repository,
            ownUsername: { "niklas" },
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 12) }
        )
        await social.load()
        let search = social.friendSearch(debounce: debounce)!
        return (search, social, repository)
    }

    private func searchCalls(_ repository: SocialRepositoryStub) -> [String] {
        repository.state.current.calls.filter { $0.hasPrefix("searchProfiles:") }
    }

    @Test func typingSearchesOnceAfterAPauseWithTheLastText() async throws {
        let (search, _, repository) = await make(debounce: .milliseconds(80))

        search.query = "l"
        search.query = "le"
        search.query = "leo"
        search.query = "  @leon"
        #expect(searchCalls(repository).isEmpty) // noch keine Pause

        try await waitUntil { if case .results = search.state { true } else { false } }
        #expect(searchCalls(repository) == ["searchProfiles:leon"])
        #expect(search.results.map(\.profile) == [leon, leona])
    }

    @Test func shortOrInvalidTextIsNotSentToTheServer() async throws {
        let (search, _, repository) = await make()

        search.query = "le"
        #expect(search.state == .idle)
        #expect(search.hint != nil)

        search.query = "le o"
        #expect(search.state == .empty(SocialText.nobodyStartsWith("le o")))

        search.query = ""
        #expect(search.state == .idle)
        try await Task.sleep(for: .milliseconds(60))
        #expect(searchCalls(repository).isEmpty)
    }

    @Test func emptyResultsAndErrorsAreShown() async throws {
        let (search, _, repository) = await make()

        search.query = "zzz"
        await search.searchNow()
        #expect(search.state == .empty("Niemand gefunden, dessen Benutzername mit „zzz“ beginnt."))

        repository.state.withLock { $0.error = .rateLimited }
        search.query = "leo"
        await search.searchNow()
        #expect(search.state == .failed(SocialError.rateLimited.message))
    }

    @Test func onlyTheNewestAnswerIsShown() async throws {
        let (search, _, repository) = await make(debounce: .seconds(10))
        repository.gate.close("searchProfiles")

        search.query = "leo"
        let first = Task { await search.searchNow() }
        try await waitUntil { repository.gate.waitingCount("searchProfiles") == 1 }
        search.query = "leona"
        let second = Task { await search.searchNow() }
        try await waitUntil { repository.gate.waitingCount("searchProfiles") == 2 }

        repository.gate.open("searchProfiles")
        await first.value
        await second.value

        #expect(search.results.map(\.profile) == [leona])
    }

    @Test func addingSendsARequestAndShowsTheNewState() async throws {
        let (search, social, repository) = await make()
        search.query = "leo"
        await search.searchNow()
        let result = try #require(search.results.first { $0.profile == leo })
        #expect(result.relationship == .none)

        #expect(await search.add(result))

        #expect(repository.state.current.calls.contains("sendFriendRequest"))
        #expect(search.results.first { $0.profile == leo }?.relationship == .outgoingRequest)
        #expect(social.notice == .init(text: "Anfrage an Leo Müller gesendet.", isError: false))
        #expect(social.busyIDs.isEmpty)
    }

    @Test func anIncomingRequestCanBeAcceptedFromTheResults() async throws {
        let requestID = UUID()
        let (search, social, _) = await make { state in
            state.relationships[self.leon.publicID] = .incomingRequest
            state.requests = [FriendRequest(id: requestID, direction: .incoming, profile: self.leon, createdAt: .distantPast)]
        }
        search.query = "leon"
        await search.searchNow()
        let result = try #require(search.results.first { $0.profile == leon })
        #expect(result.relationship == .incomingRequest)
        #expect(search.requestID(for: result) == requestID) // aus den geladenen Anfragen

        #expect(await search.accept(result))

        #expect(social.friends.map(\.profile) == [leon])
        #expect(social.incomingRequests.isEmpty)
    }

    @Test func blockingRemovesThePersonAndMessagesNeedAFriendship() async throws {
        let (search, social, repository) = await make { state in
            state.relationships[self.leona.publicID] = .friend
        }
        search.query = "leo"
        await search.searchNow()
        let friend = try #require(search.results.first { $0.profile == leona })
        let stranger = try #require(search.results.first { $0.profile == leo })

        #expect(search.chatTarget(for: friend) == .direct(leona))
        #expect(search.chatTarget(for: stranger) == nil)

        #expect(await search.block(stranger))
        #expect(!search.results.contains { $0.profile == leo })
        #expect(repository.state.current.blocked == [leo])
        #expect(social.notice?.isError == false)
    }

    @Test func textsAreTranslated() {
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(SocialText.nobodyStartsWith("zzz").contains("zzz"))
            #expect(SocialText.add == "Add")
            #expect(SocialText.alreadyFriends == "Already friends")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(SocialText.add == "Добавить")
            #expect(SocialText.requestSent == "Заявка отправлена")
        }
    }
}
