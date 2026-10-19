import Foundation
import Observation
import PaceCore

/// Social-Einstellungen (Einstellungen-Knopf auf der Hauptseite): blockierte Nutzer verwalten, Zugang zu Anfragen und
/// Gruppeneinladungen, Sichtbarkeit in der Suche.
///
/// Die Auffindbarkeit wird nicht hier doppelt gespeichert: Sie gehört zum Profil (`ProfileRepository.updateDiscoverable`)
/// und wird über ``SocialViewModel/openPrivacySettings`` im Profil-Tab geöffnet.
@MainActor
@Observable
public final class SocialSettingsViewModel {
    public enum BlockedState: Equatable {
        case loading
        case loaded([SocialProfile])
        case failed(String)
        /// Ohne Social-Backend bzw. vor der Server-Einrichtung.
        case unavailable(String)
    }

    public private(set) var blocked: BlockedState = .loading

    @ObservationIgnored private let repository: (any SocialRepository)?
    @ObservationIgnored private weak var social: SocialViewModel?

    public init(repository: (any SocialRepository)?, social: SocialViewModel?) {
        self.repository = repository
        self.social = social
        if repository == nil {
            blocked = .unavailable(SocialError.unavailable.message)
        }
    }

    public var incomingRequestCount: Int {
        social?.incomingRequests.count ?? 0
    }

    public var invitationCount: Int {
        social?.invitations.count ?? 0
    }

    /// Ob der Profil-Tab die Privatsphäre-Einstellungen öffnen kann.
    public var canOpenPrivacySettings: Bool {
        social?.openPrivacySettings != nil
    }

    public func openPrivacySettings() {
        social?.openPrivacySettings?()
    }

    public func isBusy(_ profile: SocialProfile) -> Bool {
        social?.busyIDs.contains(profile.publicID) == true
    }

    public func load() async {
        guard let repository else { return }
        if case .failed = blocked {
            blocked = .loading
        }
        do {
            let users = try await repository.blockedUsers()
            blocked = .loaded(users.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })
        } catch is CancellationError {
            return
        } catch let error as SocialError where error == .unavailable {
            blocked = .unavailable(SocialText.featureUnavailable)
        } catch {
            blocked = .failed(SocialText.message(for: error))
        }
    }

    /// Hebt eine Blockierung auf. Freundschaft und Anfragen kommen dadurch nicht zurück.
    @discardableResult
    public func unblock(_ profile: SocialProfile) async -> Bool {
        guard let social else { return false }
        let done = await social.unblock(profile)
        if done, case .loaded(let users) = blocked {
            blocked = .loaded(users.filter { $0.publicID != profile.publicID })
        }
        await load()
        return done
    }
}

/// Vollständiges Freundesranking („Alle ansehen“ bei den Top-Freunden): heute oder diese Woche.
@MainActor
@Observable
public final class FriendsRankingViewModel {
    public enum State: Equatable {
        case loading
        case loaded([LeaderboardEntry])
        case failed(String)
        case unavailable(String)
    }

    public private(set) var period: LeaderboardPeriod = .daily
    public private(set) var state: State = .loading

    @ObservationIgnored private let repository: (any SocialRepository)?
    @ObservationIgnored private weak var social: SocialViewModel?
    /// Nur die Antwort der zuletzt gestellten Anfrage zählt (schneller Wechsel zwischen „Heute“ und „Diese Woche“).
    @ObservationIgnored private var generation = 0

    public init(repository: (any SocialRepository)?, social: SocialViewModel?) {
        self.repository = repository
        self.social = social
        if repository == nil {
            state = .unavailable(SocialError.unavailable.message)
        } else if let ranking = social?.ranking, !ranking.isEmpty {
            // Das heutige Ranking ist schon geladen – sofort anzeigen, dann auffrischen.
            state = .loaded(ranking)
        }
    }

    public var entries: [LeaderboardEntry] {
        if case .loaded(let entries) = state { return entries }
        return []
    }

    /// `true`, sobald es außer dir jemanden im Ranking gibt.
    public var hasFriends: Bool {
        entries.contains { !$0.isCurrentUser } || social?.friends.isEmpty == false
    }

    public func select(_ period: LeaderboardPeriod) async {
        guard period != self.period else { return }
        self.period = period
        state = .loading
        await load()
    }

    public func load() async {
        guard let repository else { return }
        generation += 1
        let current = generation
        let requested = period
        let today = social?.today ?? ActivityCalendar().day(containing: Date())
        if case .failed = state {
            state = .loading
        }
        do {
            let entries = try await repository.friendRanking(period: requested, date: today)
            guard current == generation, requested == period else { return }
            state = .loaded(entries)
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            if let error = error as? SocialError, error == .unavailable {
                state = .unavailable(error.message)
            } else {
                state = .failed(SocialText.message(for: error))
            }
        }
    }
}
