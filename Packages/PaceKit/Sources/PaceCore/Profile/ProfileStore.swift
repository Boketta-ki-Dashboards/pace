import Foundation
import Observation

/// Gemeinsamer Stand des eigenen Profils und seiner Region für alle Features der Main App.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profile: UserProfile
    /// Hierarchie der gewählten Gemeinde; `nil`, solange sie noch nicht geladen wurde.
    public private(set) var hierarchy: RegionHierarchy?

    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let regions: any RegionRepository
    @ObservationIgnored private let cache: any ProfileCaching

    public init(
        profile: UserProfile,
        hierarchy: RegionHierarchy? = nil,
        profiles: any ProfileRepository,
        regions: any RegionRepository,
        cache: any ProfileCaching
    ) {
        self.profile = profile
        self.hierarchy = hierarchy
        self.profiles = profiles
        self.regions = regions
        self.cache = cache
    }

    /// Lädt die Hierarchie der gewählten Gemeinde, falls sie fehlt oder nicht mehr passt.
    public func loadHierarchyIfNeeded() async throws {
        guard let municipalityID = profile.municipalityID else {
            hierarchy = nil
            return
        }
        guard hierarchy?.municipality.id != municipalityID else { return }
        let loaded = try await regions.hierarchy(forMunicipality: municipalityID)
        if profile.municipalityID == municipalityID {
            hierarchy = loaded
        }
    }

    /// Lädt das Profil neu (z. B. nach einem Start aus dem Cache).
    public func refresh() async throws {
        guard let fresh = try await profiles.fetchProfile(for: profile.id) else { return }
        apply(fresh)
        try await loadHierarchyIfNeeded()
    }

    /// Wechselt die Gemeinde. Die Zustimmung zum Regionalranking bleibt unverändert.
    public func changeRegion(to newHierarchy: RegionHierarchy) async throws {
        let updated = try await profiles.updateRegion(
            municipalityID: newHierarchy.municipality.id,
            regionalLeaderboardEnabled: profile.regionalLeaderboardEnabled,
            for: profile.id
        )
        hierarchy = newHierarchy
        apply(updated)
    }

    public func setRegionalLeaderboardEnabled(_ enabled: Bool) async throws {
        let updated = try await profiles.updateRegionalLeaderboardEnabled(enabled, for: profile.id)
        apply(updated)
    }

    private func apply(_ updated: UserProfile) {
        profile = updated
        cache.save(updated)
        if hierarchy?.municipality.id != updated.municipalityID {
            hierarchy = nil
        }
    }
}
