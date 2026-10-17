import Foundation

/// Fehler beim Einlesen der Backend-Konfiguration. `message` erklärt, wie man ihn in `Config/Pace.xcconfig` behebt.
public enum BackendConfigurationError: Error, Equatable, Sendable {
    /// `SUPABASE_URL` ist leer, fehlt oder wurde nicht ersetzt.
    case missingURL
    /// `SUPABASE_PUBLISHABLE_KEY` ist leer, fehlt oder wurde nicht ersetzt.
    case missingKey
    /// Die URL endet nach `https:`, weil `//` in .xcconfig-Dateien einen Kommentar beginnt.
    case urlTruncatedByXcconfigComment
    /// Die URL lässt sich nicht als Project URL lesen (z. B. mit Pfad oder fremdem Schema).
    case invalidURL
    /// `http` ohne TLS ist nur für ein lokales Supabase erlaubt.
    case insecureURL
    /// Es stehen noch die Platzhalter aus `Config/Pace.xcconfig.example` drin.
    case placeholderValues
    /// Ein Secret Key (`sb_secret_…`) darf nie in die App.
    case secretKeyNotAllowed
    /// Ein alter service_role-Key (JWT) darf nie in die App.
    case serviceRoleKeyNotAllowed

    public var message: String {
        switch self {
        case .missingURL:
            "Die Supabase-URL fehlt. Kopiere Config/Pace.xcconfig.example nach Config/Pace.xcconfig und trage bei "
                + "SUPABASE_URL die Project URL ein (z. B. abcdefghijklmnop.supabase.co)."
        case .missingKey:
            "Der Publishable Key fehlt. Trage in Config/Pace.xcconfig bei SUPABASE_PUBLISHABLE_KEY den Publishable Key "
                + "(sb_publishable_…) deines Supabase-Projekts ein."
        case .urlTruncatedByXcconfigComment:
            "Die Supabase-URL wurde nach „https:“ abgeschnitten, weil „//“ in .xcconfig-Dateien einen Kommentar beginnt. "
                + "Trage sie in Config/Pace.xcconfig ohne „https://“ ein (z. B. abcdefghijklmnop.supabase.co)."
        case .invalidURL:
            "Die Supabase-URL in Config/Pace.xcconfig ist ungültig. Erwartet wird nur der Host der Project URL, "
                + "z. B. abcdefghijklmnop.supabase.co – ohne Pfad wie /rest/v1."
        case .insecureURL:
            "Unverschlüsseltes http ist nur für ein lokales Supabase (localhost, 127.0.0.1) erlaubt. Trage in "
                + "Config/Pace.xcconfig die https-Project-URL ein."
        case .placeholderValues:
            "Config/Pace.xcconfig enthält noch die Platzhalter aus der Vorlage. Trage die Project URL und den "
                + "Publishable Key deines Pace-Supabase-Projekts ein."
        case .secretKeyNotAllowed:
            "In Config/Pace.xcconfig steht ein Secret Key (sb_secret_…). Secret Keys gehören nie in die App – "
                + "verwende den Publishable Key (sb_publishable_…)."
        case .serviceRoleKeyNotAllowed:
            "In Config/Pace.xcconfig steht ein service_role-Key. Er umgeht alle Zugriffsregeln und gehört nie in die "
                + "App – verwende den Publishable Key (sb_publishable_…)."
        }
    }
}
