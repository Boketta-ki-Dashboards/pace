import Foundation

/// Stabile ID eines Pace-Nutzers (entspricht der Auth-User-ID im Backend). Wird nie öffentlich angezeigt.
public struct UserID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString.lowercased() }
}

/// Eine angemeldete Sitzung.
public struct AuthSession: Equatable, Sendable {
    public let userID: UserID
    /// `true` für die technische MVP-Identität ohne Login-Methode. Wird Nutzern nicht angezeigt.
    public let isAnonymous: Bool

    public init(userID: UserID, isAnonymous: Bool) {
        self.userID = userID
        self.isAnonymous = isAnonymous
    }
}

public enum AuthError: Error, Equatable, Sendable {
    /// Anonyme Anmeldung ist im Backend deaktiviert.
    case anonymousSignInDisabled
    case rateLimited
    case network
    case unexpected(String)
}

/// Anmeldung. In Milestone 2 nur die anonyme MVP-Identität; Sign in with Apple wird später ergänzt
/// (siehe docs/BACKEND.md), ohne dass Features davon abhängen.
public protocol AuthProviding: Sendable {
    /// Die lokal gespeicherte Sitzung, ohne Netzwerkzugriff. `nil`, wenn keine existiert.
    func restoreSession() async -> AuthSession?

    /// Legt eine neue anonyme Identität an und meldet sie an.
    func signInAnonymously() async throws -> AuthSession
}
