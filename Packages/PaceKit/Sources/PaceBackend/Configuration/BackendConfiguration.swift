import Foundation

/// Verbindung zum Supabase-Projekt von Pace. Enthält ausschließlich öffentliche Werte (Project URL und Publishable
/// Key) – Secret Keys und service_role-Keys werden beim Einlesen abgelehnt.
public struct BackendConfiguration: Sendable, Equatable {
    /// Info.plist-Schlüssel, befüllt aus `SUPABASE_URL` in `Config/Pace.xcconfig`.
    public static let urlInfoKey = "PaceSupabaseURL"
    /// Info.plist-Schlüssel, befüllt aus `SUPABASE_PUBLISHABLE_KEY` in `Config/Pace.xcconfig`.
    public static let publishableKeyInfoKey = "PaceSupabasePublishableKey"

    /// Basis-URL des Projekts ohne Pfad, z. B. `https://abcdefghijklmnop.supabase.co`.
    public let supabaseURL: URL
    /// Publishable Key (`sb_publishable_…`) oder alter anon-Key.
    public let publishableKey: String
    /// Projektkennung (erstes Label des Hosts). Teil des Schlüssels, unter dem die Sitzung gespeichert wird.
    public let projectRef: String

    /// Übernimmt die Werte ungeprüft (z. B. für Tests). In der App `fromInfoDictionary(_:)` verwenden.
    public init(supabaseURL: URL, publishableKey: String, projectRef: String) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.projectRef = projectRef
    }

    /// Liest und prüft die Werte aus der Info.plist der App.
    public static func fromInfoDictionary(
        _ info: [String: Any]
    ) throws(BackendConfigurationError) -> BackendConfiguration {
        try make(
            url: info[urlInfoKey] as? String,
            publishableKey: info[publishableKeyInfoKey] as? String
        )
    }

    /// Prüft rohe Werte (z. B. aus Umgebungsvariablen) nach denselben Regeln wie die Info.plist.
    public static func make(
        url rawURL: String?,
        publishableKey rawKey: String?
    ) throws(BackendConfigurationError) -> BackendConfiguration {
        guard let urlValue = ConfigurationValue.cleaned(rawURL) else { throw .missingURL }
        guard let key = ConfigurationValue.cleaned(rawKey) else { throw .missingKey }

        let (url, host) = try SupabaseURLValue.parse(urlValue)
        if host == SupabaseURLValue.placeholderHost || key == PublishableKeyValue.placeholder {
            throw .placeholderValues
        }
        try PublishableKeyValue.validate(key)

        return BackendConfiguration(
            supabaseURL: url,
            publishableKey: key,
            projectRef: SupabaseURLValue.projectRef(ofHost: host)
        )
    }
}

extension BackendConfiguration {
    /// Endpunkt von Supabase Auth.
    var authURL: URL { supabaseURL.appendingPathComponent("auth/v1") }

    /// Endpunkt von PostgREST.
    var restURL: URL { supabaseURL.appendingPathComponent("rest/v1") }

    /// Schlüssel der gespeicherten Sitzung – derselbe wie bei den offiziellen Supabase-Clients.
    var authStorageKey: String { "sb-\(projectRef)-auth-token" }
}
