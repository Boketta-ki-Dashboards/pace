import ActivityFeature
import Foundation
import Observation
import PaceCore
import RegionFeature

/// Dienste für die Einstellungen im Profil-Tab. Alles ist optional: Ohne Server-Anbindung (Tests, Vorschauen) zeigen
/// die Seiten einen ehrlichen „nicht verfügbar“-Zustand.
@MainActor
public struct ProfileSettingsServices {
    /// Darstellung, Sprache, Erinnerung. Ohne Angabe nur im Speicher (Tests, Vorschauen), ohne die App-Sprache zu ändern.
    public var settings: AppSettings?
    /// Für die Verfügbarkeitsprüfung beim Ändern des Benutzernamens.
    public var profiles: (any ProfileRepository)?
    public var notifications: (any LocalNotificationScheduling)?
    /// Zuletzt bekannter Stand von heute aus Apple Health (für Erinnerungstexte und „Geschafft!“).
    public var todayProgress: (@MainActor () -> GoalProgressSnapshot?)?
    public var account: (any AccountRepository)?
    public var media: (any MediaRepository)?
    /// Blockierte Personen.
    public var social: (any SocialRepository)?
    /// Abmelden nach dem Löschen des Kontos; Konto-Art.
    public var auth: (any AuthProviding)?
    /// Nur auf dem Gerät gespeicherte Daten (Export, Löschen). Standard: nur im Speicher.
    public var localData: any LocalAccountDataStoring
    /// z. B. `0.1.0 (1)`.
    public var appVersion: String
    /// Nach dem vollständigen Löschen des Kontos (App-Rahmen: zurück zum Start).
    public var onAccountDeleted: (@MainActor () -> Void)?
    public var availabilityDebounce: Duration
    public var exportDirectory: URL
    public var now: @Sendable () -> Date

    public init(
        settings: AppSettings? = nil,
        profiles: (any ProfileRepository)? = nil,
        notifications: (any LocalNotificationScheduling)? = nil,
        todayProgress: (@MainActor () -> GoalProgressSnapshot?)? = nil,
        account: (any AccountRepository)? = nil,
        media: (any MediaRepository)? = nil,
        social: (any SocialRepository)? = nil,
        auth: (any AuthProviding)? = nil,
        localData: any LocalAccountDataStoring = InMemoryLocalAccountData(),
        appVersion: String = "",
        onAccountDeleted: (@MainActor () -> Void)? = nil,
        availabilityDebounce: Duration = .milliseconds(400),
        exportDirectory: URL = FileManager.default.temporaryDirectory,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settings = settings
        self.profiles = profiles
        self.notifications = notifications
        self.todayProgress = todayProgress
        self.account = account
        self.media = media
        self.social = social
        self.auth = auth
        self.localData = localData
        self.appVersion = appVersion
        self.onAccountDeleted = onAccountDeleted
        self.availabilityDebounce = availabilityDebounce
        self.exportDirectory = exportDirectory
        self.now = now
    }
}

/// Eine Sprache zur Auswahl („Wie iPhone“ oder eine der drei Sprachen).
public struct LanguageChoice: Identifiable, Hashable, Sendable {
    public let preference: LanguagePreference
    /// Name in der eigenen Sprache („English“) bzw. „Wie iPhone“.
    public let title: String
    /// Zusatz, z. B. „Englisch“ (in der aktuellen Sprache) oder die Sprache des iPhones.
    public let subtitle: String?

    public var id: String {
        switch preference {
        case .system: "system"
        case .fixed(let language): language.rawValue
        }
    }
}

/// Profil und Einstellungen: Namen, Aktivität (Tagesziel, Serie, Statistik), Region, Zustimmung zu regionalen
/// Rankings, Darstellung und die Unterseiten der Einstellungen.
@MainActor
@Observable
public final class ProfileViewModel {
    /// Geöffnete Unterseiten (Navigation des Profil-Tabs).
    public var path: [ProfileRoute] = []

