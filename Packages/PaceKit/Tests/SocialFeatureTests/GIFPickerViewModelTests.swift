import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Anhangsauswahl im Chat: GIF-Suche mit echten Treffern (hier ein Stub), ehrlichen Zuständen und begrenztem Nachladen;
/// „Profil teilen“ aus dem Chat heraus.
@MainActor
struct GIFPickerViewModelTests {
    private final class SearchStub: GIFSearching, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [String] = []
        var pageSize = GIFRules.pageSize
        var error: GIFSearchError?
        var downloadError: GIFSearchError?
        var emptyFor: Set<String> = []

        var attribution: String { "Powered by Test" }
        var privacyNote: String { "Test" }

        var log: [String] { lock.withLock { calls } }

        private func page(_ prefix: String, offset: Int, limit: Int) -> [GIFSearchResult] {
            (offset..<(offset + min(limit, pageSize))).map { index in
                GIFSearchResult(
                    id: "\(prefix)-\(index)",
                    title: "\(prefix) \(index)",
                    stillURL: URL(string: "https://media.giphy.com/\(prefix)/\(index)_s.gif")!,
                    sendURL: URL(string: "https://media.giphy.com/\(prefix)/\(index).gif")!,
                    width: 480,
                    height: 270
                )
            }
        }

        func trending(limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult] {
            lock.withLock { calls.append("trending:\(offset)") }
            if let error { throw error }
            return page("trend", offset: offset, limit: limit)
        }

        func search(_ query: String, limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult] {
            lock.withLock { calls.append("search:\(query):\(offset)") }
            if let error { throw error }
            if emptyFor.contains(query) { return [] }
            return page(query, offset: offset, limit: limit)
        }

        func download(_ result: GIFSearchResult, maximumBytes: Int) async throws(GIFSearchError) -> Data {
            lock.withLock { calls.append("download:\(result.id)") }
            if let downloadError { throw downloadError }
            return Data("GIF89a-\(result.id)".utf8)
        }
    }

    @Test func withoutConfiguredSearchThePickerSaysSo() async {
        let picker = GIFPickerViewModel(search: nil)
        await picker.load()
        #expect(!picker.isAvailable)
        #expect(picker.phase == .failed(.notConfigured))
        #expect(picker.results.isEmpty)
        #expect(picker.attribution == nil)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(GIFPickerViewModel.message(for: .notConfigured).contains("nicht eingerichtet"))
        }
    }

    @Test func startsWithTrendingAndSearchesTheCleanedQuery() async {
        let search = SearchStub()
        let picker = GIFPickerViewModel(search: search)
        #expect(picker.phase == .loading)
        await picker.load()
        #expect(picker.phase == .loaded)
        #expect(picker.results.first?.id == "trend-0")
        #expect(picker.attribution == "Powered by Test")

        picker.query = "  laufen  "
        await picker.load()
        #expect(picker.results.first?.id == "laufen-0")
        // Gleicher Suchbegriff: keine neue Anfrage.
        await picker.load()
        #expect(search.log == ["trending:0", "search:laufen:0"])

        search.emptyFor = ["xyz"]
        picker.query = "xyz"
        await picker.load()
        #expect(picker.phase == .empty)
        #expect(picker.results.isEmpty)
    }

    @Test func failuresAreShownAndCanBeRetried() async {
        let search = SearchStub()
        search.error = .offline
        let picker = GIFPickerViewModel(search: search)
        await picker.load()
        #expect(picker.phase == .failed(.offline))
        search.error = nil
        await picker.load()
        #expect(picker.phase == .loaded)
    }

    @Test func loadingMoreIsPagedDeduplicatedAndCapped() async throws {
        let search = SearchStub()
        let picker = GIFPickerViewModel(search: search)
        await picker.load()
        // Nicht am Ende des Rasters: nichts nachladen.
        await picker.loadMoreIfNeeded(after: picker.results[0])
        #expect(picker.results.count == GIFRules.pageSize)

        for _ in 0..<10 {
            guard let last = picker.results.last else { break }
            await picker.loadMoreIfNeeded(after: last)
        }
        #expect(picker.results.count == GIFRules.maximumResults)
        #expect(Set(picker.results.map(\.id)).count == picker.results.count)
        let requests = search.log.filter { $0.hasPrefix("trending") }.count
        #expect(requests == GIFRules.maximumResults / GIFRules.pageSize)
    }

    @Test func choosingAGIFDownloadsItForThePreview() async throws {
        let search = SearchStub()
        let picker = GIFPickerViewModel(search: search)
        await picker.load()
        let gif = try #require(picker.results.first)
        await picker.select(gif)
        #expect(picker.selection?.result == gif)
        #expect(picker.dataToSend == Data("GIF89a-trend-0".utf8))
        picker.clearSelection()
        #expect(picker.dataToSend == nil)

        search.downloadError = .unsuitableFile
        await picker.select(gif)
        #expect(picker.selection?.error == .unsuitableFile)
        #expect(picker.dataToSend == nil)
    }

    @Test func profilesCanBeSharedFromTheChat() async throws {
        let known = ChatFixtures.direct(peer: ChatFixtures.leon)
        let repository = ChatRepositoryStub { $0.conversations = [known] }
        let list = ChatListViewModel(repository: repository, media: nil, calendar: Fixtures.activityCalendar)
        list.shareableProfiles = { [ChatFixtures.mia, ChatFixtures.gotscha] }
        await list.load()
        let chat = list.chat(for: .direct(ChatFixtures.leon))
        await chat.load()
        #expect(chat.shareableProfiles == [ChatFixtures.mia, ChatFixtures.gotscha])

        await chat.shareProfile(ChatFixtures.gotscha)

        let sent = repository.state.withLock { $0.sentDrafts }
        #expect(sent.count == 1)
        #expect(sent.first?.0.kind == .profile)
        #expect(sent.first?.0.sharedProfileID == ChatFixtures.gotscha.publicID)
        #expect(sent.first?.1 == known.id)
        #expect(chat.notice == nil)
    }

    @Test func gifRules() {
        #expect(GIFRules.query("   ") == nil)
        #expect(GIFRules.query(" happy\n dance ") == "happy dance")
        #expect(GIFRules.query(String(repeating: "a", count: 80))?.count == GIFRules.maximumQueryLength)
        #expect(GIFRules.isGIF(Data("GIF87a...".utf8)))
        #expect(!GIFRules.isGIF(Data("\u{89}PNG".utf8)))
    }
}
