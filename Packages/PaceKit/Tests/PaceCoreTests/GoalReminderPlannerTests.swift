import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Tagesziel-Erinnerungen: passende Texte, keine veralteten Zahlen, iOS-Grenze für geplante Mitteilungen.
struct GoalReminderPlannerTests {
    private let calendar = Fixtures.activityCalendar
    private let today = Fixtures.day(2026, 10, 20)

    private func plan(
        _ times: [ReminderTime],
        steps: Int? = nil,
        measuredAt: Date? = nil,
        now: Date,
        goal: Int = 10_000
    ) -> [PlannedNotification] {
        let progress = steps.map {
            GoalProgressSnapshot(day: today, steps: $0, goal: goal, measuredAt: measuredAt ?? now)
        }
        return PaceLocalization.$languageOverride.withValue(.german) {
            GoalReminderPlanner.plan(times: times, goal: goal, progress: progress, now: now, calendar: calendar)
        }
    }

    private func todays(_ notifications: [PlannedNotification]) -> [PlannedNotification] {
        notifications.filter { $0.dateComponents.day == today.day && $0.dateComponents.month == today.month }
    }

    @Test func plansEveryTimeForTwoWeeksAndSkipsTimesAlreadyPassed() {
        let times = [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 19, minute: 30)]
        let planned = plan(times, now: Fixtures.date(2026, 10, 20, 12, 0))