    public private(set) var isUpdatingParticipation = false
    /// Gewünschter Wert, solange die Anfrage läuft – der Schalter springt so nicht zurück.
    public private(set) var pendingParticipation: Bool?
    /// Wert der zuletzt fehlgeschlagenen Änderung.
    private var failedParticipation: Bool?
    public private(set) var regionLoadFailed = false

    /// Suche für „Region ändern“; `nil`, solange der Dialog geschlossen ist.
    public private(set) var regionSearch: RegionSearchViewModel?
    public private(set) var isSavingRegion = false
    public private(set) var regionChangeError: String?

    /// Das aktuell gesetzte App-Icon.
    public private(set) var appIcon: AppIconChoice
    public private(set) var isChangingAppIcon = false
    public private(set) var appIconError: String?

    /// Offenes Sheet für das Tagesziel.
    public var isEditingGoal = false

    /// Serie, Rekord und Tagesziel; `nil`, wenn keine Bewegungsdaten angebunden sind (z. B. in Tests).
    public let streak: StepStreakTracker?

    /// Darstellung, Sprache und Erinnerung.
    public let settings: AppSettings
    /// Konto & Profil.
    public let account: AccountSettingsViewModel
    /// Privatsphäre (Auffindbarkeit, blockierte Personen) – auch für die Social-Einstellungen.
    public let privacy: PrivacySettingsViewModel
    public let notifications: NotificationSettingsViewModel
    /// Datenschutz & Daten: Export und Konto löschen.
    public let dataPrivacy: DataPrivacyViewModel
    /// z. B. `0.1.0 (1)`; leer, wenn unbekannt.
    public let appVersion: String
    /// Wechselt in den Social-Tab (Anfragen, Einladungen); vom App-Rahmen gesetzt.
    @ObservationIgnored public var openSocial: (@MainActor () -> Void)?
    /// Öffnet „Meine Gruppen“ im Social-Tab (Gruppeneinstellungen liegen in der jeweiligen Gruppe).
    @ObservationIgnored public var openSocialGroups: (@MainActor () -> Void)?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let regions: any RegionRepository
    @ObservationIgnored private let appIcons: any AppIconSetting
    @ObservationIgnored private let makeStatistics: (@MainActor (StatisticsRoute) -> StatisticsViewModel)?
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let searchDebounce: Duration
    @ObservationIgnored private let accountRepository: (any AccountRepository)?

    public init(
        store: ProfileStore,
        regions: any RegionRepository,
        appIcons: any AppIconSetting = UnsupportedAppIconSetting(),
        streak: StepStreakTracker? = nil,
        statistics: (@MainActor (StatisticsRoute) -> StatisticsViewModel)? = nil,
        formatter: ActivityFormatter = ActivityFormatter(),
        searchDebounce: Duration = .milliseconds(300),
        services: ProfileSettingsServices = ProfileSettingsServices()
    ) {
        self.store = store
        self.regions = regions
        self.appIcons = appIcons
        self.streak = streak
        makeStatistics = statistics
        self.formatter = formatter
        self.searchDebounce = searchDebounce
        appIcon = AppIconChoice(alternateIconName: appIcons.currentAlternateIconName)

        let settings = services.settings ?? AppSettings(
            store: InMemoryAppPreferencesStore(),
            preferredLanguages: { [] },
            applyLanguage: { _ in }
        )
        self.settings = settings
        appVersion = services.appVersion
        accountRepository = services.account
        account = AccountSettingsViewModel(
            store: store,
            profiles: services.profiles,
            media: services.media,
            auth: services.auth,
            availabilityDebounce: services.availabilityDebounce
        )
        privacy = PrivacySettingsViewModel(store: store, blockedUsers: BlockedUsersViewModel(repository: services.social))
        let notifications = NotificationSettingsViewModel(
            settings: settings,
            notifications: services.notifications,
            isTodayGoalReached: { [weak streak] in streak?.streak?.isTodayReached ?? false },
            todayProgress: services.todayProgress ?? { nil },
            currentGoal: { [weak streak] in streak?.goals.currentGoal ?? StepGoalRules.defaultGoal },
            now: services.now
        )
        self.notifications = notifications
        dataPrivacy = DataPrivacyViewModel(
            store: store,
            account: services.account,
            media: services.media,
            auth: services.auth,
            localData: services.localData,
            settings: settings,
            notifications: notifications,
            appVersion: services.appVersion,
            exportDirectory: services.exportDirectory,
            now: services.now,
            onAccountDeleted: services.onAccountDeleted
        )
    }

