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
        #expect(RankingHint.isTied(currentUser: me, above: entry(4, 7_000)))
        #expect(RankingHint.stepsToNextPlace(currentUser: me, above: entry(4, 7_000)) == 1)
        #expect(
            RankingHint.text(currentUser: me, above: entry(4, 7_000), isAlone: false, locative: "in Hessen")
                == "Gleichstand mit Platz #4 – noch 1 Schritt zum Überholen"
        )
        #expect(!RankingHint.isTied(currentUser: me, above: entry(4, 7_001)))
        #expect(RankingHint.text(currentUser: me, above: entry(4, 7_001), isAlone: false, locative: "in Hessen") == "Noch 2 Schritte bis Platz #4")
    }

    @Test func hintsFollowTheAppLanguage() {
        let me = entry(12, 8_432, me: true)
        let above = entry(11, 9_712)
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(RankingHint.text(currentUser: me, above: above, isAlone: false, locative: "in Pfungstadt") == "1,281 more steps to rank #11")
            #expect(RankingHint.text(currentUser: entry(1, 9_000, me: true), above: nil, isAlone: false, locative: "in Hessen") == "You're in the lead in Hessen.")
            #expect(RankingHint.text(currentUser: entry(5, 7_000, me: true), above: entry(4, 7_000), isAlone: false, locative: "in Hessen") == "Tied with rank #4 – 1 more step to overtake")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(RankingHint.text(currentUser: me, above: above, isAlone: false, locative: "в рейтинге «Pfungstadt»") == "Ещё \(1_281.paceFormatted) шаг до места #11")
            #expect(1_281.paceFormatted.contains("\u{00A0}") || 1_281.paceFormatted.contains("\u{202F}"))
            #expect(RankingHint.text(currentUser: entry(12, 100, me: true), above: entry(11, 104), isAlone: false, locative: "") == "Ещё 5 шагов до места #11")
            #expect(RankingHint.text(currentUser: entry(12, 100, me: true), above: entry(11, 102), isAlone: false, locative: "") == "Ещё 3 шага до места #11")
        }
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
