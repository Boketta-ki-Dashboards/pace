import Foundation
import PaceCore

// Vorläufige Implementierungen der neuen Schnittstellen. Sie werden durch die echten Supabase-Aufrufe ersetzt
// (Migration 20261019100000 und folgende); bis dahin melden sie „nicht eingerichtet“, wie fehlende RPCs.

extension SupabaseSocialRepository {
    func searchProfiles(query: String) async throws -> [ProfileSearchResult] {
        throw SocialError.unavailable
    }

    func publicProfile(_ publicID: UUID, date: LocalDate) async throws -> PublicProfile {
        throw SocialError.unavailable
    }

    func updateGroupDetails(_ groupID: UUID, name: String, description: String, kind: GroupKind, privacy: GroupPrivacy) async throws -> GroupSummary {
        throw SocialError.unavailable
    }

    func setGroupImage(_ groupID: UUID, path: String?) async throws -> GroupSummary {
        throw SocialError.unavailable
    }

    func block(_ publicID: UUID) async throws {
        throw SocialError.unavailable
    }

    func unblock(_ publicID: UUID) async throws {
        throw SocialError.unavailable
    }

    func blockedUsers() async throws -> [SocialProfile] {
        throw SocialError.unavailable
    }

    func report(_ target: ReportTarget, reason: ReportReason, details: String?) async throws {
        throw SocialError.unavailable
    }
}

extension SupabaseProfileRepository {
    func updateNames(username: String?, displayName: String?, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("not available")
    }

    func updateAvatar(path: String?, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("not available")
    }

    func updateDiscoverable(_ discoverable: Bool, for userID: UserID) async throws -> UserProfile {
        throw ProfileError.unexpected("not available")
    }
}