        // Heute nur noch 19:30, danach 13 volle Tage mit je zwei Uhrzeiten.
        #expect(planned.count == 1 + 13 * 2)
        #expect(todays(planned).map(\.dateComponents.hour) == [19])
        #expect(planned.first?.identifier == "pace.goal-reminder.2026-10-20-1930")
        #expect(Set(planned.map(\.identifier)).count == planned.count)
        let last = planned.last?.dateComponents
        #expect(last?.year == 2026 && last?.month == 11 && last?.day == 2 && last?.hour == 19 && last?.minute == 30)
    }

    @Test func manyTimesStayBelowTheIOSLimit() {
        let times = (0..<6).map { ReminderTime(hour: 8 + 2 * $0, minute: 0) }
        #expect(GoalReminderPlanner.plannedDays(timesPerDay: 6) == 10)
        #expect(GoalReminderPlanner.plannedDays(timesPerDay: 1) == 14)
        #expect(GoalReminderPlanner.plannedDays(timesPerDay: 0) == 14)

        let planned = plan(times, now: Fixtures.date(2026, 10, 20, 6, 0))
        #expect(planned.count == 60)
        #expect(planned.count <= GoalReminderPlanner.maximumPending)
    }

    @Test func morningRemindersMentionTheGoalNotTheRemainingSteps() {
        let planned = plan([ReminderTime(hour: 9, minute: 0)], steps: 1_200, now: Fixtures.date(2026, 10, 20, 8, 30))
        let first = todays(planned).first

        #expect(first?.title == "Vergiss dein Tagesziel nicht!")
        #expect(first?.body.contains("fehlen") == false)
    }

    @Test func freshProgressNamesTheMissingSteps() {
        let now = Fixtures.date(2026, 10, 20, 18, 0)
        let planned = plan([ReminderTime(hour: 19, minute: 0)], steps: 6_000, now: now)
        let expected = PaceLocalization.$languageOverride.withValue(.german) { PaceLocalization.steps(4_000) }

        #expect(todays(planned).first?.body == "Dir fehlen noch \(expected) bis zu deinem Tagesziel.")
        // Für die folgenden Tage gibt es noch keinen Stand – also keine Zahl.
        #expect(planned.dropFirst().allSatisfy { !$0.body.contains("fehlen") })
    }

    @Test func staleProgressFallsBackToAGeneralText() {
        // Gemessen um 16 Uhr, Zustellung um 19 Uhr: drei Stunden alt – die Zahl könnte längst falsch sein.
        let planned = plan(
            [ReminderTime(hour: 19, minute: 0)],
            steps: 6_000,
            measuredAt: Fixtures.date(2026, 10, 20, 16, 0),
            now: Fixtures.date(2026, 10, 20, 16, 5)
        )
        let reminder = todays(planned).first

        #expect(reminder?.title == "Dein Tagesziel wartet")
        #expect(reminder?.body.contains("fehlen") == false)
        #expect(reminder?.body.contains("4") == false)
    }

    @Test func almostReachedGetsItsOwnText() {
        let now = Fixtures.date(2026, 10, 20, 20, 0)
        let planned = plan([ReminderTime(hour: 21, minute: 0)], steps: 9_300, now: now)
        let expected = PaceLocalization.$languageOverride.withValue(.german) { PaceLocalization.steps(700) }

        #expect(todays(planned).first?.title == "Nur noch \(expected)!")
        #expect(todays(planned).first?.body == "Dein Tagesziel ist fast geschafft.")

        // Kleine Ziele: mindestens 500 Schritte gelten als „fast geschafft“.
        let small = plan([ReminderTime(hour: 21, minute: 0)], steps: 2_550, now: now, goal: 3_000)
        #expect(todays(small).first?.body == "Dein Tagesziel ist fast geschafft.")
    }

    @Test func reachedGoalSkipsTodayButNotTheFollowingDays() {
        let times = [ReminderTime(hour: 19, minute: 0), ReminderTime(hour: 21, minute: 0)]
        let planned = plan(times, steps: 10_400, now: Fixtures.date(2026, 10, 20, 17, 0))

        #expect(todays(planned).isEmpty)
        #expect(planned.count == 13 * 2)
    }

    @Test func progressOfAnotherDayIsIgnored() {
        let yesterday = GoalProgressSnapshot(
            day: Fixtures.day(2026, 10, 19), steps: 12_000, goal: 10_000, measuredAt: Fixtures.date(2026, 10, 19, 23, 0)
        )
        let planned = GoalReminderPlanner.plan(
            times: [ReminderTime(hour: 19, minute: 0)],
            goal: 10_000,
            progress: yesterday,
            now: Fixtures.date(2026, 10, 20, 7, 0),
            calendar: calendar
        )

        // Gestern erreicht heißt nicht heute erreicht.
        #expect(todays(planned).count == 1)
    }

    @Test func nonexistentTimeOnTheDaylightSavingDayIsSkipped() {
        // 29.03.2026: In Berlin springt die Uhr von 2:00 auf 3:00.
        let planned = GoalReminderPlanner.plan(
            times: [ReminderTime(hour: 2, minute: 30)],
            goal: 10_000,
            progress: nil,
            now: Fixtures.date(2026, 3, 28, 12, 0),
            calendar: calendar
        )

        #expect(!planned.contains { $0.dateComponents.month == 3 && $0.dateComponents.day == 29 })
        #expect(planned.contains { $0.dateComponents.month == 3 && $0.dateComponents.day == 30 })
        #expect(calendar.date(Fixtures.day(2026, 3, 29), hour: 2, minute: 30) == nil)
        #expect(calendar.date(Fixtures.day(2026, 3, 29), hour: 3, minute: 0) != nil)
    }

    @Test func textsExistInAllLanguages() {
        let progress = GoalProgressSnapshot(day: today, steps: 6_000, goal: 10_000, measuredAt: Fixtures.date(2026, 10, 20, 18, 0))
        let bodies = AppLanguage.allCases.map { language in
            PaceLocalization.$languageOverride.withValue(language) {
                GoalReminderPlanner.plan(
                    times: [ReminderTime(hour: 19, minute: 0)],
                    goal: 10_000,
                    progress: progress,
                    now: Fixtures.date(2026, 10, 20, 18, 0),
                    calendar: calendar
                ).first?.body ?? ""
            }
        }

        #expect(bodies.allSatisfy { !$0.isEmpty })
        #expect(Set(bodies).count == AppLanguage.allCases.count)
    }

    @Test func successMessageIsOncePerDay() {
        let success = PaceLocalization.$languageOverride.withValue(.german) {
            GoalReminderPlanner.success(steps: 10_250, day: today)
        }
        let expected = PaceLocalization.$languageOverride.withValue(.german) { PaceLocalization.steps(10_250) }

        #expect(success.identifier == "pace.goal-reached.2026-10-20")
        #expect(success.title == "Geschafft!")
        #expect(success.body == "Du hast dein Tagesziel erreicht – \(expected) heute.")
    }
}

