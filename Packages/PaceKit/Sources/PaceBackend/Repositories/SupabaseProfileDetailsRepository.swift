import Foundation
import PaceCore
import PostgREST

/// Bio, Interessen, Banner und freiwillige Auszeichnungen (Migration 20261030100000); eigene Interessen, gesprochene
/// Sprachen und Land (Migration 20261102100000).
///
/// - Lesen über `social_profile_details` – gleiche Sichtbarkeit wie das öffentliche Profil, bei Blockierung leer.
/// - Ändern direkt in der eigenen Zeile von `public.profiles` (Spalten-Grant, RLS: nur die eigene Zeile). Constraints
///   und Trigger auf dem Server prüfen Länge, Zeichen, Katalog und die Banner-Datei.
/// - Ohne die Migration (Funktion oder Spalten unbekannt) meldet das Repository ``ProfileDetailsError/unavailable``.
/// - Ob der Server die Erweiterung aus 20261102100000 kennt, steht in der Antwort selbst (Schlüssel
///   `custom_interests`): Nur dann sendet das Repository die neuen Spalten mit – ältere Server bekommen wie bisher
///   höchstens fünf Interessen aus dem ursprünglichen Katalog.
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
        let update = try ProfileDetailsUpdate(details, bio: bio)
        let row: ProfileDetailsRow = try await mapped {
            try await client
                .from("profiles")
                .update(update)
                .eq("id", value: userID.uuidString.lowercased())
                .select(update.extended ? ProfileDetailsRow.extendedColumns : ProfileDetailsRow.columns)
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
    static let extendedColumns = columns + ",custom_interests,spoken_languages,country_code"

    let bio: String?
    let interests: [String]
    let customInterests: [String]?
    let spokenLanguages: [String]
    let countryCode: String?
    let bannerPath: String?
    let showsAchievements: Bool?
    let achievements: [String]

    enum CodingKeys: String, CodingKey {
        case bio
        case interests
        case customInterests = "custom_interests"
        case spokenLanguages = "spoken_languages"
        case countryCode = "country_code"
        case bannerPath = "banner_path"
        case showsAchievements = "shows_achievements"
        case achievements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        // Fehlt der Schlüssel ganz, kennt der Server die Erweiterung (20261102100000) noch nicht.
        if container.contains(.customInterests) {
            customInterests = try container.decodeIfPresent([String].self, forKey: .customInterests) ?? []
        } else {
            customInterests = nil
        }
        spokenLanguages = try container.decodeIfPresent([String].self, forKey: .spokenLanguages) ?? []
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        bannerPath = try container.decodeIfPresent(String.self, forKey: .bannerPath)
        showsAchievements = try container.decodeIfPresent(Bool.self, forKey: .showsAchievements)
        achievements = try container.decodeIfPresent([String].self, forKey: .achievements) ?? []
    }

    /// Bei fremden Profilen fehlt `shows_achievements`: Der Server liefert dann nur freigegebene Auszeichnungen.
    var details: ProfileDetails {
        let parsedAchievements = ProfileAchievement.parse(achievements)
        let extended = customInterests != nil
        let parsed = ProfileInterest.parse(interests)
        // IDs aus einer neueren App-Version: nicht anzeigen, aber erhalten (nur mit der Erweiterung auf dem Server).
        let preserved = extended ? ProfileInterest.unknownIDs(interests) : []
        let custom = CustomInterestRules.parse(customInterests ?? [])
        return ProfileDetails(
            bio: bio,
            interests: parsed,
            customInterests: Array(custom.prefix(max(0, ProfileInterestRules.maximumTotal - parsed.count - preserved.count))),
            spokenLanguages: SpokenLanguageCatalog.parse(spokenLanguages),
            countryCode: countryCode.flatMap { ProfileCountryCatalog.isKnown($0) ? $0 : nil },
            bannerPath: bannerPath,
            showsAchievements: showsAchievements ?? !parsedAchievements.isEmpty,
            achievements: parsedAchievements,
            supportsExtendedProfile: extended,
            preservedInterestIDs: preserved
        )
    }
}

/// Änderung der eigenen Zeile. Die neuen Spalten (20261102100000) nur, wenn der Server sie kennt.
struct ProfileDetailsUpdate: Encodable, Sendable {
    let bio: String?
    let interests: [String]
    let bannerPath: String?
    let showsAchievements: Bool
    let achievements: [String]
    /// `nil` = älterer Server: Spalten nicht senden.
    let customInterests: [String]?
    let spokenLanguages: [String]?
    let countryCode: String?

    var extended: Bool { customInterests != nil }

    enum CodingKeys: String, CodingKey {
        case bio
        case interests
        case bannerPath = "banner_path"
        case showsAchievements = "shows_achievements"
        case achievements
        case customInterests = "custom_interests"
        case spokenLanguages = "spoken_languages"
        case countryCode = "country_code"
    }

    /// Wie auf dem Server geprüft: Katalog-IDs und eigene Begriffe ohne Doppelte, zusammen höchstens 20 (ältere Server:
    /// fünf aus dem ursprünglichen Katalog), Sprachen und Land im gültigen Format.
    init(_ details: ProfileDetails, bio: String?) throws {
        self.bio = bio
        bannerPath = details.bannerPath
        showsAchievements = details.showsAchievements
        achievements = ProfileAchievement.parse(details.achievements.map(\.rawValue)).map(\.rawValue)
        let catalog = ProfileInterest.parse(details.interests.map(\.rawValue))
        guard details.supportsExtendedProfile else {
            interests = catalog.filter(\.isLegacy).prefix(ProfileInterestRules.legacyMaximum).map(\.rawValue)
            customInterests = nil
            spokenLanguages = nil
            countryCode = nil
            return
        }
        let custom = CustomInterestRules.parse(details.customInterests)
        let preserved = ProfileInterest.unknownIDs(details.preservedInterestIDs)
        guard custom.count == details.customInterests.count,
              catalog.count + preserved.count + custom.count <= ProfileInterestRules.maximumTotal,
              details.spokenLanguages.allSatisfy(SpokenLanguageCatalog.isValid),
              details.spokenLanguages.count <= ProfileInterestRules.maximumLanguages,
              details.countryCode.map(ProfileCountryCatalog.isValid) ?? true
        else { throw ProfileDetailsError.invalid }
        interests = catalog.map(\.rawValue) + preserved
        customInterests = custom
        spokenLanguages = SpokenLanguageCatalog.parse(details.spokenLanguages)
        countryCode = details.countryCode
    }

    // `nil` muss als `null` gesendet werden (Bio, Banner bzw. Land entfernen), nicht weggelassen.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bio, forKey: .bio)
        try container.encode(interests, forKey: .interests)
        try container.encode(bannerPath, forKey: .bannerPath)
        try container.encode(showsAchievements, forKey: .showsAchievements)
        try container.encode(achievements, forKey: .achievements)
        if let customInterests {
            try container.encode(customInterests, forKey: .customInterests)
            try container.encode(spokenLanguages ?? [], forKey: .spokenLanguages)
            try container.encode(countryCode, forKey: .countryCode)
        }
    }
}
