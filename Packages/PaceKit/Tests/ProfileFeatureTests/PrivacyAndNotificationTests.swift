import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Privatsphäre (Auffindbarkeit, blockierte Personen) und Mitteilungen (lokale Erinnerung).
@MainActor
struct PrivacyAndNotificationTests {
    private static let leon = SocialProfile(publicID: UUID(), username: "leon", displayName: "Leon")
    private static let anna = SocialProfile(publicID: UUID(), username: "anna", displayName: "anna")

    // MARK: Auffindbarkeit

    @Test func discoverabilityIsSavedOnTheServer() async {
        let env = ProfileSettingsEnvironment()
        let privacy = env.viewModel.privacy
        #expect(privacy.isDiscoverable)

        await privacy.setDiscoverable(false)

        #expect(!privacy.isDiscoverable)
        #expect(!privacy.discoverableToggleValue)
        #expect(env.profiles.state.withLock { $0.discoverableUpdates } == [false])
        #expect(env.cache.load(for: Fixtures.userID)?.isDiscoverable == false)
        #expect(privacy.discoverableError == nil)
        #expect(privacy.discoverableExplanation.contains("vollständig und genau"))
    }

    @Test func failedDiscoverabilityChangeKeepsTheValueAndShowsAnError() async {
        let env = ProfileSettingsEnvironment()
        env.profiles.state.withLock { $0.error = .network }

        await env.viewModel.privacy.setDiscoverable(false)

        #expect(env.viewModel.privacy.isDiscoverable)
        #expect(env.viewModel.privacy.discoverableToggleValue)
        #expect(env.viewModel.privacy.discoverableError != nil)
        #expect(!env.viewModel.privacy.isUpdatingDiscoverable)
    }

    @Test func discoverabilityWithoutServerSupportSaysSoInsteadOfRetry() async {
        let env = ProfileSettingsEnvironment()
        env.profiles.state.withLock { $0.error = .unavailable }

        await env.viewModel.privacy.setDiscoverable(false)

        #expect(env.viewModel.privacy.isDiscoverable)
        #expect(env.viewModel.privacy.discoverableError == "Diese Funktion ist auf dem Server noch nicht eingerichtet.")
    }

    // MARK: Blockierte Personen

    @Test func blockedUsersAreLoadedSortedAndCanBeUnblocked() async {
        let social = SocialRepositoryStub { $0.blocked = [Self.leon, Self.anna] }
        let env = ProfileSettingsEnvironment(social: social)
        let blocked = env.viewModel.privacy.blockedUsers

        await blocked.load()
        #expect(blocked.state == .loaded)
        #expect(blocked.users.map(\.username) == ["anna", "leon"])

        await blocked.unblock(Self.leon)
        #expect(blocked.users.map(\.username) == ["anna"])
        #expect(social.state.withLock { $0.blocked }.map(\.username) == ["anna"])
        #expect(blocked.actionError == nil)
        #expect(blocked.busyIDs.isEmpty)
    }

    @Test func failedUnblockKeepsThePersonAndShowsAnError() async {
        let social = SocialRepositoryStub { state in
            state.blocked = [Self.leon]
            state.actionError = .network
        }
        let env = ProfileSettingsEnvironment(social: social)
        let blocked = env.viewModel.privacy.blockedUsers
        await blocked.load()

        await blocked.unblock(Self.leon)

        #expect(blocked.users == [Self.leon])
        #expect(blocked.actionError == SocialError.network.message)
    }

    @Test func failedLoadAndMissingBackendAreReported() async {
        let failing = ProfileSettingsEnvironment(social: SocialRepositoryStub { $0.error = .network })
        await failing.viewModel.privacy.blockedUsers.load()
        #expect(failing.viewModel.privacy.blockedUsers.state == .failed(SocialError.network.message))

        let offline = ProfileSettingsEnvironment(withBackend: false)
        #expect(offline.viewModel.privacy.blockedUsers.state == .unavailable)
        #expect(!offline.viewModel.privacy.blockedUsers.isAvailable)
    }

    // MARK: Mitteilungen

