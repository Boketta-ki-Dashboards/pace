import Foundation
import PaceCore

// MARK: - Auth

public final class AuthStub: AuthProviding, Sendable {
    public struct State: Sendable {
        public var storedSession: AuthSession?
        public var signInResult: Result<AuthSession, AuthError> = .success(
            AuthSession(userID: Fixtures.userID, isAnonymous: true)
        )
        public var signInCalls = 0
        public var signOutCalls = 0
    }

    public let state: Locked<State>

    public init(storedSession: AuthSession? = nil, configure: (inout State) -> Void = { _ in }) {
        var state = State(storedSession: storedSession)
        configure(&state)
        self.state = Locked(state)
    }

    public func restoreSession() async -> AuthSession? {
        state.withLock { $0.storedSession }
    }

    public func signInAnonymously() async throws -> AuthSession {
        try state.withLock { state in
            state.signInCalls += 1
            let session = try state.signInResult.get()
            state.storedSession = session
            return session
        }
    }

    public func signOut() async {
        state.withLock { state in
            state.signOutCalls += 1
            state.storedSession = nil
        }
    }
}

// MARK: - Profile

public final class ProfileRepositoryStub: ProfileRepository, Sendable {
    public struct State: Sendable {
        public var profiles: [UserID: UserProfile] = [:]
        public var takenUsernames: Set<String> = []
        public var error: ProfileError?
        public var fetchCalls = 0
        public var createCalls: [NewProfile] = []
        public var regionUpdates: [(RegionID, Bool)] = []
        public var optInUpdates: [Bool] = []
        public var nameUpdates: [(username: String?, displayName: String?)] = []
        public var avatarUpdates: [String?] = []
        public var discoverableUpdates: [Bool] = []
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func fetchProfile(for userID: UserID) async throws -> UserProfile? {
        try state.withLock { state in
            state.fetchCalls += 1
            if let error = state.error { throw error }
            return state.profiles[userID]
        }
    }

    public func createProfile(_ profile: NewProfile, for userID: UserID) async throws -> UserProfile {
        try state.withLock { state in
            state.createCalls.append(profile)
            if let error = state.error { throw error }
            if state.takenUsernames.contains(profile.username.lowercased()) { throw ProfileError.usernameTaken }
            let created = Fixtures.profile(
                id: userID,
                username: profile.username,
                displayName: profile.displayName,
                municipalityID: nil
            )
            state.profiles[userID] = created
            state.takenUsernames.insert(profile.username.lowercased())
            return created
        }
    }

    public func updateRegion(
        municipalityID: RegionID,
        regionalLeaderboardEnabled: Bool,
        for userID: UserID
    ) async throws -> UserProfile {
        try state.withLock { state in
            state.regionUpdates.append((municipalityID, regionalLeaderboardEnabled))
            if let error = state.error { throw error }
            guard var profile = state.profiles[userID] else { throw ProfileError.notAuthenticated }
            profile.municipalityID = municipalityID
            profile.regionalLeaderboardEnabled = regionalLeaderboardEnabled
            state.profiles[userID] = profile
            return profile
        }
    }

    public func updateRegionalLeaderboardEnabled(_ enabled: Bool, for userID: UserID) async throws -> UserProfile {
        try state.withLock { state in
            state.optInUpdates.append(enabled)
            if let error = state.error { throw error }
            guard var profile = state.profiles[userID] else { throw ProfileError.notAuthenticated }
            profile.regionalLeaderboardEnabled = enabled
            state.profiles[userID] = profile
            return profile
        }
    }

    public func isUsernameAvailable(_ username: String) async throws -> Bool {
        try state.withLock { state in
            if let error = state.error { throw error }
            return !state.takenUsernames.contains(username.lowercased())
        }
    }

    public func updateNames(username: String?, displayName: String?, for userID: UserID) async throws -> UserProfile {
        try state.withLock { state in
            state.nameUpdates.append((username, displayName))
            if let error = state.error { throw error }
            guard var profile = state.profiles[userID] else { throw ProfileError.notAuthenticated }
            if let username {
                let lowered = username.lowercased()
                if lowered != profile.username.lowercased(), state.takenUsernames.contains(lowered) { throw ProfileError.usernameTaken }
                state.takenUsernames.remove(profile.username.lowercased())
                state.takenUsernames.insert(lowered)
                profile.username = username
            }
            if let displayName { profile.displayName = displayName }
            state.profiles[userID] = profile
            return profile
        }
    }

    public func updateAvatar(path: String?, for userID: UserID) async throws -> UserProfile {
        try state.withLock { state in
            state.avatarUpdates.append(path)
            if let error = state.error { throw error }
            guard var profile = state.profiles[userID] else { throw ProfileError.notAuthenticated }
            profile.avatarPath = path
            state.profiles[userID] = profile
            return profile
        }
    }

