import Foundation
import PaceCore
import PaceTestSupport
import Testing

struct StepGoalHistoryTests {
    private let oct16 = Fixtures.day(2026, 10, 16)

    @Test func goalAppliesFromItsDayOnward() {
        var history = StepGoalHistory(initialGoal: 10_000)
        history.setGoal(8_000, from: Fixtures.day(2026, 10, 10))
        history.setGoal(12_000, from: oct16)

        #expect(history.goal(on: Fixtures.day(2020, 1, 1)) == 10_000)
        #expect(history.goal(on: Fixtures.day(2026, 10, 9)) == 10_000)
        #expect(history.goal(on: Fixtures.day(2026, 10, 10)) == 8_000)
        #expect(history.goal(on: Fixtures.day(2026, 10, 15)) == 8_000)
        #expect(history.goal(on: oct16) == 12_000)
        #expect(history.goal(on: Fixtures.day(2027, 1, 1)) == 12_000)
    }

    @Test func changingTheGoalTwiceOnOneDayKeepsTheLastValue() {
        var history = StepGoalHistory(initialGoal: 10_000)
        history.setGoal(8_000, from: oct16)
        history.setGoal(9_000, from: oct16)

        #expect(history.changes.count == 2)
        #expect(history.goal(on: oct16) == 9_000)

        // Zurück zum vorherigen Ziel: keine überflüssige Änderung.
        history.setGoal(10_000, from: oct16)
        #expect(history.changes.count == 1)
    }

    @Test func laterChangesAreDiscardedWhenSettingAnEarlierDay() {
        // z. B. nach einer Reise in eine frühere Zeitzone.
        var history = StepGoalHistory(initialGoal: 10_000)
        history.setGoal(12_000, from: Fixtures.day(2026, 10, 17))
        history.setGoal(7_000, from: oct16)

        #expect(history.goal(on: Fixtures.day(2026, 10, 17)) == 7_000)
        #expect(history.changes.map(\.goal) == [10_000, 7_000])
    }

    @Test func goalsAreClampedAndRounded() {
        var history = StepGoalHistory(initialGoal: 123)
        #expect(history.goal(on: oct16) == 1_000)
        history.setGoal(12_340, from: oct16)
        #expect(history.goal(on: oct16) == 12_500)
        history.setGoal(999_999, from: oct16)
        #expect(history.goal(on: oct16) == 50_000)
        #expect(StepGoalRules.options.first == 1_000)
        #expect(StepGoalRules.options.last == 50_000)
    }

    @Test func storedHistoryIsRepaired() throws {
        let json = #"{"changes":[{"effectiveFrom":"2026-10-16","goal":12000},{"effectiveFrom":"2000-01-01","goal":10000},{"effectiveFrom":"2026-10-16","goal":12345}]}"#
        let history = try JSONDecoder().decode(StepGoalHistory.self, from: Data(json.utf8))

        #expect(history.changes.map(\.effectiveFrom) == [StepGoalHistory.origin, oct16])
        #expect(history.goal(on: oct16) == 12_500)

        let empty = StepGoalHistory(changes: [])
        #expect(empty.goal(on: oct16) == StepGoalRules.defaultGoal)

        let roundTrip = try JSONDecoder().decode(StepGoalHistory.self, from: JSONEncoder().encode(history))
        #expect(roundTrip == history)
    }

    @MainActor
    @Test func settingsTakeOverTheLegacyGoalOnceAndPersistChanges() {
        let store = InMemoryStepGoalStore()
        let now: @Sendable () -> Date = { Fixtures.date(2026, 10, 16, 9) }
        let settings = StepGoalSettings(store: store, legacyGoal: 12_000, calendar: Fixtures.activityCalendar, now: now)

        #expect(settings.currentGoal == 12_000)
        #expect(store.load()?.goal(on: Fixtures.day(2026, 1, 1)) == 12_000)

        settings.setGoal(8_000)
        #expect(settings.currentGoal == 8_000)
        #expect(settings.goal(on: Fixtures.day(2026, 10, 15)) == 12_000)

        // Ein erneuter Start übernimmt den Verlauf, nicht mehr das alte Ziel.
        let restarted = StepGoalSettings(store: store, legacyGoal: 5_000, calendar: Fixtures.activityCalendar, now: now)
        #expect(restarted.currentGoal == 8_000)
        #expect(restarted.goal(on: Fixtures.day(2026, 10, 15)) == 12_000)
    }

    @MainActor
    @Test func settingsDefaultToTenThousandSteps() {
        let settings = StepGoalSettings(store: InMemoryStepGoalStore(), calendar: Fixtures.activityCalendar)
        #expect(settings.currentGoal == 10_000)
    }
}
