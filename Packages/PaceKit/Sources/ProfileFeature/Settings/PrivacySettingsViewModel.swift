import Foundation
import Observation
import PaceCore

/// Blockierte Personen verwalten – gemeinsam für „Privatsphäre“ und „Social-Einstellungen“.
///
/// Eine Blockierung beendet Freundschaft, Anfragen und Einladungen zwischen euch; ihr findet euch nicht mehr und
/// könnt euch nicht mehr schreiben. Durchgesetzt wird das auf dem Server.
@MainActor
@Observable
public final class BlockedUsersViewModel {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
        /// Kein Social-Backend angebunden.
        case unavailable
    }

    public private(set) var state: State
    public private(set) var users: [SocialProfile] = []
    /// Personen, deren Blockierung gerade aufgehoben wird.
    public private(set) var busyIDs: Set<UUID> = []
    /// Fehler der letzten Aktion (z. B. Aufheben fehlgeschlagen).
    public private(set) var actionError: String?

    @ObservationIgnored private let repository: (any SocialRepository)?

    public init(repository: (any SocialRepository)?) {
        self.repository = repository
        state = repository == nil ? .unavailable : .idle
    }

    public var isAvailable: Bool { repository != nil }

    public func load() async {
        guard let repository else { return }
        if users.isEmpty { state = .loading }
        do {
            let loaded = try await repository.blockedUsers()
            users = loaded.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Hebt die Blockierung auf. Eine frühere Freundschaft entsteht dadurch nicht neu.
    public func unblock(_ user: SocialProfile) async {
        guard let repository, !busyIDs.contains(user.publicID) else { return }
        busyIDs.insert(user.publicID)
        actionError = nil
        defer { busyIDs.remove(user.publicID) }

        do {
            try await repository.unblock(user.publicID)
            users.removeAll { $0.publicID == user.publicID }
        } catch {
            actionError = Self.message(for: error)
        }
    }

    public var emptyText: String {
        PaceLocalization.text(
            de: "Du hast niemanden blockiert.",
            en: "You haven't blocked anyone.",
            ru: "Ты никого не заблокировал."
        )
    }

    public var unavailableText: String {
        SocialError.unavailable.message
    }

    public var explanation: String {
        PaceLocalization.text(
            de: "Blockierte Personen finden dich nicht mehr, können dir keine Anfragen, Einladungen oder Nachrichten senden und sehen dich nicht in gemeinsamen Ranglisten von Freunden. Hebst du eine Blockierung auf, entsteht keine Freundschaft neu.",
            en: "Blocked people can no longer find you, can't send you requests, invitations or messages, and don't see you in friend rankings. Unblocking someone does not restore a friendship.",
            ru: "Заблокированные пользователи больше не находят тебя, не могут отправлять тебе запросы, приглашения и сообщения и не видят тебя в рейтинге друзей. После разблокировки дружба не восстанавливается."
        )
    }

    static func message(for error: Error) -> String {
        (error as? SocialError ?? .unexpected(String(describing: error))).message
    }
}

/// Privatsphäre: Auffindbarkeit in der Suche und blockierte Personen. Die Teilnahme an regionalen Rankings steuert
/// das Profil selbst (gleiche Logik wie auf der Profilseite).
@MainActor
@Observable
public final class PrivacySettingsViewModel {
    public private(set) var isUpdatingDiscoverable = false
    /// Gewünschter Wert, solange die Anfrage läuft – der Schalter springt so nicht zurück.
    public private(set) var pendingDiscoverable: Bool?
    private var failedDiscoverable: Bool?
    private var discoverableFailure: ProfileError?

    public let blockedUsers: BlockedUsersViewModel

    @ObservationIgnored private let store: ProfileStore

    public init(store: ProfileStore, blockedUsers: BlockedUsersViewModel) {
        self.store = store
        self.blockedUsers = blockedUsers
    }

    public var isDiscoverable: Bool { store.profile.isDiscoverable }

    public var discoverableToggleValue: Bool {
        pendingDiscoverable ?? isDiscoverable
    }

    public func setDiscoverable(_ discoverable: Bool) async {
        guard discoverable != isDiscoverable, !isUpdatingDiscoverable else { return }
        isUpdatingDiscoverable = true
        pendingDiscoverable = discoverable
        failedDiscoverable = nil
        discoverableFailure = nil
        defer {
            isUpdatingDiscoverable = false
            pendingDiscoverable = nil
        }

        do {
            try await store.setDiscoverable(discoverable)
        } catch {
            failedDiscoverable = discoverable
            discoverableFailure = error as? ProfileError
        }
    }

    /// Fehler der letzten Änderung – verschwindet, sobald der Wert dem gewünschten entspricht.
    public var discoverableError: String? {
        guard let failedDiscoverable, failedDiscoverable != isDiscoverable else { return nil }
        if discoverableFailure == .unavailable { return ProfileError.unavailable.message }
        return PaceLocalization.text(
            de: "Die Einstellung konnte nicht gespeichert werden. Bitte versuche es erneut.",
            en: "The setting couldn't be saved. Please try again.",
            ru: "Не удалось сохранить настройку. Попробуй снова."
        )
    }

    public var discoverableExplanation: String {
        if discoverableToggleValue {
            return PaceLocalization.text(
                de: "Andere finden dich, sobald sie die ersten Buchstaben deines Benutzernamens eingeben.",
                en: "Others can find you as soon as they type the first letters of your username.",
                ru: "Другие найдут тебя, как только введут первые буквы твоего имени пользователя."
            )
        }
        return PaceLocalization.text(
            de: "Andere finden dich nur, wenn sie deinen Benutzernamen vollständig und genau eingeben – zum Beispiel aus einem geteilten Link.",
            en: "Others can only find you if they enter your exact, complete username – for example from a shared link.",
            ru: "Другие найдут тебя, только если введут твоё имя пользователя полностью и точно – например, из ссылки."
        )
    }
}
