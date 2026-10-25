import Foundation
@testable import HomeFeature
import PaceCore
import Testing

/// Eigene Inhalte je Widget (Auftrag 4, Punkt 12): Standard wie bisher, eigene Auswahl passend zur Größe, Speichern.
struct HomeWidgetDetailsTests {
    @Test func withoutOwnChoiceWidgetsShowWhatTheyShowedBefore() {
        #expect(HomeModule(kind: .stepsToday, size: .small).shownDetails.isEmpty)
        #expect(HomeModule(kind: .stepsToday, size: .medium).shownDetails == [.distanceEnergy])
        #expect(HomeModule(kind: .stepsToday, size: .large).shownDetails == [.distanceEnergy, .floorsExercise])
        // Max: Groß plus Analyse (7-Tage-Diagramm, Vergleich).
        #expect(HomeModule(kind: .stepsToday, size: .max).shownDetails == [.distanceEnergy, .floorsExercise, .weekChart, .comparison])
        #expect(HomeModule(kind: .streak, size: .small).shownDetails.isEmpty)
        #expect(HomeModule(kind: .streak, size: .medium).shownDetails == [.record])
        #expect(HomeModule(kind: .streak, size: .large).shownDetails == [.record, .week])
        #expect(HomeModule(kind: .streak, size: .max).shownDetails == [.record, .week, .recentDays])
        #expect(HomeModule(kind: .friends, size: .large).shownDetails.isEmpty)
        #expect(HomeModule(kind: .friends, size: .max).shownDetails == [.friendChart])
        #expect(HomeModule(kind: .groups, size: .large).shownDetails == [.groupProgress, .groupGoal])
        #expect(HomeModule(kind: .neighborhood, size: .small).shownDetails == [.rankGap])
        #expect(HomeModule(kind: .week, size: .max).shownDetails.isEmpty)
    }

    @Test func ownChoiceIsShownInFixedOrderAndFitsTheSize() {
        let all = HomeWidgetConfiguration(details: [.dayBest, .comparison, .floorsExercise, .distanceEnergy])
        // Mittel zeigt höchstens zwei, Groß drei, Max alle – immer in der festen Reihenfolge.
        #expect(HomeModule(kind: .stepsToday, size: .medium, configuration: all).shownDetails == [.distanceEnergy, .floorsExercise])
        #expect(HomeModule(kind: .stepsToday, size: .large, configuration: all).shownDetails.count == 3)
        #expect(HomeModule(kind: .stepsToday, size: .max, configuration: all).shownDetails == [.distanceEnergy, .floorsExercise, .comparison, .dayBest])

        let best = HomeWidgetConfiguration(details: [.dayBest])
        #expect(HomeModule(kind: .stepsToday, size: .medium, configuration: best).shownDetails == [.dayBest])

        let milestone = HomeWidgetConfiguration(details: [.milestone, .record])
        #expect(HomeModule(kind: .streak, size: .medium, configuration: milestone).shownDetails == [.record, .milestone])
        // Klein bleibt beim Wichtigsten.
        #expect(HomeModule(kind: .streak, size: .small, configuration: milestone).shownDetails.isEmpty)

        // Leere Auswahl heißt: keine Zusatzinhalte (nicht: Standard).
        let none = HomeWidgetConfiguration(details: [])
        #expect(HomeModule(kind: .stepsToday, size: .max, configuration: none).shownDetails.isEmpty)
        #expect(!HomeModule(kind: .neighborhood, size: .medium, configuration: none).shows(.rankGap))
    }

    @Test func theSevenDayChartNeedsAtLeastLarge() {
        let chart = HomeWidgetConfiguration(details: [.weekChart, .dayBest])
        #expect(HomeModule(kind: .stepsToday, size: .medium, configuration: chart).shownDetails == [.dayBest])
        #expect(HomeModule(kind: .stepsToday, size: .large, configuration: chart).shownDetails == [.weekChart, .dayBest])
        #expect(!HomeModuleKind.stepsToday.availableDetails(for: .medium).contains(.weekChart))
    }

    @Test func theFriendsChartNeedsAtLeastLarge() {
        let chart = HomeWidgetConfiguration(details: [.friendChart, .friendGap])
        #expect(HomeModule(kind: .friends, size: .medium, configuration: chart).shownDetails == [.friendGap])
        #expect(HomeModule(kind: .friends, size: .large, configuration: chart).shownDetails == [.friendGap, .friendChart])
        #expect(!HomeModuleKind.friends.availableDetails(for: .medium).contains(.friendChart))
    }

