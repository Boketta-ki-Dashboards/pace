import ActivityFeature
import Foundation
import Observation
import PaceCore
import RegionFeature

/// Profil und Einstellungen: Namen, Aktivität (Tagesziel, Serie, Statistik), Region, Zustimmung zu regionalen
/// Rankings, App-Icon.
@MainActor
@Observable
public final class ProfileViewModel {
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

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let regions: any RegionRepository
    @ObservationIgnored private let appIcons: any AppIconSetting
    @ObservationIgnored private let makeStatistics: (@MainActor (StatisticsRoute) -> StatisticsViewModel)?
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let searchDebounce: Duration

    public init(
        store: ProfileStore,
        regions: any RegionRepository,
        appIcons: any AppIconSetting = UnsupportedAppIconSetting(),
        streak: StepStreakTracker? = nil,
        statistics: (@MainActor (StatisticsRoute) -> StatisticsViewModel)? = nil,
        formatter: ActivityFormatter = ActivityFormatter(),
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.store = store
        self.regions = regions
        self.appIcons = appIcons
        self.streak = streak
        makeStatistics = statistics
        self.formatter = formatter
        self.searchDebounce = searchDebounce
        appIcon = AppIconChoice(alternateIconName: appIcons.currentAlternateIconName)
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
        return hierarchy.district.municipalityCount <= 1 ? "kreisfreie Stadt" : hierarchy.district.displayName
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
            ? "Du konntest nicht zu den Rankings hinzugefügt werden. Bitte versuche es erneut."
            : "Du konntest nicht aus den Rankings entfernt werden. Bitte versuche es erneut."
    }

    /// z. B. `10.000 Schritte`; `nil` ohne angebundene Bewegungsdaten.
    public var goalText: String? {
        streak.map { "\(formatter.steps($0.goals.currentGoal)) Schritte" }
    }

    /// z. B. `Rekord: 33 Tage`. Ein gespeicherter Rekord erscheint auch, solange der Verlauf lädt oder nicht lesbar
    /// ist; „Noch kein Rekord“ nur, wenn der Verlauf wirklich keinen ergibt.
    public var recordText: String {
        if let record = streak?.record, record.days > 0 {
            return "Rekord: \(record.days == 1 ? "1 Tag" : "\(record.days) Tage")"
        }
        guard let streak else { return "Noch kein Rekord" }
        switch streak.history.state {
        case .idle, .loading: return "Rekord wird berechnet …"
        case .noReadAccess, .failed: return "Rekord nicht verfügbar"
        case .loaded: return "Noch kein Rekord"
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
            appIconError = "Das App-Icon konnte nicht geändert werden. Bitte versuche es erneut."
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
        case .invalidRegion:
            "Diese Gemeinde kann nicht gewählt werden. Bitte suche erneut."
        case .network:
            "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."
        default:
            "Deine Region konnte nicht geändert werden. Bitte versuche es erneut."
        }
    }
}
