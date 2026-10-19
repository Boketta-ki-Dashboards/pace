import Foundation

/// Links in die App, z. B. zum Teilen des eigenen Profils: `pace://u/niklas`.
///
/// Das URL-Schema `pace` ist in der Info.plist eingetragen. Ein geöffneter Link führt zum Profil im Social-Tab;
/// ob man die Person sehen oder hinzufügen darf, prüft wie immer der Server.
public enum PaceLink: Equatable, Sendable {
    /// Öffentliches Profil über den Benutzernamen.
    case profile(username: String)

    public static let scheme = "pace"

    public var url: URL {
        switch self {
        case .profile(let username):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "u"
            components.path = "/" + username
            // Benutzernamen bestehen nur aus Buchstaben, Ziffern und „_“ – die URL ist damit immer gültig.
            return components.url ?? URL(string: "\(Self.scheme)://u")!
        }
    }

    /// Erkennt einen Pace-Link; `nil` bei fremden oder ungültigen Links (z. B. unzulässiger Benutzername).
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == "u" else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1 else { return nil }
        let username = String(parts[0])
        guard UsernameRules.violation(for: username) == nil else { return nil }
        self = .profile(username: username)
    }
}
