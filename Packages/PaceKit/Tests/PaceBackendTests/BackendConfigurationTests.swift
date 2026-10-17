import Foundation
import PaceBackend
import Testing

struct BackendConfigurationTests {
    private func parse(url: String?, key: String? = "sb_publishable_abc123") throws(BackendConfigurationError) -> BackendConfiguration {
        var info: [String: Any] = [:]
        if let url { info[BackendConfiguration.urlInfoKey] = url }
        if let key { info[BackendConfiguration.publishableKeyInfoKey] = key }
        return try BackendConfiguration.fromInfoDictionary(info)
    }

    @Test func acceptsHostWithoutSchemeAndAddsHTTPS() throws {
        let configuration = try parse(url: "bnkrenfvfiaapsbkeejq.supabase.co")

        #expect(configuration.supabaseURL.absoluteString == "https://bnkrenfvfiaapsbkeejq.supabase.co")
        #expect(configuration.projectRef == "bnkrenfvfiaapsbkeejq")
        #expect(configuration.publishableKey == "sb_publishable_abc123")
    }

    @Test(arguments: ["https://bnkrenfvfiaapsbkeejq.supabase.co", "https://bnkrenfvfiaapsbkeejq.supabase.co/", "  bnkrenfvfiaapsbkeejq.supabase.co  "])
    func acceptsFullURLAndSurroundingWhitespace(_ url: String) throws {
        #expect(try parse(url: url).supabaseURL.absoluteString == "https://bnkrenfvfiaapsbkeejq.supabase.co")
    }

    @Test(arguments: ["https:", "http:", "HTTPS:"])
    func detectsURLTruncatedByXcconfigComment(_ url: String) {
        #expect(throws: BackendConfigurationError.urlTruncatedByXcconfigComment) { try parse(url: url) }
    }

    @Test(arguments: [nil, "", "   ", "$(SUPABASE_URL)"] as [String?])
    func missingURL(_ url: String?) {
        #expect(throws: BackendConfigurationError.missingURL) { try parse(url: url) }
    }

    @Test(arguments: [nil, "", "$(SUPABASE_PUBLISHABLE_KEY)"] as [String?])
    func missingKey(_ key: String?) {
        #expect(throws: BackendConfigurationError.missingKey) { try parse(url: "abc.supabase.co", key: key) }
    }

    @Test func rejectsPlaceholders() {
        #expect(throws: BackendConfigurationError.placeholderValues) { try parse(url: "example.supabase.co") }
        #expect(throws: BackendConfigurationError.placeholderValues) {
            try parse(url: "abc.supabase.co", key: "sb_publishable_example")
        }
    }

    @Test func rejectsSecretKey() {
        #expect(throws: BackendConfigurationError.secretKeyNotAllowed) {
            try parse(url: "abc.supabase.co", key: "sb_secret_abcdefghijklmnop")
        }
    }

    @Test func rejectsLegacyServiceRoleKeyButAcceptsLegacyAnonKey() throws {
        func jwt(role: String) -> String {
            let payload = Data(#"{"iss":"supabase","role":"\#(role)"}"#.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
            return "eyJhbGciOiJIUzI1NiJ9.\(payload).signature"
        }

        #expect(throws: BackendConfigurationError.serviceRoleKeyNotAllowed) {
            try parse(url: "abc.supabase.co", key: jwt(role: "service_role"))
        }
        #expect(try parse(url: "abc.supabase.co", key: jwt(role: "anon")).publishableKey == jwt(role: "anon"))
    }

    @Test func httpOnlyForLocalSupabase() throws {
        #expect(throws: BackendConfigurationError.insecureURL) { try parse(url: "http://abc.supabase.co") }
        #expect(try parse(url: "http://127.0.0.1:54321").supabaseURL.absoluteString == "http://127.0.0.1:54321")
        #expect(try parse(url: "localhost:54321").supabaseURL.absoluteString == "http://localhost:54321")
    }

    @Test(arguments: ["https://abc.supabase.co/rest/v1", "ftp://abc.supabase.co", "https://abc.supabase.co?x=1"])
    func rejectsInvalidURLs(_ url: String) {
        #expect(throws: BackendConfigurationError.invalidURL) { try parse(url: url) }
    }

    @Test func everyErrorExplainsTheFix() {
        let errors: [BackendConfigurationError] = [
            .missingURL, .missingKey, .urlTruncatedByXcconfigComment, .invalidURL, .insecureURL,
            .placeholderValues, .secretKeyNotAllowed, .serviceRoleKeyNotAllowed,
        ]
        for error in errors {
            #expect(error.message.contains("Pace.xcconfig"))
        }
    }
}