    /// Körperdaten und Kalorienschätzung (dieselbe Quelle wie Home, Statistik und Kalender).
    public var bodyMetrics: BodyMetricsSettings? { streak?.history.bodyMetrics }

    // MARK: Navigation

    /// Öffnet eine Unterseite direkt (von außen, z. B. aus den Social-Einstellungen).
    public func show(_ route: ProfileRoute) {
        path = [route]
    }

    /// Öffnet eine weitere Unterseite über der aktuellen – oder geht zu ihr zurück, wenn sie schon offen ist (keine
    /// Einstellungs-Schleifen, kein doppeltes Auflegen durch zweimaliges Tippen).
    public func open(_ route: ProfileRoute) {
        let opened = PaceNavigationRules.opening(route, in: path)
        if opened != path { path = opened }
    }

    /// Neues Formular für „Problem melden“ bzw. „Feedback senden“.
    public func makeFeedback(_ kind: FeedbackKind) -> FeedbackViewModel {
        FeedbackViewModel(kind: kind, account: accountRepository, appVersion: appVersion)
    }

    /// Profilbild für den Kopf.
    public var avatar: MediaReference? { store.profile.avatar }
    /// Stabiler Wert für die Farbe der Initialen.
    public var avatarSeed: String { store.profile.publicID.uuidString }
    public var share: ProfileShare { ProfileShare(username: store.profile.username) }

    // MARK: Darstellung und Sprache

    public var appearance: AppearancePreference { settings.appearance }

    /// Wirkt sofort (RootView) und bleibt gespeichert.
    public func setAppearance(_ appearance: AppearancePreference) {
        settings.appearance = appearance
    }

    public var language: LanguagePreference { settings.language }

    public var languageChoices: [LanguageChoice] {
        let system = LanguageChoice(
            preference: .system,
            title: PaceLocalization.text(de: "Wie iPhone", en: "Same as iPhone", ru: "Как на iPhone"),
            subtitle: settings.systemLanguage.nativeName
        )
        return [system] + AppLanguage.allCases.map { language in
            let localizedName = Self.localizedName(of: language)
            return LanguageChoice(
                preference: .fixed(language),
                title: language.nativeName,
                subtitle: localizedName == language.nativeName ? nil : localizedName
            )
        }
    }

    /// Wechselt die Sprache sofort und plant die Erinnerung in der neuen Sprache neu.
    public func setLanguage(_ preference: LanguagePreference) async {
        guard preference != settings.language else { return }
        settings.language = preference
        await notifications.reschedule()
    }

    /// Kurzer Wert für die Zeile „Sprache“, z. B. „Wie iPhone (Deutsch)“ oder „English“.
    public var languageSummary: String {
        switch settings.language {
        case .system:
            PaceLocalization.text(de: "Wie iPhone", en: "Same as iPhone", ru: "Как на iPhone")
                + " (\(settings.resolvedLanguage.nativeName))"
        case .fixed(let language):
            language.nativeName
        }
    }

    /// Name einer Sprache in der aktuellen Sprache, z. B. „Englisch“.
    static func localizedName(of language: AppLanguage) -> String {
        switch language {
        case .german: PaceLocalization.text(de: "Deutsch", en: "German", ru: "Немецкий")
        case .english: PaceLocalization.text(de: "Englisch", en: "English", ru: "Английский")
        case .russian: PaceLocalization.text(de: "Russisch", en: "Russian", ru: "Русский")
        }
    }

