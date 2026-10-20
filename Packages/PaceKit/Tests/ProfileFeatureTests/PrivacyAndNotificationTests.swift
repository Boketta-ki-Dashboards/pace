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
        now: @escaping @Sendable () -> Date = { Fixtures.date(2026, 10, 20, 9) }
    ) -> (NotificationSettingsViewModel, AppSettings, InMemoryAppPreferencesStore) {
        let store = InMemoryAppPreferencesStore(AppPreferences(language: .fixed(.german), streakReminder: reminder))
        let settings = AppSettings(store: store, preferredLanguages: { [] }, applyLanguage: { _ in })
        let viewModel = NotificationSettingsViewModel(
            settings: settings,
            notifications: scheduler,
            isTodayGoalReached: goalReached,
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
        #expect(scheduled.first?.hour == 19)
        #expect(scheduled.first?.minute == 0)
        #expect(scheduled.first?.skipToday == false)
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
        #expect(scheduled.last?.hour == 7)
        #expect(scheduled.last?.minute == 45)
        #expect(store.load().streakReminder == StreakReminderSettings(isEnabled: true, hour: 7, minute: 45))
        // Deutsch „07:45“ (je nach Plattform-ICU auch „7:45“), Englisch mit AM/PM.
        #expect(viewModel.reminderTimeText.hasSuffix("7:45"))
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(viewModel.reminderTimeText.contains("AM"))
        }
    }

    @Test func reachedGoalSkipsTodaysReminder() async {
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

        #expect(scheduler.state.withLock { $0.scheduled }.map(\.skipToday) == [false, true])
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

    @Test func withoutSchedulerTheSectionIsUnavailable() async {
        let env = ProfileSettingsEnvironment(withBackend: false)

        await env.viewModel.notifications.setReminderEnabled(true)

        #expect(!env.viewModel.notifications.isAvailable)
        #expect(!env.viewModel.notifications.reminder.isEnabled)
    }

    @Test func reminderTextsAreLocalized() {
        #expect(NotificationSettingsViewModel.reminderTitle == "Dein Tagesziel wartet")
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(NotificationSettingsViewModel.reminderTitle == "Your daily goal is waiting")
            #expect(NotificationSettingsViewModel.reminderBody == "Reach your daily goal today to keep your streak going.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(NotificationSettingsViewModel.reminderTitle == "Твоя дневная цель ждёт")
        }
    }
}
