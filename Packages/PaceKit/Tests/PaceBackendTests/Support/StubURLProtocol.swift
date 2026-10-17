import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceTestSupport
import Testing

/// Eine vom Stub empfangene Anfrage.
struct RecordedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = request.url!
        headers = request.allHTTPHeaderFields ?? [:]
        body = request.httpBody ?? request.httpBodyStream.map(Self.read)
    }

    var path: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
    }

    var host: String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? ""
    }

    /// Dekodierter Wert eines Query-Parameters.
    func query(_ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    /// Header-Wert, ohne Beachtung der Groß-/Kleinschreibung des Namens.
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Einträge im `Prefer`-Header, z. B. `return=minimal`.
    var preferences: Set<String> {
        Set((header("Prefer") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    func jsonBody() throws -> JSONValue {
        let data = try #require(body, "Anfrage ohne Body")
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func read(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Antwort des Stubs: HTTP-Antwort oder Netzwerkfehler.
enum StubOutcome: Sendable {
    case response(status: Int, headers: [String: String], body: Data)
    case failure(URLError)

    /// JSON-Antwort, standardmäßig `200`.
    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> StubOutcome {
        var allHeaders = ["Content-Type": "application/json; charset=utf-8"]
        allHeaders.merge(headers) { _, new in new }
        return .response(status: status, headers: allHeaders, body: Data(body.utf8))
    }

    /// Fehlerantwort von PostgREST im Originalformat.
    static func postgrestError(
        status: Int,
        code: String,
        message: String,
        details: String? = nil
    ) -> StubOutcome {
        let detailsJSON = details.map { "\"\($0)\"" } ?? "null"
        return json(
            #"{"code":"\#(code)","details":\#(detailsJSON),"hint":null,"message":"\#(message)"}"#,
            status: status
        )
    }
}

typealias StubHandler = @Sendable (RecordedRequest) -> StubOutcome

/// Handler je Host. Jeder Test verwendet einen eigenen Host, damit parallele Tests sich nicht stören.
enum StubRegistry {
    private static let handlers = Locked<[String: StubHandler]>([:])

    static func register(host: String, handler: @escaping StubHandler) {
        handlers.withLock { $0[host] = handler }
    }

    static func unregister(host: String) {
        handlers.withLock { $0[host] = nil }
    }

    static func handler(for host: String) -> StubHandler? {
        handlers.withLock { $0[host] }
    }
}

/// Beantwortet alle Anfragen einer `URLSession` über `StubRegistry`.
final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = RecordedRequest(request)
        guard let handler = StubRegistry.handler(for: recorded.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch handler(recorded) {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: recorded.url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
