import Foundation

/// Zeile für die Anzeige: ein Eintrag oder eine Lücke zwischen Top-Liste und eigener Position.
public enum LeaderboardRow: Equatable, Hashable, Sendable, Identifiable {
    case entry(LeaderboardEntry)
    /// Ausgelassene Plätze nach Platz `afterRank`.
    case gap(afterRank: Int)

    public var id: String {
        switch self {
        case .entry(let entry): "entry-\(entry.publicUserID.uuidString)"
        case .gap(let rank): "gap-\(rank)"
        }
    }
}

/// Das geladene Ranking für eine Ebene.
public struct LeaderboardSnapshot: Equatable, Sendable {
    public let query: LeaderboardQuery
    public let rows: [LeaderboardRow]
    public let totalParticipants: Int
    /// Der eigene Eintrag, falls der Nutzer im Ranking erscheint.
    public let currentUserEntry: LeaderboardEntry?

    public init(query: LeaderboardQuery, rows: [LeaderboardRow], totalParticipants: Int, currentUserEntry: LeaderboardEntry?) {
        self.query = query
        self.rows = rows
        self.totalParticipants = totalParticipants
        self.currentUserEntry = currentUserEntry
    }

    public var entries: [LeaderboardEntry] {
        rows.compactMap {
            guard case .entry(let entry) = $0 else { return nil }
            return entry
        }
    }

    public var isEmpty: Bool { totalParticipants == 0 }

    /// Anzahl der lückenlos geladenen Plätze ab Platz 1.
    public var loadedTopCount: Int {
        var count = 0
        for entry in entries {
            guard entry.rank == count + 1 else { break }
            count += 1
        }
        return count
    }

    /// Ob es nach den lückenlos geladenen Plätzen weitere gibt, die noch nicht angezeigt werden.
    public var canLoadMore: Bool {
        loadedTopCount < totalParticipants && entries.count < totalParticipants
    }

    /// Nur der Nutzer selbst ist im Ranking.
    public var isCurrentUserAlone: Bool {
        totalParticipants == 1 && currentUserEntry != nil
    }
}

/// Lädt die Top-Plätze und – falls der Nutzer nicht darunter ist – seine Position mit Nachbarn.
public struct LeaderboardLoader: Sendable {
    private let repository: any LeaderboardRepository
    private let topLimit: Int
    private let neighborRadius: Int

    public init(repository: any LeaderboardRepository, topLimit: Int = 50, neighborRadius: Int = 1) {
        self.repository = repository
        self.topLimit = topLimit
        self.neighborRadius = neighborRadius
    }

    public func load(_ query: LeaderboardQuery) async throws -> LeaderboardSnapshot {
        let top = try await repository.page(for: query, offset: 0, limit: topLimit)
        var rows = top.entries.map(LeaderboardRow.entry)
        var currentUser = top.entries.first(where: \.isCurrentUser)

        if currentUser == nil {
            let neighborhood = try await repository.neighborhood(for: query, radius: neighborRadius)
            currentUser = neighborhood.first(where: \.isCurrentUser)
            let lastTopRank = top.entries.last?.rank ?? 0
            let below = neighborhood.filter { $0.rank > lastTopRank }.sorted { $0.rank < $1.rank }
            if let first = below.first {
                if first.rank > lastTopRank + 1 {
                    rows.append(.gap(afterRank: lastTopRank))
                }
                rows.append(contentsOf: below.map(LeaderboardRow.entry))
            }
        }

        return LeaderboardSnapshot(
            query: query,
            rows: rows,
            totalParticipants: top.totalParticipants,
            currentUserEntry: currentUser
        )
    }

    /// Lädt die nächsten Plätze nach den lückenlos geladenen und fügt sie ein. Schließt sich dabei die Lücke zur
    /// eigenen Position, verschwindet sie.
    public func loadMore(after snapshot: LeaderboardSnapshot) async throws -> LeaderboardSnapshot {
        let page = try await repository.page(for: snapshot.query, offset: snapshot.loadedTopCount, limit: topLimit)

        // Neuere Werte gewinnen; je Platz und je Nutzer nur ein Eintrag.
        var byRank: [Int: LeaderboardEntry] = [:]
        for entry in snapshot.entries + page.entries {
            byRank[entry.rank] = entry
        }
        var seenUsers: Set<UUID> = []
        let merged = byRank.values
            .sorted { $0.rank < $1.rank }
            .filter { seenUsers.insert($0.publicUserID).inserted }

        var rows: [LeaderboardRow] = []
        var previousRank = 0
        for entry in merged {
            if entry.rank > previousRank + 1 {
                rows.append(.gap(afterRank: previousRank))
            }
            rows.append(.entry(entry))
            previousRank = entry.rank
        }

        return LeaderboardSnapshot(
            query: snapshot.query,
            rows: rows,
            totalParticipants: page.totalParticipants,
            currentUserEntry: merged.first(where: \.isCurrentUser) ?? snapshot.currentUserEntry
        )
    }
}