/// Mehrere Uhrzeiten je Tag und die Übernahme der Einstellung älterer Versionen.
struct StreakReminderSettingsTests {
    @Test func timesAreSortedUniqueAndLimited() {
        var settings = StreakReminderSettings(isEnabled: true, hour: 19, minute: 0)
        settings.add(ReminderTime(hour: 8, minute: 0))
        settings.add(ReminderTime(hour: 19, minute: 0))
        #expect(settings.times == [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 19, minute: 0)])
        #expect(settings.hour == 8)

        for hour in [10, 12, 14, 16, 18] {
            settings.add(ReminderTime(hour: hour, minute: 15))
        }
        #expect(settings.times.count == StreakReminderSettings.maximumTimes)
        #expect(!settings.canAddTime)
    }

    @Test func theLastTimeCannotBeRemoved() {
        var settings = StreakReminderSettings(
            isEnabled: true, times: [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 20, minute: 0)]
        )
        settings.remove(ReminderTime(hour: 8, minute: 0))
        settings.remove(ReminderTime(hour: 20, minute: 0))

        #expect(settings.times == [ReminderTime(hour: 20, minute: 0)])
    }

    @Test func replacingKeepsTheListSorted() {
        var settings = StreakReminderSettings(
            isEnabled: true, times: [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 20, minute: 0)]
        )
        settings.replace(ReminderTime(hour: 20, minute: 0), with: ReminderTime(hour: 6, minute: 45))
        #expect(settings.times == [ReminderTime(hour: 6, minute: 45), ReminderTime(hour: 8, minute: 0)])

        // Auf eine schon vorhandene Uhrzeit gelegt: keine Doppelten.
        settings.replace(ReminderTime(hour: 6, minute: 45), with: ReminderTime(hour: 8, minute: 0))
        #expect(settings.times == [ReminderTime(hour: 8, minute: 0)])
    }

    @Test func emptyListFallsBackToTheDefaultTime() {
        let settings = StreakReminderSettings(isEnabled: true, times: [])
        #expect(settings.times == [StreakReminderSettings.defaultTime])
    }

    @Test func suggestedTimeIsNotYetUsed() {
        var settings = StreakReminderSettings(isEnabled: true, hour: 8, minute: 0)
        for _ in 0..<5 {
            let suggestion = settings.suggestedNextTime
            #expect(!settings.times.contains(suggestion))
            settings.add(suggestion)
        }
        #expect(settings.times.count == 6)
    }

    @Test func settingOfAnOlderVersionIsTakenOver() throws {
        let json = Data(#"{"isEnabled":true,"hour":7,"minute":30}"#.utf8)
        let decoded = try JSONDecoder().decode(StreakReminderSettings.self, from: json)

        #expect(decoded.isEnabled)
        #expect(decoded.times == [ReminderTime(hour: 7, minute: 30)])
    }

    @Test func roundTripKeepsAllTimesAndTheFirstForOlderVersions() throws {
        let settings = StreakReminderSettings(
            isEnabled: true, times: [ReminderTime(hour: 21, minute: 0), ReminderTime(hour: 9, minute: 15)]
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(StreakReminderSettings.self, from: data)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(decoded == settings)
        // Ältere Versionen lesen „hour“/„minute“ und sehen die erste Uhrzeit.
        #expect(object["hour"] as? Int == 9)
        #expect(object["minute"] as? Int == 15)
    }

    @Test func invalidValuesAreClamped() {
        let time = ReminderTime(hour: 27, minute: -5)
        #expect(time.hour == 23 && time.minute == 0)
    }
}
