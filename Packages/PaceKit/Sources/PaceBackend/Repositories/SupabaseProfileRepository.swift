import Foundation
import PaceCore
import PostgREST

/// Das eigene Profil in `public.profiles`. Row Level Security erlaubt nur die eigene Zeile; geändert werden nur die
/// per Spalten-Grant freigegebenen Felder (Namen, Region, Zustimmung, Profilbild, Auffindbarkeit). Constraints und
/// Trigger auf dem Server prüfen Format, Profilbild-Pfad und das Rate Limit für Benutzernamen.
struct SupabaseProfileRepository: ProfileRepository {
    let client: PostgrestClient

    func fetchProfile(for userID: UserID) async throws -> UserProfile? {
        try await mapped {
            try await withColumnFallback { columns in
                let row: ProfileRow? = try await client
                    .from("profiles")
                    .select(columns)
                    .eq("id", value: userID.description)
                    .maybeSingle()
                    .execute()
                    .value
                return row?.profile
            }
        }
    }

    /// Benutzer- und Anzeigename werden vor dem Senden normalisiert (Leerzeichen am Rand), wie es der Server verlangt.
    func createProfile(_ profile: NewProfile, for userID: UserID) async throws -> UserProfile {
        let row = NewProfileRow(
            id: userID.description,
            username: UsernameRules.normalized(profile.username),
            displayName: DisplayNameRules.normalized(profile.displayName)
        )
        return try await mapped {
            try await withColumnFallback { columns in
                let created: ProfileRow = try await client
                    .from("profiles")
                    .insert(row)
                    .select(columns)
                    .single()
                    .execute()
                    .value
                return created.profile
            }
        }
    }

    func updateRegion(
        municipalityID: RegionID,
        regionalLeaderboardEnabled: Bool,
        for userID: UserID
    ) async throws -> UserProfile {
        let update = ProfileRegionUpdate(
            municipalityID: municipalityID.rawValue,
            regionalLeaderboardEnabled: regionalLeaderboardEnabled
        )
        return try await updateOwnProfile(update, for: userID)
    }

    func updateRegionalLeaderboardEnabled(_ enabled: Bool, for userID: UserID) async throws -> UserProfile {
        try await updateOwnProfile(ProfileOptInUpdate(regionalLeaderboardEnabled: enabled), for: userID)
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let params = UsernameAvailabilityParams(username: UsernameRules.normalized(username))
        return try await mapped {
            try await client.rpc("is_username_available", params: params).execute().value
        }
    }

    /// Ändert nur die übergebenen Namen. Ohne Änderung wird das aktuelle Profil geladen.
    func updateNames(username: String?, displayName: String?, for userID: UserID) async throws -> UserProfile {
        let update = ProfileNamesUpdate(
            username: username.map(UsernameRules.normalized),
            displayName: displayName.map(DisplayNameRules.normalized)
        )
        guard update.username != nil || update.displayName != nil else {
            guard let profile = try await fetchProfile(for: userID) else { throw ProfileError.notAuthenticated }
            return profile
        }
        return try await updateOwnProfile(update, for: userID)
    }

    /// Der Pfad muss im Ordner der eigenen öffentlichen ID liegen und die Datei bereits hochgeladen sein (Trigger).
    func updateAvatar(path: String?, for userID: UserID) async throws -> UserProfile {
        try await updateOwnProfile(ProfileAvatarUpdate(avatarPath: path), for: userID)
    }

    func updateDiscoverable(_ discoverable: Bool, for userID: UserID) async throws -> UserProfile {
        try await updateOwnProfile(ProfileDiscoverableUpdate(isDiscoverable: discoverable), for: userID)
    }

    private func updateOwnProfile(_ values: some Encodable & Sendable, for userID: UserID) async throws -> UserProfile {
        try await mapped {
            try await withColumnFallback { columns in
                let updated: ProfileRow = try await client
                    .from("profiles")
                    .update(values)
                    .eq("id", value: userID.description)
                    .select(columns)
                    .single()
                    .execute()
                    .value
                return updated.profile
            }
        }
    }

    /// Fragt mit allen Spalten an; fehlen die neuen Spalten auf dem Server (Postgres `42703`, z. B. vor Migration
    /// 20261019100000), wird mit den bisherigen Spalten wiederholt. Die Anfrage scheitert dann vor jeder Änderung.
    private func withColumnFallback<T>(_ operation: (String) async throws -> T) async throws -> T {
        do {
            return try await operation(ProfileRow.columns)
        } catch let error as PostgrestError where error.code == "42703" {
            return try await operation(ProfileRow.legacyColumns)
        }
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as ProfileError {
            throw error
        } catch {
            throw BackendErrorMapping.profileError(error)
        }
    }
}
