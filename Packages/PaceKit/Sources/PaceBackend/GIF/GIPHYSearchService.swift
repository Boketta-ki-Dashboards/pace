import Foundation
import PaceCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GIF-Suche über die GIPHY-API (developers.giphy.com).
///
/// - Der API-Schlüssel kommt aus `Config/Pace.xcconfig` (`GIPHY_API_KEY`, von Git ignoriert) über die Info.plist
///   (`PaceGIPHYAPIKey`). Ohne Schlüssel gibt es keine Suche – die App sagt das ehrlich, statt Platzhalter zu zeigen.
/// - Nur jugendfreie Inhalte (`rating=pg`), Sprache der App.
/// - Geladen wird ausschließlich über HTTPS von GIPHY-Hosts; die Datei wird geprüft (GIF, Größengrenze des Chats) und
///   dann wie ein GIF aus der Mediathek in den geschützten Chat-Speicher hochgeladen.
public struct GIPHYSearchService: GIFSearching {
    public static let infoKey = "PaceGIPHYAPIKey"
    static let baseURL = URL(string: "https://api.giphy.com/v1/gifs")!
    static let rating = "pg"

    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let apiKey: String
    private let load: Loader
    private let language: @Sendable () -> String

    /// `nil` ohne gültigen Schlüssel (leer oder nicht ersetzte Build-Variable).
    public init?(
        apiKey: String?,
        language: @escaping @Sendable () -> String = { PaceLocalization.shared.effectiveLanguage.rawValue },
        load: @escaping Loader = { try await URLSession.shared.data(for: $0) }
    ) {
        guard let key = ConfigurationValue.cleaned(apiKey), key.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        self.apiKey = key
        self.language = language
        self.load = load
    }

    /// Aus der Info.plist der App; `nil`, wenn kein Schlüssel eingetragen ist.
    public static func fromInfoDictionary(_ info: [String: Any]) -> GIPHYSearchService? {
        GIPHYSearchService(apiKey: info[infoKey] as? String)
    }

    public var attribution: String { "Powered by GIPHY" }

    public var privacyNote: String {
        PaceLocalization.text(
            de: "Suchbegriffe gehen an GIPHY. Gesendet wird eine Kopie des GIFs – nur für diesen Chat sichtbar.",
            en: "Search terms are sent to GIPHY. A copy of the GIF is sent – visible only in this chat.",
            ru: "Поисковые запросы передаются GIPHY. Отправляется копия GIF – её видят только участники чата."
        )
    }

    public func trending(limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult] {
        try await fetch("trending", query: nil, limit: limit, offset: offset)
    }

    public func search(_ query: String, limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult] {
        guard let cleaned = GIFRules.query(query) else {
            return try await trending(limit: limit, offset: offset)
        }
        return try await fetch("search", query: cleaned, limit: limit, offset: offset)
    }

    public func download(_ result: GIFSearchResult, maximumBytes: Int) async throws(GIFSearchError) -> Data {
        guard Self.isAllowedMediaURL(result.sendURL) else { throw .unsuitableFile }
        var request = URLRequest(url: result.sendURL)
        request.timeoutInterval = 30
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(request)
        } catch {
            throw Self.map(error)
        }
        try Self.check(response)
        guard data.count <= maximumBytes, GIFRules.isGIF(data) else { throw .unsuitableFile }
        return data
    }

    // MARK: Anfrage

    func request(_ endpoint: String, query: String?, limit: Int, offset: Int) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "offset", value: String(max(offset, 0))),
            URLQueryItem(name: "rating", value: Self.rating),
        ]
        if let query {
            items.append(URLQueryItem(name: "q", value: query))
            items.append(URLQueryItem(name: "lang", value: language()))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        return request
    }

    private func fetch(_ endpoint: String, query: String?, limit: Int, offset: Int) async throws(GIFSearchError) -> [GIFSearchResult] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(request(endpoint, query: query, limit: limit, offset: offset))
        } catch {
            throw Self.map(error)
        }
        try Self.check(response)
        return try Self.parse(data)
    }

    // MARK: Antwort

    static func check(_ response: URLResponse) throws(GIFSearchError) {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw .notConfigured
        case 429: throw .rateLimited
        default: throw .failed
        }
    }

    static func map(_ error: any Error) -> GIFSearchError {
        guard let urlError = error as? URLError else { return .failed }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        default:
            return .failed
        }
    }

    /// Nur HTTPS von GIPHY (`giphy.com` und Subdomains wie `media2.giphy.com`).
    static func isAllowedMediaURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "giphy.com" || host.hasSuffix(".giphy.com")
    }

    /// Ergebnisse ohne verwertbare Dateien (fehlende oder fremde Links, zu große Dateien) werden übersprungen.
    static func parse(_ data: Data) throws(GIFSearchError) -> [GIFSearchResult] {
        let response: SearchResponse
        do {
            response = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw .failed
        }
        return response.data.compactMap { item in
            guard let images = item.images,
                  let still = images.fixedWidthStill?.link ?? images.downsizedStill?.link,
                  let send = images.sendRendition,
                  let sendURL = send.link
            else { return nil }
            return GIFSearchResult(
                id: item.id,
                title: item.title ?? "",
                stillURL: still,
                sendURL: sendURL,
                width: send.pixelWidth,
                height: send.pixelHeight
            )
        }
    }

    // MARK: DTOs (Zahlen kommen bei GIPHY als Texte)

    struct SearchResponse: Decodable {
        let data: [Item]
    }

    struct Item: Decodable {
        let id: String
        let title: String?
        let images: Images?
    }

    struct Images: Decodable {
        let fixedWidthStill: Rendition?
        let downsizedStill: Rendition?
        let fixedWidth: Rendition?
        let downsized: Rendition?

        enum CodingKeys: String, CodingKey {
            case fixedWidthStill = "fixed_width_still"
            case downsizedStill = "downsized_still"
            case fixedWidth = "fixed_width"
            case downsized
        }

        /// „downsized“ (unter 2 MB, gute Auflösung für Chat-Blasen), sonst „fixed_width“ (200 px breit).
        var sendRendition: Rendition? {
            [downsized, fixedWidth].compactMap { $0 }.first { rendition in
                rendition.link != nil && (rendition.bytes ?? 0) <= MediaRules.maximumChatBytes
            }
        }
    }

    struct Rendition: Decodable {
        let url: String?
        let width: String?
        let height: String?
        let size: String?

        /// Nur zulässige Links (HTTPS, GIPHY).
        var link: URL? {
            guard let url, let parsed = URL(string: url), GIPHYSearchService.isAllowedMediaURL(parsed) else { return nil }
            return parsed
        }

        var pixelWidth: Int { width.flatMap { Int($0) } ?? 0 }
        var pixelHeight: Int { height.flatMap { Int($0) } ?? 0 }
        var bytes: Int? { size.flatMap { Int($0) } }
    }
}
