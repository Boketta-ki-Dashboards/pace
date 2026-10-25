import Foundation
@testable import PaceBackend
import PaceCore
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GIF-Suche über GIPHY: Schlüssel nur aus der Konfiguration, jugendfreie Treffer in der App-Sprache, nur GIPHY-Links,
/// geprüfte Dateien, ehrliche Fehler.
struct GIPHYSearchServiceTests {
    private static let gif = Data("GIF89a".utf8) + Data(repeating: 0, count: 64)

    private static let sample = Data("""
    {"data":[
      {"type":"gif","id":"abc","title":"Laufen GIF",
       "images":{
         "fixed_width_still":{"url":"https://media2.giphy.com/media/abc/200w_s.gif","width":"200","height":"112"},
         "fixed_width":{"url":"https://media2.giphy.com/media/abc/200w.gif","width":"200","height":"112","size":"450000"},
         "downsized":{"url":"https://media2.giphy.com/media/abc/giphy-downsized.gif","width":"480","height":"270","size":"1500000"}
       }},
      {"type":"gif","id":"big","title":"Zu groß",
       "images":{
         "fixed_width_still":{"url":"https://media1.giphy.com/media/big/200w_s.gif","width":"200","height":"200"},
         "fixed_width":{"url":"https://media1.giphy.com/media/big/200w.gif","width":"200","height":"200","size":"900000"},
         "downsized":{"url":"https://media1.giphy.com/media/big/giphy-downsized.gif","width":"480","height":"480","size":"12000000"}
       }},
      {"type":"gif","id":"evil","title":"Fremder Link",
       "images":{
         "fixed_width_still":{"url":"https://example.com/still.gif","width":"200","height":"200"},
         "downsized":{"url":"http://media.giphy.com/insecure.gif","width":"480","height":"480","size":"1000"}
       }}
    ],"pagination":{"total_count":3,"count":3,"offset":0},"meta":{"status":200,"msg":"OK"}}
    """.utf8)

    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { stored } }
        func append(_ request: URLRequest) { lock.withLock { stored.append(request) } }
    }

    private static func service(
        status: Int = 200,
        body: Data = sample,
        error: URLError? = nil,
        log: RequestLog = RequestLog()
    ) -> GIPHYSearchService {
        GIPHYSearchService(apiKey: "testKey123", language: { "ru" }) { request in
            log.append(request)
            if let error { throw error }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }!
    }

    @Test func withoutAKeyThereIsNoSearch() {
        #expect(GIPHYSearchService(apiKey: nil) == nil)
        #expect(GIPHYSearchService(apiKey: "") == nil)
        #expect(GIPHYSearchService(apiKey: "  ") == nil)
        // Nicht ersetzte Build-Variable (kein Pace.xcconfig-Eintrag).
        #expect(GIPHYSearchService(apiKey: "$(GIPHY_API_KEY)") == nil)
        #expect(GIPHYSearchService(apiKey: "key with spaces") == nil)
        #expect(GIPHYSearchService.fromInfoDictionary([:]) == nil)
        #expect(GIPHYSearchService.fromInfoDictionary([GIPHYSearchService.infoKey: "abcDEF123"]) != nil)
    }

    @Test func searchAsksForFamilyFriendlyResultsInTheAppLanguage() async throws {
        let log = RequestLog()
        let results = try await Self.service(log: log).search("  laufen   schnell ", limit: 30, offset: 60)
        let url = try #require(log.requests.first?.url)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host == "api.giphy.com")
        #expect(url.path == "/v1/gifs/search")
        #expect(items["q"] == "laufen schnell")
        #expect(items["rating"] == "pg")
        #expect(items["lang"] == "ru")
        #expect(items["limit"] == "30")
        #expect(items["offset"] == "60")
        #expect(items["api_key"] == "testKey123")
        #expect(results.map(\.id) == ["abc", "big"])
    }

    @Test func emptySearchShowsTrending() async throws {
        let log = RequestLog()
        _ = try await Self.service(log: log).search("   ", limit: 10, offset: 0)
        #expect(log.requests.first?.url?.path == "/v1/gifs/trending")
    }

    @Test func resultsUseSmallStillsAndASendableFileFromGIPHYOnly() throws {
        let results = try GIPHYSearchService.parse(Self.sample)
        let first = try #require(results.first)
        #expect(first.stillURL.absoluteString == "https://media2.giphy.com/media/abc/200w_s.gif")
        #expect(first.sendURL.absoluteString == "https://media2.giphy.com/media/abc/giphy-downsized.gif")
        #expect(first.width == 480 && first.height == 270)
        // Zu große „downsized“-Datei: die kleinere Fassung wird gesendet.
        #expect(results[1].sendURL.absoluteString == "https://media1.giphy.com/media/big/200w.gif")
        // Fremde oder unverschlüsselte Links fallen weg.
        #expect(!results.contains { $0.id == "evil" })
        #expect(!GIPHYSearchService.isAllowedMediaURL(URL(string: "https://giphy.com.evil.example/a.gif")!))
        #expect(GIPHYSearchService.isAllowedMediaURL(URL(string: "https://i.giphy.com/a.gif")!))
    }

    @Test func errorsAreHonest() async {
        await #expect(throws: GIFSearchError.notConfigured) { try await Self.service(status: 403).trending(limit: 5, offset: 0) }
        await #expect(throws: GIFSearchError.rateLimited) { try await Self.service(status: 429).trending(limit: 5, offset: 0) }
        await #expect(throws: GIFSearchError.failed) { try await Self.service(status: 500).trending(limit: 5, offset: 0) }
        await #expect(throws: GIFSearchError.offline) {
            try await Self.service(error: URLError(.notConnectedToInternet)).search("a", limit: 5, offset: 0)
        }
        await #expect(throws: GIFSearchError.failed) { try await Self.service(body: Data("kein json".utf8)).trending(limit: 5, offset: 0) }
    }

    @Test func downloadAcceptsOnlyGIFsWithinTheChatLimit() async throws {
        let result = try #require(try GIPHYSearchService.parse(Self.sample).first)
        let data = try await Self.service(body: Self.gif).download(result, maximumBytes: MediaRules.maximumChatBytes)
        #expect(data == Self.gif)

        await #expect(throws: GIFSearchError.unsuitableFile) {
            try await Self.service(body: Data("<html>".utf8)).download(result, maximumBytes: MediaRules.maximumChatBytes)
        }
        await #expect(throws: GIFSearchError.unsuitableFile) {
            try await Self.service(body: Self.gif).download(result, maximumBytes: 10)
        }
        let foreign = GIFSearchResult(
            id: "x",
            title: "",
            stillURL: URL(string: "https://example.com/s.gif")!,
            sendURL: URL(string: "https://example.com/a.gif")!,
            width: 1,
            height: 1
        )
        let log = RequestLog()
        await #expect(throws: GIFSearchError.unsuitableFile) {
            try await Self.service(body: Self.gif, log: log).download(foreign, maximumBytes: MediaRules.maximumChatBytes)
        }
        // Fremde Links werden gar nicht erst geladen.
        #expect(log.requests.isEmpty)
    }
}
