import Foundation
import Observation
import PaceCore
import RegionFeature

/// Zweiter Onboarding-Schritt: Gemeinde wählen und entscheiden, ob man in regionalen Rankings erscheint.
///
/// Gespeichert wird nur die ID der Gemeinde, kein Standort.
@MainActor
@Observable
public final class RegionOnboardingViewModel {
    public let search: RegionSearchViewModel
    public let profile: UserProfile

    /// Die Entscheidung, die gerade gespeichert wird (`true` = regional antreten); `nil`, wenn nichts gespeichert wird.
    public private(set) var savingChoice: Bool?
    public private(set) var errorMessage: String?

    public var isSaving: Bool {
        savingChoice != nil
    }

    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let onFinished: @MainActor (UserProfile) -> Void

    public init(
        profile: UserProfile,
        profiles: any ProfileRepository,
        regions: any RegionRepository,
        searchDebounce: Duration = .milliseconds(300),
        onFinished: @escaping @MainActor (UserProfile) -> Void
    ) {
        self.profile = profile
        self.profiles = profiles
        self.onFinished = onFinished
        search = RegionSearchViewModel(regions: regions, debounce: searchDebounce)
    }

    public var canConfirm: Bool {
        search.selection != nil && !isSaving
    }

    /// Speichert die gewählte Gemeinde.
    /// - Parameter regionalLeaderboardEnabled: Ausdrückliche Zustimmung, in regionalen Rankings zu erscheinen.
    public func confirm(regionalLeaderboardEnabled: Bool) async {
        guard canConfirm, let selection = search.selection else { return }
        savingChoice = regionalLeaderboardEnabled
        errorMessage = nil
        defer { savingChoice = nil }

        do {
            let updated = try await profiles.updateRegion(
                municipalityID: selection.municipality.id,
                regionalLeaderboardEnabled: regionalLeaderboardEnabled,
                for: profile.id
            )
            onFinished(updated)
        } catch {
            if error as? ProfileError == .invalidRegion {
                search.clearSelection()
            }
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        switch error as? ProfileError {
        case .invalidRegion:
            PaceLocalization.text(
                de: "Diese Gemeinde kann nicht gewählt werden. Bitte suche sie erneut.",
                en: "This municipality can't be selected. Please search for it again.",
                ru: "Этот населённый пункт нельзя выбрать. Найди его ещё раз."
            )
        case .network:
            OnboardingTexts.noConnection
        default:
            PaceLocalization.text(
                de: "Deine Region konnte nicht gespeichert werden. Bitte versuche es erneut.",
                en: "Your region couldn't be saved. Please try again.",
                ru: "Не удалось сохранить регион. Попробуй ещё раз."
            )
        }
    }
}
