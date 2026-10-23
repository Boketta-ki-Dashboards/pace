import Foundation
import Observation
import PaceCore

/// Profil einer Person – Freund oder nicht – mit den Aktionen, die zur Beziehung passen: Anfrage senden, annehmen,
/// ablehnen oder zurückziehen, Nachricht schreiben (nur Freunde), Profil teilen, Freund entfernen, blockieren, melden.
///
/// Schritte zeigt der Server nur unter Freunden. Jede Aktion läuft über ``SocialViewModel`` (gleiche Hinweise, gleicher
/// Stand auf der Hauptseite) und lädt danach das Profil neu, damit die Beziehung dem Server entspricht.
@MainActor
@Observable
public final class UserProfileViewModel {
    public enum State: Equatable {
        case loading
        case loaded(PublicProfile)
        case failed(String)
        /// Die Person gibt es nicht (mehr) oder sie ist nicht sichtbar.
        case notFound
    }

    /// Bekannte Angaben – damit Kopf und Name sofort erscheinen, bevor das Profil geladen ist.
    public private(set) var profile: SocialProfile
    public private(set) var state: State = .loading

    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private weak var social: SocialViewModel?

    public init(profile: SocialProfile, repository: any SocialRepository, social: SocialViewModel?) {
        self.profile = profile
        self.repository = repository
        self.social = social
    }

    public var loaded: PublicProfile? {
        if case .loaded(let details) = state { return details }
        return nil
    }

    public var relationship: SocialRelationship? {
        loaded?.relationship
    }

    /// Läuft gerade eine Aktion für diese Person?
    public var isBusy: Bool {
        guard let social else { return false }
        return social.busyIDs.contains(profile.publicID) || requestID.map(social.busyIDs.contains) == true
    }

    /// Offene Anfrage zwischen euch – vom Server oder aus den geladenen Anfragen.
    public var requestID: UUID? {
        if let id = loaded?.requestID { return id }
        return social?.requests.first { $0.profile.publicID == profile.publicID }?.id
    }

    /// Nachricht schreiben – nur unter Freunden und ohne Blockierung.
    public var chatTarget: ChatTarget? {
        guard let loaded, loaded.relationship == .friend, !loaded.isBlockedByMe else { return nil }
        return .direct(loaded.profile)
    }

    public var isOwnProfile: Bool {
        relationship == .me
    }

    public func load() async {
        if case .failed = state {
            state = .loading
        }
        let today = social?.today ?? ActivityCalendar().day(containing: Date())
        do {
            let details = try await repository.publicProfile(profile.publicID, date: today)
            profile = details.profile
            state = .loaded(details)
        } catch SocialError.notFound {
            state = .notFound
        } catch is CancellationError {
            return
        } catch {
            state = .failed(SocialText.message(for: error))
        }
    }

    // MARK: Aktionen

    @discardableResult
    public func sendRequest() async -> Bool {
        guard let social else { return false }
        let sent = await social.sendRequest(to: profile) != nil
        await load()
        return sent
    }

    @discardableResult
    public func respond(accept: Bool) async -> Bool {
        guard let social, let requestID else { return false }
        let done = await social.respondToRequest(requestID, from: profile, accept: accept)
        await load()
        return done
    }

    @discardableResult
    public func withdrawRequest() async -> Bool {
        guard let social, let requestID else { return false }
        let done = await social.cancelRequest(requestID, to: profile)
        await load()
        return done
    }

    @discardableResult
    public func removeFriend() async -> Bool {
        guard let social else { return false }
        let done = await social.removeFriend(profile)
        await load()
        return done
    }

    @discardableResult
    public func block() async -> Bool {
        guard let social else { return false }
        let done = await social.block(profile)
        await load()
        return done
    }

    @discardableResult
    public func unblock() async -> Bool {
        guard let social else { return false }
        let done = await social.unblock(profile)
        await load()
        return done
    }

    // MARK: Spitzname

