import Foundation
import Observation
import PaceCore

/// Führt durch das Onboarding: Profil anlegen, dann Region wählen.
@MainActor
@Observable
public final class OnboardingViewModel {
    /// Womit das Onboarding beginnt.
    public enum Start: Equatable, Sendable {
        /// Noch kein Profil.
        case profile(UserID)
        /// Profil vorhanden, aber ohne Region.
        case region(UserProfile)
    }

    public enum Step {
        case profile(ProfileSetupViewModel)
        case region(RegionOnboardingViewModel)

        /// 1 für das Profil, 2 für die Region.
        public var number: Int {
            switch self {
            case .profile: 1
            case .region: 2
            }
        }
    }

    public static let stepCount = 2

    public private(set) var step: Step

    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let regions: any RegionRepository
    @ObservationIgnored private let cache: any ProfileCaching
    @ObservationIgnored private let debounce: Debounce
    @ObservationIgnored private let onFinished: @MainActor (UserProfile) -> Void

    /// Wartezeiten beim Tippen. In Tests `.immediate`.
    public struct Debounce: Sendable {
        public let usernameAvailability: Duration
        public let regionSearch: Duration

        public init(usernameAvailability: Duration, regionSearch: Duration) {
            self.usernameAvailability = usernameAvailability
            self.regionSearch = regionSearch
        }

        public static let standard = Debounce(usernameAvailability: .milliseconds(400), regionSearch: .milliseconds(300))
        public static let immediate = Debounce(usernameAvailability: .zero, regionSearch: .zero)
    }

    /// - Parameter onFinished: Erhält das vollständige Profil (mit Region), sobald das Onboarding abgeschlossen ist.
    public init(
        start: Start,
        profiles: any ProfileRepository,
        regions: any RegionRepository,
        cache: any ProfileCaching,
        debounce: Debounce = .standard,
        onFinished: @escaping @MainActor (UserProfile) -> Void
    ) {
        self.profiles = profiles
        self.regions = regions
        self.cache = cache
        self.debounce = debounce
        self.onFinished = onFinished

        // Die Schritt-ViewModels melden sich über `owner` zurück, das erst nach der Initialisierung gesetzt wird.
        let owner = WeakOwner()
        switch start {
        case .profile(let userID):
            step = .profile(ProfileSetupViewModel(
                userID: userID,
                profiles: profiles,
                availabilityDebounce: debounce.usernameAvailability
            ) { profile in
                owner.value?.profileCreated(profile)
            })
        case .region(let profile):
            step = .region(Self.makeRegionStep(
                profile: profile,
                profiles: profiles,
                regions: regions,
                debounce: debounce,
                owner: owner
            ))
        }
        owner.value = self
    }

    private func profileCreated(_ profile: UserProfile) {
        cache.save(profile)
        if profile.isComplete {
            onFinished(profile)
            return
        }
        let owner = WeakOwner()
        owner.value = self
        step = .region(Self.makeRegionStep(
            profile: profile,
            profiles: profiles,
            regions: regions,
            debounce: debounce,
            owner: owner
        ))
    }

    private func regionChosen(_ profile: UserProfile) {
        cache.save(profile)
        onFinished(profile)
    }

    private static func makeRegionStep(
        profile: UserProfile,
        profiles: any ProfileRepository,
        regions: any RegionRepository,
        debounce: Debounce,
        owner: WeakOwner
    ) -> RegionOnboardingViewModel {
        RegionOnboardingViewModel(
            profile: profile,
            profiles: profiles,
            regions: regions,
            searchDebounce: debounce.regionSearch
        ) { profile in
            owner.value?.regionChosen(profile)
        }
    }

    @MainActor
    private final class WeakOwner {
        weak var value: OnboardingViewModel?
    }
}
