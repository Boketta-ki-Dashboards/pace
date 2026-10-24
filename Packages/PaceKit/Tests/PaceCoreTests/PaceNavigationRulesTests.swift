import PaceCore
import Testing

/// Navigationspfade: dieselbe Seite nie zweimal, Rückweg bleibt der ursprüngliche.
struct PaceNavigationRulesTests {
    @Test func newPagesAreAppended() {
        #expect(PaceNavigationRules.opening("a", in: []) == ["a"])
        #expect(PaceNavigationRules.opening("b", in: ["a"]) == ["a", "b"])
    }

    @Test func theTopPageIsNotOpenedTwice() {
        #expect(PaceNavigationRules.opening("b", in: ["a", "b"]) == ["a", "b"])
    }

    @Test func aPageFurtherDownIsReturnedTo() {
        #expect(PaceNavigationRules.opening("a", in: ["a", "b", "c"]) == ["a"])
        #expect(PaceNavigationRules.opening("b", in: ["a", "b", "c"]) == ["a", "b"])
    }

    @Test func alternatingNeverGrows() {
        var path = ["gruppe"]
        for _ in 0..<50 {
            path = PaceNavigationRules.opening("chat", in: path)
            path = PaceNavigationRules.opening("gruppe", in: path)
        }
        #expect(path == ["gruppe"])
    }

    @Test func samePageUsesTheGivenIdentity() {
        // Gleiche Seite trotz anderer Anzeigedaten: Die vorhandene bleibt.
        let path = PaceNavigationRules.opening("Gruppe:1:neu", in: ["Gruppe:1:alt", "Chat:1"]) {
            $0.split(separator: ":").prefix(2) == $1.split(separator: ":").prefix(2)
        }
        #expect(path == ["Gruppe:1:alt"])
    }

    @Test func replacingTheTopPage() {
        #expect(PaceNavigationRules.replacingTop(with: "neu", in: ["a", "erstellen"], isSamePage: ==) == ["a", "neu"])
        #expect(PaceNavigationRules.replacingTop(with: "a", in: ["a", "b", "teilen"], isSamePage: ==) == ["a"])
        #expect(PaceNavigationRules.replacingTop(with: "a", in: [], isSamePage: ==) == ["a"])
    }
}
