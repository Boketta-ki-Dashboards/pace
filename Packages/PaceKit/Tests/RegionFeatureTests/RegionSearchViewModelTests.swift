import Foundation
import PaceCore
import PaceTestSupport
import RegionFeature
import Testing

@MainActor
struct RegionSearchViewModelTests {
    private func makeViewModel(_ regions: RegionRepositoryStub = RegionRepositoryStub(), debounce: Duration = .zero) -> RegionSearchViewModel {
        RegionSearchViewModel(regions: regions, debounce: debounce)
    }

    @Test func startsIdleWithoutSelection() {
        let viewModel = makeViewModel()

        #expect(viewModel.state == .idle)
        #expect(viewModel.selection == nil)
    }

    @Test func tooShortQueryStaysIdleWithoutRequest() async {
        let regions = RegionRepositoryStub()
        let viewModel = makeViewModel(regions)

        await viewModel.search(" P ")

        #expect(viewModel.state == .idle)
        #expect(regions.state.current.searchQueries.isEmpty)
    }

    @Test func showsResultsForNormalizedQuery() async {
        let regions = RegionRepositoryStub()
        let viewModel = makeViewModel(regions)

        await viewModel.search("  pfung ")

        #expect(viewModel.state == .results([Fixtures.pfungstadtHierarchy]))
        #expect(regions.state.current.searchQueries == ["pfung"])
    }

    @Test func showsNoResults() async {
        let viewModel = makeViewModel()

        await viewModel.search("Atlantis")

        #expect(viewModel.state == .noResults(query: "Atlantis"))
    }

    @Test func networkErrorShowsMessageAndRetryRecovers() async {
        let regions = RegionRepositoryStub { $0.error = .network }
        let viewModel = makeViewModel(regions)

        await viewModel.search("Berlin")
        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected failed state, got \(viewModel.state)")
            return
        }
        #expect(message.contains("Verbindung"))

        regions.state.withLock { $0.error = nil }
        await viewModel.retry()

        #expect(viewModel.state == .results([Fixtures.berlinHierarchy]))
    }

    @Test func rapidTypingOnlySearchesTheLatestQuery() async throws {
        let regions = RegionRepositoryStub()
        // Großzügige Wartezeit, damit der Abbruch auch auf einer ausgelasteten CI sicher davor liegt.
        let viewModel = makeViewModel(regions, debounce: .milliseconds(500))

        // Wie `.task(id:)`: Jede neue Eingabe bricht die vorige Suche ab.
        let first = Task { await viewModel.search("Fra") }
        try await Task.sleep(for: .milliseconds(10))
        first.cancel()
        let second = Task { await viewModel.search("Frankfurt") }
        await first.value
        await second.value

        #expect(regions.state.current.searchQueries == ["Frankfurt"])
        #expect(viewModel.state == .results([Fixtures.frankfurtHierarchy]))
    }

    @Test func overtakenSearchDoesNotOverwriteNewerResult() async throws {
        let regions = RegionRepositoryStub()
        let viewModel = makeViewModel(regions, debounce: .milliseconds(300))

        // Die ältere Suche startet sicher zuerst und wartet noch, wenn die neuere beginnt.
        let older = Task { await viewModel.search("Griesheim") }
        try await Task.sleep(for: .milliseconds(50))
        let newer = Task { await viewModel.search("Pfungstadt") }
        await older.value
        await newer.value

        #expect(viewModel.state == .results([Fixtures.pfungstadtHierarchy]))
    }

    @Test func clearingTheQueryReturnsToIdle() async {
        let viewModel = makeViewModel()
        await viewModel.search("Berlin")

        await viewModel.search("")

        #expect(viewModel.state == .idle)
    }

    @Test func selectionIsKeptAndCanBeCleared() async {
        let viewModel = makeViewModel()
        await viewModel.search("Pfungstadt")

        viewModel.select(Fixtures.pfungstadtHierarchy)
        await viewModel.search("Berlin")

        #expect(viewModel.selection == Fixtures.pfungstadtHierarchy)
        viewModel.clearSelection()
        #expect(viewModel.selection == nil)
    }
}
