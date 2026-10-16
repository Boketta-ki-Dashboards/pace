import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct RegionHierarchyTests {
    @Test func municipalityWithLandkreisHasFourLeaderboardLevels() {
        let scopes = Fixtures.pfungstadtHierarchy.leaderboardScopes

        #expect(scopes.map(\.name) == ["Pfungstadt", "Darmstadt-Dieburg", "Hessen", "Deutschland"])
        #expect(scopes.map(\.level) == [.municipality, .district, .state, .country])
    }

    @Test func kreisfreieStadtSkipsIdenticalDistrictLevel() {
        let scopes = Fixtures.frankfurtHierarchy.leaderboardScopes

        #expect(scopes.map(\.id) == ["DE:06412000", "DE:06", "DE"])
    }

    @Test func cityStateSkipsDistrictAndStateLevels() {
        let scopes = Fixtures.berlinHierarchy.leaderboardScopes

        #expect(scopes.map(\.id) == ["DE:11000000", "DE"])
    }

    @Test func hierarchyKeepsAllFourLevelsEvenWhenScopesAreReduced() {
        let hierarchy = Fixtures.frankfurtHierarchy

        #expect(hierarchy.allLevels.map(\.level) == [.municipality, .district, .state, .country])
        #expect(hierarchy.district.kind == .kreisfreieStadt)
    }

    @Test func subtitleShowsStateAndDistrictWithKind() {
        #expect(Fixtures.pfungstadtHierarchy.subtitle == "Hessen · Landkreis Darmstadt-Dieburg")
    }

    @Test func subtitleForKreisfreieStadt() {
        #expect(Fixtures.frankfurtHierarchy.subtitle == "Hessen · kreisfreie Stadt")
    }

    @Test func subtitleForCityState() {
        #expect(Fixtures.berlinHierarchy.subtitle == "Stadtstaat")
    }

    @Test(arguments: [
        (RegionKind.landkreis, "Landkreis Musterkreis"),
        (.kreis, "Kreis Musterkreis"),
        (.stadtkreis, "Stadtkreis Musterkreis"),
        (.regionalverband, "Musterkreis"),
        (.kreisfreieStadt, "Musterkreis"),
    ])
    func districtDisplayNameIncludesKind(kind: RegionKind, expected: String) {
        let region = Region(id: "DE:99999", code: "99999", name: "Musterkreis", level: .district, kind: kind, parentID: "DE:99", municipalityCount: 5)

        #expect(region.displayName == expected)
    }

    @Test func regionIDIsCodableAsPlainString() throws {
        let data = try JSONEncoder().encode(["id": RegionID("DE:06432018")])
        #expect(String(decoding: data, as: UTF8.self) == #"{"id":"DE:06432018"}"#)
    }
}

struct RegionSearchQueryTests {
    @Test func trimsAndCollapsesWhitespace() {
        #expect(RegionSearchQuery.normalized("  Frankfurt   am  Main ") == "Frankfurt am Main")
    }

    @Test(arguments: ["", " ", "P", " a "])
    func rejectsTooShortQueries(_ raw: String) {
        #expect(RegionSearchQuery.normalized(raw) == nil)
    }

    @Test func acceptsTwoCharacters() {
        #expect(RegionSearchQuery.normalized("Pf") == "Pf")
    }
}