    private func makeNotifications(
        scheduler: NotificationSchedulerStub,
        reminder: StreakReminderSettings = StreakReminderSettings(),
        goalReached: @escaping @MainActor () -> Bool = { false },
        progress: @escaping @MainActor () -> GoalProgressSnapshot? = { nil },
        now: @escaping @Sendable () -> Date = { Fixtures.date(2026, 10, 20, 9) }
    ) -> (NotificationSettingsViewModel, AppSettings, InMemoryAppPreferencesStore) {
        let store = InMemoryAppPreferencesStore(AppPreferences(language: .fixed(.german), streakReminder: reminder))
        let settings = AppSettings(store: store, preferredLanguages: { [] }, applyLanguage: { _ in })
        let viewModel = NotificationSettingsViewModel(
            settings: settings,
            notifications: scheduler,
            isTodayGoalReached: goalReached,
            todayProgress: progress,
            currentGoal: { 10_000 },
            calendar: Fixtures.activityCalendar,
            now: now
        )
        return (viewModel, settings, store)
    }

    @Test func enablingTheReminderAsksForPermissionAndSchedules() async {
        let scheduler = NotificationSchedulerStub()
        let (viewModel, _, store) = makeNotifications(scheduler: scheduler)

        await viewModel.setReminderEnabled(true)

        #expect(viewModel.reminder.isEnabled)
        #expect(store.load().streakReminder.isEnabled)
        #expect(viewModel.authorization == .authorized)
        let scheduled = scheduler.state.withLock { $0.scheduled }
        #expect(scheduled.count == 1)
        // 19:00 an 14 Tagen, beginnend heute (20.10., 9 Uhr).
        #expect(scheduled.first?.count == 14)
        #expect(scheduled.first?.first?.dateComponents.day == 20)
        #expect(scheduled.first?.first?.dateComponents.hour == 19)
    }

    @Test func deniedPermissionKeepsTheReminderOff() async {
        let scheduler = NotificationSchedulerStub { $0.grantsOnRequest = false }
        let (viewModel, _, store) = makeNotifications(scheduler: scheduler)

        await viewModel.setReminderEnabled(true)

        #expect(!viewModel.reminder.isEnabled)
        #expect(!store.load().streakReminder.isEnabled)
        #expect(viewModel.authorization == .denied)
        #expect(viewModel.message == NotificationSettingsViewModel.deniedMessage)
        #expect(scheduler.state.withLock { $0.scheduled }.isEmpty)
        #expect(viewModel.statusTitle == "Mitteilungen ausgeschaltet")
    }

    @Test func turningTheReminderOffCancelsIt() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let (viewModel, _, _) = makeNotifications(scheduler: scheduler, reminder: StreakReminderSettings(isEnabled: true))

        await viewModel.setReminderEnabled(false)

