import Foundation
import PaceCore
import PostgREST

/// Das eigene Profil in `public.profiles`. Row Level Security erlaubt nur die eigene Zeile.
struct SupabaseProfileRepository: ProfileRepository {
    let client: PostgrestClient

    func fetchProfile(for userID: UserID) async throws -> UserProfile? {
        try await mapped {
            let row: ProfileRow? = try await client
                .from("profiles")
                .select(ProfileRow.columns)
                .eq("id", value: userID.description)
                .maybeSingle()
                .execute()
                .value
            return row?.profile
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
            let created: ProfileRow = try await client
                .from("profiles")
                .insert(row)
                .select(ProfileRow.columns)
                .single()
                .execute()
                .value
            return created.profile
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

    private func updateOwnProfile(_ values: some Encodable & Sendable, for userID: UserID) async throws -> UserProfile {
        try await mapped {
            let updated: ProfileRow = try await client
                .from("profiles")
                .update(values)
                .eq("id", value: userID.description)
                .select(ProfileRow.columns)
                .single()
                .execute()
                .value
            return updated.profile
        }
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw BackendErrorMapping.profileError(error)
        }
    }
}
