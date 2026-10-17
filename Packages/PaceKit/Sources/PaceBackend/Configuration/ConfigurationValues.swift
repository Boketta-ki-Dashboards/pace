import Foundation

/// Bereinigt Rohwerte aus der Info.plist.
enum ConfigurationValue {
    /// Getrimmter Wert ohne umschließende Anführungszeichen. `nil`, wenn er leer ist oder eine nicht ersetzte
    /// Build-Variable wie `$(SUPABASE_URL)` enthält.
    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty, !value.contains("$("), !value.contains("${") else { return nil }
        return value
    }
}

/// Liest die Project URL. Erlaubt ist der Host allein (empfohlen, weil `//` in .xcconfig einen Kommentar beginnt)
/// oder eine vollständige URL ohne Pfad.
enum SupabaseURLValue {
    static let placeholderHost = "example.supabase.co"
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1"]

    /// Normalisierte URL (nur Schema, Host und Port) und ihr Host in Kleinbuchstaben.
    static func parse(_ value: String) throws(BackendConfigurationError) -> (url: URL, host: String) {
        let lowercased = value.lowercased()
        if lowercased == "https:" || lowercased == "http:" {
            throw .urlTruncatedByXcconfigComment
        }

        let candidate: String
        if lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://") {
            candidate = value
        } else if lowercased.contains("://") {
            throw .invalidURL
        } else {
            // Ohne Schema: https, außer für ein lokales Supabase (Supabase CLI läuft ohne TLS).
            candidate = (localHosts.contains(hostPart(of: lowercased)) ? "http://" : "https://") + value
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { throw .invalidURL }

        if scheme == "http", !localHosts.contains(host) {
            throw .insecureURL
        }

        var normalized = URLComponents()
        normalized.scheme = scheme
        normalized.host = host
        normalized.port = components.port
        guard let url = normalized.url else { throw .invalidURL }
        return (url, host)
    }

    /// Erstes Label des Hosts, z. B. `abcdefghijklmnop` für `abcdefghijklmnop.supabase.co`.
    static func projectRef(ofHost host: String) -> String {
        host.split(separator: ".").first.map(String.init) ?? host
    }

    private static func hostPart(of value: String) -> String {
        let authority = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        return authority.split(separator: ":", maxSplits: 1).first.map(String.init) ?? authority
    }
}

/// Prüft den Key: Nur öffentliche Keys sind erlaubt.
enum PublishableKeyValue {
    static let placeholder = "sb_publishable_example"

    static func validate(_ key: String) throws(BackendConfigurationError) {
        if key.hasPrefix("sb_secret_") {
            throw .secretKeyNotAllowed
        }
        if legacyJWTRole(of: key) == "service_role" {
            throw .serviceRoleKeyNotAllowed
        }
    }

    /// Rolle aus dem Payload eines alten JWT-Keys (`anon` bzw. `service_role`). `nil` für andere Formate.
    static func legacyJWTRole(of key: String) -> String? {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = base64URLDecoded(segments[1]),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        return object["role"] as? String
    }

    private static func base64URLDecoded(_ segment: Substring) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