    /// Einen privaten Spitznamen gibt es nur für Freunde; nur du siehst ihn.
    public var canEditNickname: Bool {
        guard let loaded else { return false }
        return loaded.relationship == .friend && !loaded.isBlockedByMe
    }

    public private(set) var isSavingNickname = false
    /// Fehler beim letzten Speichern (z. B. keine Verbindung).
    public private(set) var nicknameError: String?

    /// Prüfung beim Tippen; `nil`, wenn die Eingabe gespeichert werden kann (leer = Spitzname entfernen).
    public func nicknameProblem(for input: String) -> String? {
        NicknameRules.violation(for: input).map(SocialText.nicknameProblem)
    }

    /// Ob die Eingabe etwas ändert und gültig ist.
    public func canSaveNickname(_ input: String) -> Bool {
        canEditNickname && !isSavingNickname && nicknameProblem(for: input) == nil
            && NicknameRules.storedValue(input) != profile.nickname
    }

    /// Speichert den Spitznamen auf dem Server (leere Eingabe entfernt ihn) und übernimmt ihn sofort überall.
    /// - Returns: `true`, wenn gespeichert (oder unverändert).
    @discardableResult
    public func saveNickname(_ input: String) async -> Bool {
        guard canEditNickname, !isSavingNickname else { return false }
        if let problem = nicknameProblem(for: input) {
            nicknameError = problem
            return false
        }
        let value = NicknameRules.storedValue(input)
        guard value != profile.nickname else {
            nicknameError = nil
            return true
        }
        isSavingNickname = true
        defer { isSavingNickname = false }
        do {
            let saved = try await repository.setFriendNickname(publicID: profile.publicID, nickname: value)
            profile = profile.withNickname(saved.nickname)
            if let details = loaded {
                state = .loaded(PublicProfile(
                    profile: profile,
                    relationship: details.relationship,
                    requestID: details.requestID,
                    friendsSince: details.friendsSince,
                    stepsToday: details.stepsToday,
                    stepsWeek: details.stepsWeek,
                    isBlockedByMe: details.isBlockedByMe
                ))
            }
            nicknameError = nil
            social?.nicknameDidChange(profile)
            return true
        } catch is CancellationError {
            return false
        } catch {
            nicknameError = SocialText.actionMessage(for: error)
            return false
        }
    }

    /// Fehlerhinweis zurücksetzen (z. B. beim Schließen der Eingabe).
    public func clearNicknameError() {
        nicknameError = nil
    }

    /// Link und Text zum Teilen außerhalb von Pace.
    public var shareURL: URL {
        PaceLink.profile(username: profile.username).url
    }

    public var shareText: String {
        SocialText.shareProfileText(username: profile.username, isOwn: isOwnProfile)
    }
}

/// Profil eines Freundes: nur Namen und Wettbewerbsschritte (heute, diese Woche).
@MainActor
@Observable
public final class FriendProfileViewModel {
    public enum State: Equatable {
        case loading
        case loaded(FriendProfileDetails)
        case failed(String)
        case removed
    }

    public let profile: SocialProfile
    public private(set) var state: State = .loading
    public private(set) var isRemoving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private weak var social: SocialViewModel?
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        profile: SocialProfile,
        repository: any SocialRepository,
        social: SocialViewModel?,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.profile = profile
        self.repository = repository
        self.social = social
        self.calendar = calendar
        self.now = now
    }

    public func load() async {
        if case .failed = state {
            state = .loading
        }
        do {
            state = .loaded(try await repository.friendProfile(profile.publicID, date: calendar.day(containing: now())))
        } catch SocialError.notFound {
            state = .removed
        } catch is CancellationError {
            return
        } catch {
            state = .failed(SocialText.message(for: error))
        }
    }

    public func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        errorMessage = nil
        defer { isRemoving = false }
        do {
            try await repository.removeFriend(profile.publicID)
            state = .removed
            await social?.load()
        } catch {
            errorMessage = SocialText.actionMessage(for: error)
        }
    }
}
