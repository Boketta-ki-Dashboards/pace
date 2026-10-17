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
        (RegionKind.landkreis, "Landkreis Musterland"),
        (.kreis, "Kreis Musterland"),
        (.stadtkreis, "Stadtkreis Musterland"),
        (.regionalverband, "Musterland"),
        (.kreisfreieStadt, "Musterland"),
    ])
    func districtDisplayNameIncludesKind(kind: RegionKind, expected: String) {
        let region = Region(id: "DE:99999", code: "99999", name: "Musterland", level: .district, kind: kind, parentID: "DE:99", municipalityCount: 5)

        #expect(region.displayName == expected)
    }

    /// Echte Namen aus dem GV100AD, die ihre Art schon enthalten, und die passende Präposition.
    @Test(arguments: [
        ("Darmstadt-Dieburg", RegionKind.landkreis, "Landkreis Darmstadt-Dieburg", "im Landkreis Darmstadt-Dieburg"),
        ("Main-Kinzig-Kreis", .landkreis, "Main-Kinzig-Kreis", "im Main-Kinzig-Kreis"),
        ("Landkreis Rostock", .landkreis, "Landkreis Rostock", "im Landkreis Rostock"),
        ("Region Hannover", .landkreis, "Region Hannover", "in der Region Hannover"),
        ("Städteregion Aachen", .kreis, "Städteregion Aachen", "in der Städteregion Aachen"),
        ("Rhein-Kreis Neuss", .kreis, "Rhein-Kreis Neuss", "im Rhein-Kreis Neuss"),
        ("Oberbergischer Kreis", .kreis, "Oberbergischer Kreis", "im Oberbergischen Kreis"),
        ("Rheinisch-Bergischer Kreis", .kreis, "Rheinisch-Bergischer Kreis", "im Rheinisch-Bergischen Kreis"),
        ("Nordfriesland", .kreis, "Kreis Nordfriesland", "im Kreis Nordfriesland"),
        ("Eifelkreis Bitburg-Prüm", .landkreis, "Eifelkreis Bitburg-Prüm", "im Eifelkreis Bitburg-Prüm"),
        ("Regionalverband Saarbrücken", .regionalverband, "Regionalverband Saarbrücken", "im Regionalverband Saarbrücken"),
    ])
    func realDistrictNames(name: String, kind: RegionKind, displayName: String, locative: String) {
        let region = Region(id: "DE:99999", code: "99999", name: name, level: .district, kind: kind, parentID: "DE:99", municipalityCount: 5)

        #expect(region.displayName == displayName)
        #expect(region.locative == locative)
    }

    @Test func locativeForOtherLevels() {
        let saarland = Region(id: "DE:10", code: "10", name: "Saarland", level: .state, kind: .state, parentID: "DE", municipalityCount: 52)

        #expect(Fixtures.pfungstadt.locative == "in Pfungstadt")
        #expect(Fixtures.hessen.locative == "in Hessen")
        #expect(saarland.locative == "im Saarland")
        #expect(Fixtures.germany.locative == "in Deutschland")
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