        #expect(!viewModel.reminder.isEnabled)
        #expect(scheduler.state.withLock { $0.cancelCalls } == 1)
        #expect(scheduler.state.withLock { $0.scheduled }.isEmpty)
    }

    @Test func changingTheTimeReschedulesOnlyWhenSomethingChanged() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let (viewModel, _, store) = makeNotifications(scheduler: scheduler, reminder: StreakReminderSettings(isEnabled: true))

        await viewModel.reschedule()
        await viewModel.reschedule() // unverändert → kein zweites Planen
        await viewModel.setReminderTime(hour: 7, minute: 45)

        let scheduled = scheduler.state.withLock { $0.scheduled }
        #expect(scheduled.count == 2)
        #expect(scheduled.last?.first?.dateComponents.hour == 7)
        #expect(scheduled.last?.first?.dateComponents.minute == 45)
        #expect(store.load().streakReminder == StreakReminderSettings(isEnabled: true, hour: 7, minute: 45))
        // Deutsch „07:45“ (je nach Plattform-ICU auch „7:45“), Englisch mit AM/PM.
        #expect(viewModel.reminderTimeText.hasSuffix("7:45"))
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(viewModel.reminderTimeText.contains("AM"))
        }
    }

    @Test func severalTimesAreAddedEditedRemovedAndStored() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let (viewModel, _, store) = makeNotifications(scheduler: scheduler, reminder: StreakReminderSettings(isEnabled: true))

        await viewModel.addReminderTime(ReminderTime(hour: 8, minute: 0))
        await viewModel.addReminderTime(ReminderTime(hour: 12, minute: 30))
        await viewModel.addReminderTime(ReminderTime(hour: 12, minute: 30)) // doppelt → ignoriert
        #expect(viewModel.reminder.times == [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 12, minute: 30), ReminderTime(hour: 19, minute: 0)])
        #expect(viewModel.reminderSummary == "3 Erinnerungen")

        await viewModel.updateReminderTime(ReminderTime(hour: 12, minute: 30), to: ReminderTime(hour: 16, minute: 0))
        await viewModel.removeReminderTime(ReminderTime(hour: 8, minute: 0))
        #expect(viewModel.reminder.times == [ReminderTime(hour: 16, minute: 0), ReminderTime(hour: 19, minute: 0)])

        // Gespeichert – auch nach einem „Neustart“.
        #expect(store.load().streakReminder.times == viewModel.reminder.times)
        // Heute ab 9 Uhr: 16:00 und 19:00 → je Tag zwei Mitteilungen.
        let last = scheduler.state.withLock { $0.scheduled.last ?? [] }
        #expect(last.prefix(2).map { $0.dateComponents.hour } == [16, 19])

        // Die letzte verbleibende Uhrzeit lässt sich nicht entfernen.
        await viewModel.removeReminderTime(ReminderTime(hour: 16, minute: 0))
        await viewModel.removeReminderTime(ReminderTime(hour: 19, minute: 0))
        #expect(viewModel.reminder.times == [ReminderTime(hour: 19, minute: 0)])
    }

    @Test func reachedGoalSkipsTodaysReminders() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let reached = Locked(false)
        let (viewModel, _, _) = makeNotifications(
            scheduler: scheduler,
            reminder: StreakReminderSettings(isEnabled: true),
            goalReached: { reached.withLock { $0 } }
        )

        await viewModel.reschedule()
        reached.withLock { $0 = true }
        await viewModel.reschedule()

        let plans = scheduler.state.withLock { $0.scheduled }
        #expect(plans.map { $0.first?.dateComponents.day } == [20, 21])
    }

    @Test func freshProgressNamesTheMissingStepsAndIsThrottled() async throws {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let clock = Locked(Fixtures.date(2026, 10, 20, 18, 0))
        let steps = Locked(6_580)
        let (viewModel, _, _) = makeNotifications(
            scheduler: scheduler,
            reminder: StreakReminderSettings(isEnabled: true),
            progress: {
                GoalProgressSnapshot(day: Fixtures.day(2026, 10, 20), steps: steps.withLock { $0 }, goal: 10_000, measuredAt: clock.withLock { $0 })
            },
            now: { clock.withLock { $0 } }
        )

        await viewModel.progressDidChange()
        let first = try #require(scheduler.state.withLock { $0.scheduled.last?.first })
        #expect(first.body == "Dir fehlen noch 3.420 Schritte bis zu deinem Tagesziel.")

        // Wenige Minuten später, neuer Stand: noch nicht neu planen (Drosselung) …
        clock.withLock { $0 = Fixtures.date(2026, 10, 20, 18, 2) }
        steps.withLock { $0 = 9_350 }
        await viewModel.progressDidChange()
        #expect(scheduler.state.withLock { $0.scheduled.count } == 1)
        // … nach fünf Minuten schon – jetzt „fast geschafft“.
        clock.withLock { $0 = Fixtures.date(2026, 10, 20, 18, 6) }
        await viewModel.progressDidChange()
        let updated = try #require(scheduler.state.withLock { $0.scheduled.last?.first })
        #expect(updated.title == "Nur noch 650 Schritte!")
        #expect(updated.body == "Dein Tagesziel ist fast geschafft.")
    }

    @Test func successIsAnnouncedOnceWhenTheGoalIsCrossed() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let steps = Locked(9_800)
        let (viewModel, settings, _) = makeNotifications(
            scheduler: scheduler,
            reminder: StreakReminderSettings(isEnabled: true),
            progress: {
                GoalProgressSnapshot(day: Fixtures.day(2026, 10, 20), steps: steps.withLock { $0 }, goal: 10_000, measuredAt: Fixtures.date(2026, 10, 20, 9))
            }
        )

        await viewModel.progressDidChange()
        steps.withLock { $0 = 10_120 }
        await viewModel.progressDidChange()
        await viewModel.progressDidChange()

        let delivered = scheduler.state.withLock { $0.delivered }
        #expect(delivered.count == 1)
        #expect(delivered.first?.title == "Geschafft!")
        #expect(delivered.first?.body == "Du hast dein Tagesziel erreicht – 10.120 Schritte heute.")
        #expect(settings.goalReachedNotifiedOn == Fixtures.day(2026, 10, 20))
        // Heutige Erinnerungen entfallen, der Plan beginnt morgen.
        #expect(scheduler.state.withLock { $0.scheduled.last?.first?.dateComponents.day } == 21)
    }

    @Test func goalAlreadyReachedAtLaunchIsNotAnnouncedAgain() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let (viewModel, _, _) = makeNotifications(
            scheduler: scheduler,
            reminder: StreakReminderSettings(isEnabled: true),
            progress: {
                GoalProgressSnapshot(day: Fixtures.day(2026, 10, 20), steps: 12_000, goal: 10_000, measuredAt: Fixtures.date(2026, 10, 20, 9))
            }
        )

        await viewModel.progressDidChange()

        #expect(scheduler.state.withLock { $0.delivered }.isEmpty)
    }

    @Test func aNewDayReschedulesTheSamePlan() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let clock = Locked(Fixtures.date(2026, 10, 20, 9))
        let (viewModel, _, _) = makeNotifications(
            scheduler: scheduler,
            reminder: StreakReminderSettings(isEnabled: true),
            now: { clock.withLock { $0 } }
        )

        await viewModel.reschedule()
        clock.withLock { $0 = Fixtures.date(2026, 10, 21, 9) }
        await viewModel.reschedule()

        #expect(scheduler.state.withLock { $0.scheduled }.count == 2)
    }

    @Test func reminderTimeFromThePickerIsStored() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let (viewModel, _, _) = makeNotifications(scheduler: scheduler, reminder: StreakReminderSettings(isEnabled: true))
        let picked = Calendar.current.date(bySettingHour: 20, minute: 15, second: 0, of: Date()) ?? Date()

        await viewModel.setReminderTime(picked)

        #expect(viewModel.reminder.hour == 20)
        #expect(viewModel.reminder.minute == 15)
        let date = viewModel.reminderDate
        #expect(Calendar.current.component(.hour, from: date) == 20)
        #expect(Calendar.current.component(.minute, from: date) == 15)
    }

    // MARK: Chat-Hinweise

    @Test func chatHintsAreDeliveredOnlyWhenEnabledAndAllowed() async {
        let scheduler = NotificationSchedulerStub { $0.authorization = .authorized }
        let (viewModel, _, store) = makeNotifications(scheduler: scheduler)
        let hint = PlannedNotification(identifier: "pace.chat.1", dateComponents: DateComponents(), title: "Mia", body: "Hey")

        #expect(viewModel.chatMessageHints)
        await viewModel.announceIncomingMessage(hint)
        #expect(scheduler.state.withLock { $0.delivered } == [hint])

        await viewModel.setChatMessageHints(false)
        await viewModel.announceIncomingMessage(hint)
        #expect(scheduler.state.withLock { $0.delivered }.count == 1)
        #expect(store.load().chatMessageHints == false)

        // Wieder an, aber Mitteilungen in iOS ausgeschaltet: kein Hinweis, ehrlicher Text.
        scheduler.state.withLock { $0.authorization = .denied }
        await viewModel.setChatMessageHints(true)
        await viewModel.announceIncomingMessage(hint)
        #expect(scheduler.state.withLock { $0.delivered }.count == 1)
        #expect(viewModel.message == NotificationSettingsViewModel.deniedMessage)
        #expect(store.load().chatMessageHints)
    }

    @Test func enablingChatHintsAsksForPermissionOnce() async {
        let scheduler = NotificationSchedulerStub()
        let (viewModel, settings, _) = makeNotifications(scheduler: scheduler)
        settings.chatMessageHints = false

        await viewModel.setChatMessageHints(true)

        #expect(scheduler.state.withLock { $0.requestCount } == 1)
        #expect(viewModel.authorization == .authorized)
        #expect(viewModel.message == nil)
    }

    @Test func withoutSchedulerTheSectionIsUnavailable() async {
        let env = ProfileSettingsEnvironment(withBackend: false)

        await env.viewModel.notifications.setReminderEnabled(true)

        #expect(!env.viewModel.notifications.isAvailable)
        #expect(!env.viewModel.notifications.reminder.isEnabled)
    }
}
