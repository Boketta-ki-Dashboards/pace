import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct LeaderboardLoaderTests {
    private let query = LeaderboardQuery(regionID: Fixtures.pfungstadt.id, period: .daily, date: Fixtures.day(2026, 10, 16))

    private func makeLoader(_ ranking: [LeaderboardEntry], topLimit: Int = 50) -> (LeaderboardLoader, LeaderboardRepositoryStub) {
        let repository = LeaderboardRepositoryStub { $0.rankings[Fixtures.pfungstadt.id] = ranking }
        return (LeaderboardLoader(repository: repository, topLimit: topLimit, neighborRadius: 1), repository)
    }

    @Test func currentUserInTopNeedsNoNeighborhoodRequest() async throws {
        let (loader, repository) = makeLoader(Fixtures.ranking(count: 10, currentUserRank: 3))

        let snapshot = try await loader.load(query)

        #expect(snapshot.entries.count == 10)
        #expect(snapshot.currentUserEntry?.rank == 3)
        #expect(snapshot.rows.allSatisfy { if case .entry = $0 { true } else { false } })
        #expect(repository.state.current.neighborhoodRequests.isEmpty)
        #expect(repository.state.current.pageRequests.map(\.limit) == [50])
    }

    @Test func loadMoreAppendsNextPageAndKeepsOwnPosition() async throws {
        let (loader, repository) = makeLoader(Fixtures.ranking(count: 30, currentUserRank: 25), topLimit: 10)
        let first = try await loader.load(query)
        #expect(first.loadedTopCount == 10)
        #expect(first.canLoadMore)

        let second = try await loader.loadMore(after: first)

        #expect(repository.state.current.pageRequests.last?.offset == 10)
        #expect(second.loadedTopCount == 20)
        #expect(second.rows.contains(.gap(afterRank: 20)))
        #expect(second.entries.suffix(3).map(\.rank) == [24, 25, 26])
        #expect(second.currentUserEntry?.rank == 25)
        #expect(second.canLoadMore)
    }

    @Test func loadMoreClosesTheGapToOwnPosition() async throws {
        let (loader, _) = makeLoader(Fixtures.ranking(count: 30, currentUserRank: 15), topLimit: 10)
        let first = try await loader.load(query)
        #expect(first.rows.contains(.gap(afterRank: 10)))

        let second = try await loader.loadMore(after: first)

        #expect(!second.rows.contains { if case .gap = $0 { true } else { false } })
        #expect(second.entries.map(\.rank) == Array(1...20))
        #expect(Set(second.entries.map(\.publicUserID)).count == second.entries.count)
    }

    @Test func nothingMoreToLoadWhenEverythingIsShown() async throws {
        let (loader, _) = makeLoader(Fixtures.ranking(count: 8, currentUserRank: 2), topLimit: 10)

        let snapshot = try await loader.load(query)

        #expect(!snapshot.canLoadMore)
    }

    @Test func currentUserBelowTopIsAppendedWithNeighborsAndGap() async throws {
        let (loader, _) = makeLoader(Fixtures.ranking(count: 500, currentUserRank: 383))

        let snapshot = try await loader.load(query)

        let ranks = snapshot.entries.map(\.rank)
        #expect(ranks.prefix(50) == ArraySlice(1...50))
        #expect(ranks.suffix(3) == [382, 383, 384])
        #expect(snapshot.rows[50] == .gap(afterRank: 50))
        #expect(snapshot.currentUserEntry?.rank == 383)
        #expect(snapshot.totalParticipants == 500)
    }

    @Test func noGapWhenCurrentUserDirectlyFollowsTop() async throws {
        let (loader, _) = makeLoader(Fixtures.ranking(count: 60, currentUserRank: 52))

        let snapshot = try await loader.load(query)

        #expect(!snapshot.rows.contains(.gap(afterRank: 50)))
        #expect(snapshot.entries.map(\.rank).suffix(3) == [51, 52, 53])
    }

    @Test func neighborsInsideTopAreNotDuplicated() async throws {
        let (loader, _) = makeLoader(Fixtures.ranking(count: 60, currentUserRank: 51))

        let snapshot = try await loader.load(query)

        #expect(snapshot.entries.map(\.rank) == Array(1...52))
    }

    @Test func userNotInRankingShowsTopOnly() async throws {
        let (loader, repository) = makeLoader(Fixtures.ranking(count: 80))

        let snapshot = try await loader.load(query)

        #expect(snapshot.entries.count == 50)
        #expect(snapshot.currentUserEntry == nil)
        #expect(repository.state.current.neighborhoodRequests.count == 1)
    }

    @Test func emptyRanking() async throws {
        let (loader, _) = makeLoader([])

        let snapshot = try await loader.load(query)

        #expect(snapshot.isEmpty)
        #expect(snapshot.rows.isEmpty)
        #expect(!snapshot.isCurrentUserAlone)
    }

    @Test func currentUserAloneInRanking() async throws {
        let (loader, _) = makeLoader(Fixtures.ranking(count: 1, currentUserRank: 1))

        let snapshot = try await loader.load(query)

        #expect(snapshot.isCurrentUserAlone)
    }

    @Test func pageReportsWhetherMoreEntriesExist() {
        let page = LeaderboardPage(entries: Fixtures.ranking(count: 50), totalParticipants: 51, offset: 0, limit: 50)
        let last = LeaderboardPage(entries: Fixtures.ranking(count: 1), totalParticipants: 51, offset: 50, limit: 50)

        #expect(page.hasMore)
        #expect(!last.hasMore)
    }

    @Test func propagatesErrors() async {
        let repository = LeaderboardRepositoryStub { $0.error = .network }
        let loader = LeaderboardLoader(repository: repository)

        await #expect(throws: LeaderboardError.network) {
            try await loader.load(query)
        }
    }

    @Test func periodsAreDailyAndWeekly() {
        #expect(LeaderboardPeriod.allCases == [.daily, .weekly])
        #expect(LeaderboardPeriod.weekly.rawValue == "weekly")
    }
}
