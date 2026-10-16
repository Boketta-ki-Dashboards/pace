import Foundation

/// Lokaler Cache des eigenen Profils, damit die App auch ohne Netz direkt startet.
public protocol ProfileCaching: Sendable {
    func load(for userID: UserID) -> UserProfile?
    func save(_ profile: UserProfile)
}

/// Speichert das Profil als JSON in den `UserDefaults`. Enthält keine Gesundheitsdaten.
public struct UserDefaultsProfileCache: ProfileCaching {
    private let suiteName: String?
    private let keyPrefix = "pace.profile."

    /// - Parameter suiteName: `nil` für die Standard-Defaults der App.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load(for userID: UserID) -> UserProfile? {
        guard let data = defaults.data(forKey: keyPrefix + userID.description) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    public func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: keyPrefix + profile.id.description)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
