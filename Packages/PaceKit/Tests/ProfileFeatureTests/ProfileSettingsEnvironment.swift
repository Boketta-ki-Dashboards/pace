import Foundation
import PaceCore
import PaceTestSupport
import ProfileFeature

/// Gemeinsamer Aufbau für die Einstellungs-Tests: Profil mit allen Diensten als Test-Doubles und ein Protokoll der
/// Aufrufe, um Reihenfolgen zu prüfen.
@MainActor
final class ProfileSettingsEnvironment {
    let store: ProfileStore
    let profiles: ProfileRepositoryStub
    let cache: InMemoryProfileCache
    let preferences: InMemoryAppPreferencesStore
    let settings: AppSettings
    let appliedLanguages: Locked<[AppLanguage]>
    let notifications: NotificationSchedulerStub
    let account: AccountRepositoryStub
    let media: MediaRepositoryStub
    let social: SocialRepositoryStub
    let auth: AuthStub
    let localData: InMemoryLocalAccountData
    let log = CallLog()
    let exportDirectory: URL
    var deletedCallbacks = 0
    let viewModel: ProfileViewModel

    init(
        profile: UserProfile = Fixtures.profile(),
        preferences: AppPreferences = AppPreferences(language: .fixed(.german)),
        preferredLanguages: [String] = ["de-DE"],
        notifications: NotificationSchedulerStub = NotificationSchedulerStub(),
        account: AccountRepositoryStub = AccountRepositoryStub(),
        media: MediaRepositoryStub = MediaRepositoryStub(),
        social: SocialRepositoryStub = SocialRepositoryStub(),
        localData: InMemoryLocalAccountData = InMemoryLocalAccountData([
            LocalDataSection(name: "settings", json: Data(#"{"appearance":"dark"}"#.utf8)),
            LocalDataSection(name: "streakRecord", json: Data(#"{"days":12}"#.utf8)),
        ]),
        withBackend: Bool = true
    ) {
        let profiles = ProfileRepositoryStub { $0.profiles[profile.id] = profile }
        let cache = InMemoryProfileCache()
        let regions = RegionRepositoryStub()
        store = ProfileStore(profile: profile, profiles: profiles, regions: regions, cache: cache)
        self.profiles = profiles
        self.cache = cache
        let preferenceStore = InMemoryAppPreferencesStore(preferences)
        self.preferences = preferenceStore
        let applied = Locked<[AppLanguage]>([])
        appliedLanguages = applied
        settings = AppSettings(
            store: preferenceStore,
            preferredLanguages: { preferredLanguages },
            applyLanguage: { language in applied.withLock { $0.append(language) } }
        )
        self.notifications = notifications
        self.account = account
        self.media = media
        self.social = social
        auth = AuthStub(storedSession: AuthSession(userID: profile.id, isAnonymous: true))
        self.localData = localData
        exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pace-tests-\(UUID().uuidString)", isDirectory: true)

        let log = log
        let services = ProfileSettingsServices(
            settings: settings,
            profiles: profiles,
            notifications: withBackend ? LoggingNotifications(notifications, log: log) : nil,
            account: withBackend ? LoggingAccount(account, log: log) : nil,
            media: withBackend ? LoggingMedia(media, log: log) : nil,
            social: withBackend ? social : nil,
            auth: LoggingAuth(auth, log: log),
            localData: LoggingLocalData(localData, log: log),
            appVersion: "0.1.0 (1)",
            availabilityDebounce: .zero,
            exportDirectory: exportDirectory,
            now: { Fixtures.date(2026, 10, 20, 9, 30) }
        )
        viewModel = ProfileViewModel(store: store, regions: regions, searchDebounce: .zero, services: services)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: exportDirectory)
    }
}

/// Reihenfolge von Aufrufen über mehrere Test-Doubles hinweg.
final class CallLog: Sendable {
    private let entries = Locked<[String]>([])

    func record(_ entry: String) {
        entries.withLock { $0.append(entry) }
    }

    var calls: [String] {
        entries.withLock { $0 }
    }
}

struct LoggingAccount: AccountRepository {
    let base: AccountRepositoryStub
    let log: CallLog

    init(_ base: AccountRepositoryStub, log: CallLog) {
        self.base = base
        self.log = log
    }

    func exportData() async throws -> Data {
        log.record("account.export")
        return try await base.exportData()
    }

    func ownMedia() async throws -> [MediaReference] {
        log.record("account.ownMedia")
        return try await base.ownMedia()
    }

    func deleteAccount() async throws {
        log.record("account.delete")
        try await base.deleteAccount()
    }

    func submitFeedback(kind: FeedbackKind, message: String, appVersion: String) async throws {
        log.record("account.feedback")
        try await base.submitFeedback(kind: kind, message: message, appVersion: appVersion)
    }
}

struct LoggingMedia: MediaRepository {
    let base: MediaRepositoryStub
    let log: CallLog

    init(_ base: MediaRepositoryStub, log: CallLog) {
        self.base = base
        self.log = log
    }

    func upload(_ data: Data, contentType: String, to target: MediaUploadTarget) async throws -> MediaReference {
        log.record("media.upload")
        return try await base.upload(data, contentType: contentType, to: target)
    }

    func data(for reference: MediaReference) async throws -> Data {
        try await base.data(for: reference)
    }

    func delete(_ reference: MediaReference) async throws {
        log.record("media.delete:\(reference.path)")
        try await base.delete(reference)
    }
}

struct LoggingAuth: AuthProviding {
    let base: AuthStub
    let log: CallLog

    init(_ base: AuthStub, log: CallLog) {
        self.base = base
        self.log = log
    }

    func restoreSession() async -> AuthSession? {
        await base.restoreSession()
    }

    func signInAnonymously() async throws -> AuthSession {
        try await base.signInAnonymously()
    }

    func signOut() async {
        log.record("auth.signOut")
        await base.signOut()
    }
}

struct LoggingLocalData: LocalAccountDataStoring {
    let base: InMemoryLocalAccountData
    let log: CallLog

    init(_ base: InMemoryLocalAccountData, log: CallLog) {
        self.base = base
        self.log = log
    }

    func exportSections() -> [LocalDataSection] {
        base.exportSections()
    }

    func eraseAll() {
        log.record("local.erase")
        base.eraseAll()
    }
}

struct LoggingNotifications: LocalNotificationScheduling {
    let base: NotificationSchedulerStub
    let log: CallLog

    init(_ base: NotificationSchedulerStub, log: CallLog) {
        self.base = base
        self.log = log
    }

    func authorization() async -> NotificationAuthorization {
        await base.authorization()
    }

    func requestAuthorization() async -> Bool {
        log.record("notifications.request")
        return await base.requestAuthorization()
    }

    func scheduleGoalReminders(_ notifications: [PlannedNotification]) async {
        log.record("notifications.schedule")
        await base.scheduleGoalReminders(notifications)
    }

    func cancelGoalReminders() async {
        log.record("notifications.cancel")
        await base.cancelGoalReminders()
    }

    func deliver(_ notification: PlannedNotification) async {
        log.record("notifications.deliver")
        await base.deliver(notification)
    }
}
