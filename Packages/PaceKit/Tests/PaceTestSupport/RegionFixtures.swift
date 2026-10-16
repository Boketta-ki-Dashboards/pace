import Foundation
import PaceCore

/// Regionen mit echten amtlichen Schlüsseln (GV100AD, Stand 30.09.2026). Die Gemeindezahlen sind für Tests
/// vereinfacht, die Hierarchie entspricht dem Gemeindeverzeichnis.
public extension Fixtures {
    static let germany = Region(id: "DE", code: "DE", name: "Deutschland", level: .country, kind: .country, parentID: nil, municipalityCount: 10_749)

    static let hessen = Region(id: "DE:06", code: "06", name: "Hessen", level: .state, kind: .state, parentID: "DE", municipalityCount: 421)
    static let darmstadtDieburg = Region(id: "DE:06432", code: "06432", name: "Darmstadt-Dieburg", level: .district, kind: .landkreis, parentID: "DE:06", municipalityCount: 23)
    static let pfungstadt = Region(id: "DE:06432018", code: "06432018", name: "Pfungstadt", level: .municipality, kind: .stadt, parentID: "DE:06432", municipalityCount: 1)
    static let griesheim = Region(id: "DE:06432010", code: "06432010", name: "Griesheim", level: .municipality, kind: .stadt, parentID: "DE:06432", municipalityCount: 1)

    static let frankfurtDistrict = Region(id: "DE:06412", code: "06412", name: "Frankfurt am Main", level: .district, kind: .kreisfreieStadt, parentID: "DE:06", municipalityCount: 1)
    static let frankfurt = Region(id: "DE:06412000", code: "06412000", name: "Frankfurt am Main", level: .municipality, kind: .kreisfreieStadt, parentID: "DE:06412", municipalityCount: 1)

    static let berlinState = Region(id: "DE:11", code: "11", name: "Berlin", level: .state, kind: .state, parentID: "DE", municipalityCount: 1)
    static let berlinDistrict = Region(id: "DE:11000", code: "11000", name: "Berlin", level: .district, kind: .kreisfreieStadt, parentID: "DE:11", municipalityCount: 1)
    static let berlin = Region(id: "DE:11000000", code: "11000000", name: "Berlin", level: .municipality, kind: .kreisfreieStadt, parentID: "DE:11000", municipalityCount: 1)

    static let pfungstadtHierarchy = RegionHierarchy(municipality: pfungstadt, district: darmstadtDieburg, state: hessen, country: germany)
    static let griesheimHierarchy = RegionHierarchy(municipality: griesheim, district: darmstadtDieburg, state: hessen, country: germany)
    static let frankfurtHierarchy = RegionHierarchy(municipality: frankfurt, district: frankfurtDistrict, state: hessen, country: germany)
    static let berlinHierarchy = RegionHierarchy(municipality: berlin, district: berlinDistrict, state: berlinState, country: germany)

    static let allHierarchies = [pfungstadtHierarchy, griesheimHierarchy, frankfurtHierarchy, berlinHierarchy]
}

public extension Fixtures {
    static let userID = UserID(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
    static let publicUserID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!

    static func profile(
        id: UserID = userID,
        username: String = "niklas",
        displayName: String = "Niklas",
        municipalityID: RegionID? = pfungstadt.id,
        regionalLeaderboardEnabled: Bool = false
    ) -> UserProfile {
        UserProfile(
            id: id,
            publicID: publicUserID,
            username: username,
            displayName: displayName,
            municipalityID: municipalityID,
            regionalLeaderboardEnabled: regionalLeaderboardEnabled,
            createdAt: Fixtures.date(2026, 10, 1, 12),
            updatedAt: Fixtures.date(2026, 10, 1, 12)
        )
    }

    /// Ein Ranking mit `count` Einträgen absteigend nach Schritten; optional ist Platz `currentUserRank` der Nutzer selbst.
    static func ranking(count: Int, currentUserRank: Int? = nil, topSteps: Int = 20_000) -> [LeaderboardEntry] {
        (1...max(count, 1)).prefix(count).map { rank in
            let isMe = rank == currentUserRank
            return LeaderboardEntry(
                rank: rank,
                publicUserID: isMe ? publicUserID : UUID(uuidString: String(format: "20000000-0000-4000-8000-%012d", rank))!,
                username: isMe ? "niklas" : "user\(rank)",
                displayName: isMe ? "Niklas" : "Nutzer \(rank)",
                competitionSteps: max(topSteps - rank * 10, 0),
                isCurrentUser: isMe
            )
        }
    }
}