    public func updateDiscoverable(_ discoverable: Bool, for userID: UserID) async throws -> UserProfile {
        try state.withLock { state in
            state.discoverableUpdates.append(discoverable)
            if let error = state.error { throw error }
            guard var profile = state.profiles[userID] else { throw ProfileError.notAuthenticated }
            profile.isDiscoverable = discoverable
            state.profiles[userID] = profile
            return profile
        }
    }
}

public final class InMemoryProfileCache: ProfileCaching, Sendable {
    public let storage = Locked<[UserID: UserProfile]>([:])

    public init(_ profiles: [UserProfile] = []) {
        storage.withLock { storage in
            for profile in profiles { storage[profile.id] = profile }
        }
    }

    public func load(for userID: UserID) -> UserProfile? {
        storage.withLock { $0[userID] }
    }

    public func save(_ profile: UserProfile) {
        storage.withLock { $0[profile.id] = profile }
    }
}

// MARK: - Regions

public final class RegionRepositoryStub: RegionRepository, Sendable {
    public struct State: Sendable {
        public var hierarchies: [RegionHierarchy] = Fixtures.allHierarchies
        public var error: RegionError?
        public var searchQueries: [String] = []
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func searchMunicipalities(matching query: String, limit: Int) async throws -> [RegionHierarchy] {
        try state.withLock { state in
            state.searchQueries.append(query)
            if let error = state.error { throw error }
            let matches = state.hierarchies.filter {
                $0.municipality.name.lowercased().contains(query.lowercased())
            }
            return Array(matches.prefix(limit))
        }
    }

    public func hierarchy(forMunicipality id: RegionID) async throws -> RegionHierarchy {
        try state.withLock { state in
            if let error = state.error { throw error }
            guard let hierarchy = state.hierarchies.first(where: { $0.municipality.id == id }) else {
                throw RegionError.notFound
            }
            return hierarchy
        }
    }
}

// MARK: - Leaderboard

public final class LeaderboardRepositoryStub: LeaderboardRepository, Sendable {
    public struct State: Sendable {
        /// Vollständiges, bereits sortiertes Ranking je Region.
        public var rankings: [RegionID: [LeaderboardEntry]] = [:]
        public var error: LeaderboardError?
        public var pageRequests: [(query: LeaderboardQuery, offset: Int, limit: Int)] = []
        public var neighborhoodRequests: [(query: LeaderboardQuery, radius: Int)] = []
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func page(for query: LeaderboardQuery, offset: Int, limit: Int) async throws -> LeaderboardPage {
        try state.withLock { state in
            state.pageRequests.append((query, offset, limit))
            if let error = state.error { throw error }
            let all = state.rankings[query.regionID] ?? []
            let entries = Array(all.dropFirst(offset).prefix(limit))
            return LeaderboardPage(entries: entries, totalParticipants: all.count, offset: offset, limit: limit)
        }
    }

    public func neighborhood(for query: LeaderboardQuery, radius: Int) async throws -> [LeaderboardEntry] {
        try state.withLock { state in
            state.neighborhoodRequests.append((query, radius))
            if let error = state.error { throw error }
            let all = state.rankings[query.regionID] ?? []
            guard let me = all.first(where: \.isCurrentUser) else { return [] }
            return all.filter { abs($0.rank - me.rank) <= radius }
        }
    }
}

// MARK: - Activity Sync

public final class ActivitySyncRepositoryStub: ActivitySyncRepository, Sendable {
    public struct State: Sendable {
        public var uploads: [[DailyCompetitionSteps]] = []
        public var error: ActivitySyncError?
    }

    public let state = Locked(State())

    public init() {}

    public func upsert(_ days: [DailyCompetitionSteps], for userID: UserID) async throws {
        try state.withLock { state in
            if let error = state.error { throw error }
            state.uploads.append(days)
        }
    }
}

/// Zeichnet Sync-Aufrufe auf, ohne etwas zu senden.
public final class ActivitySyncingSpy: ActivitySyncing, Sendable {
    public struct State: Sendable {
        public var submissions: [(overview: ActivityOverview, trigger: ActivitySyncTrigger)] = []
        public var flushes = 0
    }

    public let state = Locked(State())

    public init() {}

    public var triggers: [ActivitySyncTrigger] {
        state.withLock { $0.submissions.map(\.trigger) }
    }

    public func submit(_ overview: ActivityOverview, trigger: ActivitySyncTrigger) async {
        state.withLock { $0.submissions.append((overview, trigger)) }
    }

    public func flush() async {
        state.withLock { $0.flushes += 1 }
    }
}
