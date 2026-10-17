import Foundation
import PaceCore
import PostgREST

/// Regionen aus dem amtlichen Gemeindeverzeichnis, gesucht und aufgelöst per RPC.
struct SupabaseRegionRepository: RegionRepository {
    /// Obergrenze, die auch der Server erzwingt.
    static let maximumSearchLimit = 50

    let client: PostgrestClient

    /// Zu kurze Eingaben werden ohne Anfrage mit einem leeren Ergebnis beantwortet.
    func searchMunicipalities(matching query: String, limit: Int) async throws -> [RegionHierarchy] {
        guard let normalized = RegionSearchQuery.normalized(query) else { return [] }
        let params = SearchMunicipalitiesParams(
            query: normalized,
            limit: min(max(limit, 1), Self.maximumSearchLimit)
        )
        let rows: [HierarchyRow] = try await mapped {
            try await client.rpc("search_municipalities", params: params).execute().value
        }
        return rows.map(\.hierarchy)
    }

    func hierarchy(forMunicipality id: RegionID) async throws -> RegionHierarchy {
        let params = RegionHierarchyParams(municipalityID: id.rawValue)
        let rows: [HierarchyRow] = try await mapped {
            try await client.rpc("get_region_hierarchy", params: params).execute().value
        }
        guard let row = rows.first else { throw RegionError.notFound }
        return row.hierarchy
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw BackendErrorMapping.regionError(error)
        }
    }
}