    @Test func onlyDetailsOfTheKindAreKept() {
        let mixed = HomeWidgetConfiguration(details: [.record, .dayBest, .friendGap])
        #expect(HomeModule(kind: .streak, configuration: mixed).configuration.details == [.record])
        #expect(HomeModule(kind: .stepsToday, configuration: mixed).configuration.details == [.dayBest])
        // Arten ohne Zusatzinhalte speichern keine.
        #expect(HomeModule(kind: .week, configuration: mixed).configuration.details == nil)
        #expect(HomeModule(kind: .week, configuration: mixed).configuration.isEmpty)
    }

    @Test func everyWidgetCanHaveItsOwnName() {
        let named = HomeWidgetConfiguration(customName: "  Meine   Flamme ")
        #expect(HomeModule(kind: .streak, configuration: named).title == "Meine Flamme")
        #expect(HomeModule(kind: .stepsToday, configuration: named).title == "Meine Flamme")
        #expect(HomeModule(kind: .groups, configuration: named).configuration.customName == "Meine Flamme")
        #expect(HomeModule(kind: .streak).title == HomeModuleKind.streak.title)
    }

    @Test func detailsAreStoredAndUnknownOnesAreSkipped() throws {
        let module = HomeModule(
            id: "steps",
            kind: .stepsToday,
            size: .large,
            configuration: HomeWidgetConfiguration(customName: "Heute", details: [.dayBest, .comparison])
        )
        let data = try JSONEncoder().encode(HomePreferences(modules: [module]))
        let decoded = try JSONDecoder().decode(HomePreferences.self, from: data)
        #expect(decoded.modules.first == module)

        let json = #"{"version":3,"modules":[{"id":"s","kind":"streak","size":"large","config":{"details":["milestone","futureThing"]}}]}"#
        let future = try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))
        #expect(future.modules.first?.configuration.details == [.milestone])

        // Ohne eigene Auswahl wird nichts gespeichert (das Widget folgt weiter seiner Größe).
        let plain = try JSONEncoder().encode(HomeModule(id: "w", kind: .streak))
        #expect(!String(decoding: plain, as: UTF8.self).contains("details"))
    }

    @Test func nextStreakMilestone() {
        #expect(StreakMilestone.next(after: 0) == 3)
        #expect(StreakMilestone.next(after: 5) == 7)
        #expect(StreakMilestone.next(after: 7) == 14)
        #expect(StreakMilestone.next(after: 364) == 365)
        #expect(StreakMilestone.next(after: 365) == 400)
        #expect(StreakMilestone.next(after: 450) == 500)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(StreakMilestone.text(current: 5) == "Noch 2 Tage bis zu 7 Tagen in Folge")
            #expect(StreakMilestone.text(current: 13) == "Noch 1 Tag bis zu 14 Tagen in Folge")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(StreakMilestone.text(current: 5) == "2 days more to reach 7 in a row")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(StreakMilestone.text(current: 5) == "Ещё 2 дня до 7 дней подряд")
            #expect(StreakMilestone.text(current: 20) == "Ещё 1 день до 21 дня подряд")
        }
    }

    @Test func friendsGapRefersToTheRealRankAhead() {
        let me = UUID()
        let ranking = [
            Self.entry(rank: 1, steps: 12_000),
            Self.entry(rank: 2, steps: 12_000),
            Self.entry(rank: 3, steps: 9_000),
            Self.entry(rank: 4, steps: 8_000),
            Self.entry(rank: 5, steps: 7_500),
            Self.entry(rank: 6, steps: 5_000, id: me, isCurrentUser: true),
        ]
        let widget = HomeFriendsWidget(ranking: ranking, friendIDs: nil, selection: nil)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(widget.gapText(for: widget.allRows[0]) == nil)
            #expect(widget.gapText(for: widget.allRows[1]) == "Gleichstand mit #1")
            #expect(widget.gapText(for: widget.allRows[2]) == "3.000 hinter #2")
            // Mittel: Die eigene Zeile ersetzt die dritte – der Abstand bezieht sich trotzdem auf Platz 5.
            let rows = widget.rows(for: .medium)
            let myRow = rows.last
            #expect(myRow?.entry.isCurrentUser == true)
            #expect(myRow.flatMap(widget.gapText(for:)) == "2.500 hinter #5")
        }
    }

    private static func entry(rank: Int, steps: Int, id: UUID = UUID(), isCurrentUser: Bool = false) -> LeaderboardEntry {
        LeaderboardEntry(
            rank: rank,
            publicUserID: id,
            username: "p\(rank)",
            displayName: "P\(rank)",
            competitionSteps: steps,
            isCurrentUser: isCurrentUser
        )
    }
}
