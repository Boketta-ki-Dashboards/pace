import Foundation
import PaceCore
import PostgREST

/// Bio, Interessen, Banner und freiwillige Auszeichnungen (Migration 20261030100000).
///
/// - Lesen über `social_profile_details` – gleiche Sichtbarkeit wie das öffentliche Profil, bei Blockierung leer.
/// - Ändern direkt in der eigenen Zeile von `public.profiles` (Spalten-Grant, RLS: nur die eigene Zeile). Constraints
///   und Trigger auf dem Server prüfen Länge, Zeichen, Katalog und die Banner-Datei.
/// - Ohne die Migration (Funktion oder Spalten unbekannt) meldet das Repository ``ProfileDetailsError/unavailable``.
struct SupabaseProfileDetailsRepository: ProfileDetailsRepository {
    let client: PostgrestClient
    let ownPublicID: OwnPublicID
    let currentUserID: @Sendable () -> UUID?

    func details(of publicID: UUID) async throws -> ProfileDetails {
        let row: ProfileDetailsRow = try await mapped {
            try await client.rpc("social_profile_details", params: ["p_public_id": publicID]).execute().value
        }
        return row.details
    }

    func ownDetails() async throws -> ProfileDetails {
        let publicID: UUID
        do {
            publicID = try await ownPublicID.value()
        } catch {
            throw ProfileDetailsError.unexpected("no_profile")
        }
        return try await details(of: publicID)
    }

    func saveOwnDetails(_ details: ProfileDetails) async throws -> ProfileDetails {
        guard let userID = currentUserID() else { throw ProfileDetailsError.unexpected("not_authenticated") }
        let bio = details.bio.flatMap(ProfileBioRules.normalized)
        if let bio, ProfileBioRules.problem(bio) != nil { throw ProfileDetailsError.invalid }
        let update = ProfileDetailsUpdate(
            bio: bio,
            interests: ProfileInterest.parse(details.interests.map(\.rawValue)).map(\.rawValue),
            bannerPath: details.bannerPath,
            showsAchievements: details.showsAchievements,
            achievements: ProfileAchievement.parse(details.achievements.map(\.rawValue)).map(\.rawValue)
        )
        let row: ProfileDetailsRow = try await mapped {
            try await client
                .from("profiles")
                .update(update)
                .eq("id", value: userID.uuidString.lowercased())
                .select(ProfileDetailsRow.columns)
                .single()
                .execute()
                .value
        }
        return row.details
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            // Abbruch (Seite verlassen) ist kein Netzfehler – sonst zeigt das Profil „Keine Verbindung“.
            if BackendFailure.isCancellation(error) { throw CancellationError() }
            throw BackendErrorMapping.profileDetailsError(error)
        }
    }
}

/// Antwort von `social_profile_details` bzw. die geänderte Zeile.
struct ProfileDetailsRow: Decodable {
    static let columns = "bio,interests,banner_path,shows_achievements,achievements"

    let bio: String?
    let interests: [String]
    let bannerPath: String?
    let showsAchievements: Bool?
    let achievements: [String]

    enum CodingKeys: String, CodingKey {
        case bio
        case interests
        case bannerPath = "banner_path"
        case showsAchievements = "shows_achievements"
        case achievements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        bannerPath = try container.decodeIfPresent(String.self, forKey: .bannerPath)
        showsAchievements = try container.decodeIfPresent(Bool.self, forKey: .showsAchievements)
        achievements = try container.decodeIfPresent([String].self, forKey: .achievements) ?? []
    }

    /// Bei fremden Profilen fehlt `shows_achievements`: Der Server liefert dann nur freigegebene Auszeichnungen.
    var details: ProfileDetails {
        let parsedAchievements = ProfileAchievement.parse(achievements)
        return ProfileDetails(
            bio: bio,
            interests: ProfileInterest.parse(interests),
            bannerPath: bannerPath,
            showsAchievements: showsAchievements ?? !parsedAchievements.isEmpty,
            achievements: parsedAchievements
        )
    }
}

struct ProfileDetailsUpdate: Encodable, Sendable {
    let bio: String?
    let interests: [String]
    let bannerPath: String?
    let showsAchievements: Bool
    let achievements: [String]

    enum CodingKeys: String, CodingKey {
        case bio
        case interests
        case bannerPath = "banner_path"
        case showsAchievements = "shows_achievements"
        case achievements
    }

    // `nil` muss als `null` gesendet werden (Bio bzw. Banner entfernen), nicht weggelassen.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bio, forKey: .bio)
        try container.encode(interests, forKey: .interests)
        try container.encode(bannerPath, forKey: .bannerPath)
        try container.encode(showsAchievements, forKey: .showsAchievements)
        try container.encode(achievements, forKey: .achievements)
    }
}
