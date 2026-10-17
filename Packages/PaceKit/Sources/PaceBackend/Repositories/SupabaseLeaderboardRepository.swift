import Foundation
import PaceCore
import PostgREST

/// Serverseitig berechnete Rankings per RPC. Es werden nie alle Teilnehmer geladen.
struct SupabaseLeaderboardRepository: LeaderboardRepository {
    /// Grenzen, die auch der Server erzwingt.
    static let maximumPageSize = 100
    static let maximumRadius = 10

    let client: PostgrestClient

    func page(for query: LeaderboardQuery, offset: Int, limit: Int) async throws -> LeaderboardPage {
        let offset = max(offset, 0)
        let limit = min(max(limit, 1), Self.maximumPageSize)
        let params = LeaderboardPageParams(
            regionID: query.regionID.rawValue,
            period: query.period.rawValue,
            date: query.date.isoString,
            limit: limit,
            offset: offset
        )
        let response: LeaderboardResponse = try await mapped {
            try await client.rpc("leaderboard_page", params: params).execute().value
        }
        return LeaderboardPage(
            entries: Self.sortedEntries(response),
            totalParticipants: response.totalParticipants,
            offset: offset,
            limit: limit
        )
    }

    func neighborhood(for query: LeaderboardQuery, radius: Int) async throws -> [LeaderboardEntry] {
        let params = LeaderboardNeighborhoodParams(
            regionID: query.regionID.rawValue,
            period: query.period.rawValue,
            date: query.date.isoString,
            radius: min(max(radius, 0), Self.maximumRadius)
        )
        let response: LeaderboardResponse = try await mapped {
            try await client.rpc("leaderboard_neighborhood", params: params).execute().value
        }
        return Self.sortedEntries(response)
    }

    private static func sortedEntries(_ response: LeaderboardResponse) -> [LeaderboardEntry] {
        response.entries.map(\.entry).sorted { $0.rank < $1.rank }
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw BackendErrorMapping.leaderboardError(error)
        }
    }
}
