import Foundation
import Observation
import PaceCore
import RegionFeature

/// Profil und Einstellungen: Namen, Region, Zustimmung zu regionalen Rankings, App-Icon.
@MainActor
@Observable
public final class ProfileViewModel {
    public private(set) var isUpdatingParticipation = false
    public private(set) var errorMessage: String?
    public private(set) var regionLoadFailed = false

    /// Suche für „Region ändern“; `nil`, solange der Dialog geschlossen ist.
    public private(set) var regionSearch: RegionSearchViewModel?
    public private(set) var isSavingRegion = false
    public private(set) var regionChangeError: String?

    /// Das aktuell gesetzte App-Icon.
    public private(set) var appIcon: AppIconChoice
    public private(set) var isChangingAppIcon = false
    public private(set) var appIconError: String?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let regions: any RegionRepository
    @ObservationIgnored private let appIcons: any AppIconSetting
    @ObservationIgnored private let searchDebounce: Duration

    public init(
        store: ProfileStore,
        regions: any RegionRepository,
        appIcons: any AppIconSetting = UnsupportedAppIconSetting(),
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.store = store
        self.regions = regions
        self.appIcons = appIcons
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
        errorMessage = nil
        defer { isUpdatingParticipation = false }

        do {
            try await store.setRegionalLeaderboardEnabled(enabled)
        } catch {
            errorMessage = enabled
                ? "Du konntest nicht zu den Rankings hinzugefügt werden. Bitte versuche es erneut."
                : "Du konntest nicht aus den Rankings entfernt werden. Bitte versuche es erneut."
        }
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
