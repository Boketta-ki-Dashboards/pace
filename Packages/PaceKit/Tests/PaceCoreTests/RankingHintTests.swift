import Foundation
import PaceCore
import Testing

struct RankingHintTests {
    private func entry(_ rank: Int, _ steps: Int, me: Bool = false) -> LeaderboardEntry {
        LeaderboardEntry(rank: rank, publicUserID: UUID(), username: "u\(rank)", displayName: "U\(rank)", competitionSteps: steps, isCurrentUser: me)
    }

    @Test func overtakingNeedsOneStepMoreThanTheNextPlace() {
        let me = entry(12, 8_432, me: true)
        #expect(RankingHint.stepsToNextPlace(currentUser: me, above: entry(11, 8_712)) == 281)
        #expect(RankingHint.text(currentUser: me, above: entry(11, 8_712), isAlone: false, locative: "in Pfungstadt") == "Noch 281 Schritte bis Platz #11")
    }

    @Test func tieWithTheNextPlaceNeedsOneStep() {
        // Gleichstand: Der andere hatte den Wert zuerst und steht deshalb vorn.
        let me = entry(5, 7_000, me: true)
        #expect(RankingHint.text(currentUser: me, above: entry(4, 7_000), isAlone: false, locative: "in Hessen") == "Noch 1 Schritt bis Platz #4")
    }

    @Test func leaderAndLoneUserGetNoClimbHint() {
        let leader = entry(1, 20_000, me: true)
        #expect(RankingHint.stepsToNextPlace(currentUser: leader, above: nil) == nil)
        #expect(RankingHint.text(currentUser: leader, above: nil, isAlone: false, locative: "in Hessen") == "Du führst in Hessen.")
        #expect(RankingHint.text(currentUser: leader, above: nil, isAlone: true, locative: "in Hessen") == "Du bist der Erste in Hessen.")
    }

    @Test func missingOrNonAdjacentPlaceAboveGivesNoHint() {
        let me = entry(40, 3_000, me: true)
        #expect(RankingHint.text(currentUser: me, above: nil, isAlone: false, locative: "in Hessen") == nil)
        #expect(RankingHint.stepsToNextPlace(currentUser: me, above: entry(38, 3_500)) == nil)
    }
}