    public var displayName: String { store.profile.displayName }
    public var username: String { "@\(store.profile.username)" }

    /// Bis zu zwei Initialen für den Avatar, z. B. `NK` für „Niklas K.“.
    public var initials: String {
        let letters = DisplayNameRules.normalized(store.profile.displayName)
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var municipalityName: String? {
        store.hierarchy?.municipality.name
    }

    /// Kreis bzw. „kreisfreie Stadt“, wenn Gemeinde und Kreis zusammenfallen.
    public var districtName: String? {
        guard let hierarchy = store.hierarchy else { return nil }
        return hierarchy.district.municipalityCount <= 1
            ? PaceLocalization.text(de: "kreisfreie Stadt", en: "independent city", ru: "внерайонный город")
            : hierarchy.district.displayName
    }

    public var stateName: String? {
        store.hierarchy?.state.name
    }

    public var regionalLeaderboardEnabled: Bool {
        store.profile.regionalLeaderboardEnabled
    }

    public var isChangingRegion: Bool {
        regionSearch != nil
    }

    /// Ob die gewählte Gemeinde gespeichert werden kann (gewählt und anders als die aktuelle).
    public var canSaveRegion: Bool {
        guard !isSavingRegion, let selection = regionSearch?.selection else { return false }
        return selection.municipality.id != store.profile.municipalityID
    }

    /// Lädt die Hierarchie der Gemeinde für die Anzeige.
    public func load() async {
        do {
            try await store.loadHierarchyIfNeeded()
            regionLoadFailed = false
        } catch {
            regionLoadFailed = true
        }
    }

    public func setRegionalLeaderboardEnabled(_ enabled: Bool) async {
        guard enabled != regionalLeaderboardEnabled, !isUpdatingParticipation else { return }
        isUpdatingParticipation = true
        pendingParticipation = enabled
        failedParticipation = nil
        defer {
            isUpdatingParticipation = false
            pendingParticipation = nil
        }

        do {
            try await store.setRegionalLeaderboardEnabled(enabled)
        } catch {
            failedParticipation = enabled
        }
    }

    /// Wert des Schalters: während der Anfrage bereits der gewünschte.
    public var participationToggleValue: Bool {
        pendingParticipation ?? regionalLeaderboardEnabled
    }

    /// Fehler der letzten Änderung – verschwindet, sobald die Teilnahme (auch anderswo, z. B. im Rankings-Tab)
    /// dem gewünschten Wert entspricht.
    public var errorMessage: String? {
        guard let failedParticipation, failedParticipation != regionalLeaderboardEnabled else { return nil }
        return failedParticipation
            ? PaceLocalization.text(
                de: "Du konntest nicht zu den Rankings hinzugefügt werden. Bitte versuche es erneut.",
                en: "You couldn't be added to the rankings. Please try again.",
                ru: "Не удалось добавить тебя в рейтинги. Попробуй снова."
            )
            : PaceLocalization.text(
                de: "Du konntest nicht aus den Rankings entfernt werden. Bitte versuche es erneut.",
                en: "You couldn't be removed from the rankings. Please try again.",
                ru: "Не удалось убрать тебя из рейтингов. Попробуй снова."
            )
    }

    /// z. B. `10.000 Schritte`; `nil` ohne angebundene Bewegungsdaten.
    public var goalText: String? {
        streak.map { tracker in
            let goal = tracker.goals.currentGoal
            return "\(formatter.steps(goal)) " + PaceLocalization.plural(
                goal,
                de: ("Schritt", "Schritte"),
                en: ("step", "steps"),
                ru: ("шаг", "шага", "шагов")
            )
        }
    }

    /// z. B. `Rekord: 33 Tage`. Ein gespeicherter Rekord erscheint auch, solange der Verlauf lädt oder nicht lesbar
    /// ist; „Noch kein Rekord“ nur, wenn der Verlauf wirklich keinen ergibt.
    public var recordText: String {
        if let record = streak?.record, record.days > 0 {
            return PaceLocalization.text(de: "Rekord", en: "Record", ru: "Рекорд") + ": " + PaceLocalization.days(record.days)
        }
        let noRecord = PaceLocalization.text(de: "Noch kein Rekord", en: "No record yet", ru: "Рекорда пока нет")
        guard let streak else { return noRecord }
        switch streak.history.state {
        case .idle, .loading:
            return PaceLocalization.text(de: "Rekord wird berechnet …", en: "Calculating record …", ru: "Считаем рекорд …")
        case .noReadAccess, .failed:
            return PaceLocalization.text(de: "Rekord nicht verfügbar", en: "Record not available", ru: "Рекорд недоступен")
        case .loaded:
            return noRecord
        }
    }

    /// Serie und Rekord; `nil`, solange der Verlauf nicht geladen ist.
    public var streakSummary: StreakSummary? {
        guard let streak, let current = streak.streak else { return nil }
        return StreakSummary(streak: current, record: streak.record, recentDays: streak.recentDays(7), formatter: formatter)
    }

    public var showsStatistics: Bool {
        makeStatistics != nil
    }

    public func statistics(for route: StatisticsRoute) -> StatisticsViewModel? {
        makeStatistics?(route)
    }

    /// Lädt den Verlauf für Serie und Rekord (selten, siehe `ActivityHistoryStore`).
    public func loadActivity() async {
        await streak?.loadIfNeeded()
    }

    /// Ob iOS alternative App-Icons erlaubt.
    public var supportsAppIconChange: Bool {
        appIcons.supportsAlternateIcons
    }

    /// Setzt das App-Icon. iOS bestätigt den Wechsel selbst; bei Erfolg zeigt die App keine weitere Meldung.
    public func selectAppIcon(_ choice: AppIconChoice) async {
        guard choice != appIcon, !isChangingAppIcon, supportsAppIconChange else { return }
        isChangingAppIcon = true
        appIconError = nil
        defer { isChangingAppIcon = false }

        do {
            try await appIcons.setAlternateIconName(choice.alternateIconName)
            appIcon = choice
        } catch {
            // Tatsächlichen Stand anzeigen, nicht die gewünschte Auswahl.
            appIcon = AppIconChoice(alternateIconName: appIcons.currentAlternateIconName)
            appIconError = PaceLocalization.text(
                de: "Das App-Icon konnte nicht geändert werden. Bitte versuche es erneut.",
                en: "The app icon couldn't be changed. Please try again.",
                ru: "Не удалось сменить значок приложения. Попробуй снова."
            )
        }
    }

    public func beginRegionChange() {
        regionChangeError = nil
        regionSearch = RegionSearchViewModel(regions: regions, debounce: searchDebounce)
    }

    public func cancelRegionChange() {
        guard !isSavingRegion else { return }
        regionSearch = nil
        regionChangeError = nil
    }

    /// Speichert die gewählte Gemeinde (nur ihre ID) und schließt den Dialog. Die Zustimmung zu Rankings bleibt.
    public func saveRegionChange() async {
        guard canSaveRegion, let selection = regionSearch?.selection else { return }
        isSavingRegion = true
        regionChangeError = nil
        defer { isSavingRegion = false }

        do {
            try await store.changeRegion(to: selection)
            regionSearch = nil
            regionLoadFailed = false
        } catch {
            regionChangeError = Self.regionChangeMessage(for: error)
        }
    }

    static func regionChangeMessage(for error: Error) -> String {
        switch error as? ProfileError {
        case .some(.invalidRegion):
            ProfileError.invalidRegion.message
        case .some(.network):
            ProfileError.network.message
        default:
            PaceLocalization.text(
                de: "Deine Region konnte nicht geändert werden. Bitte versuche es erneut.",
                en: "Your region couldn't be changed. Please try again.",
                ru: "Не удалось изменить регион. Попробуй снова."
            )
        }
    }
}
