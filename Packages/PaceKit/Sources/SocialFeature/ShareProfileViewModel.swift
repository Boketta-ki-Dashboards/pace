import Foundation
import Observation
import PaceCore

/// „Profil teilen“: Empfängerauswahl aus Freunden und eigenen Gruppen. Das Profil wird als Profilnachricht in die
/// gewählten Chats geschickt (über ``ChatListViewModel/shareProfile(_:with:)``); dort erscheint eine antippbare
/// Profilkarte. Zusätzlich lässt sich der Link `pace://u/<name>` außerhalb von Pace teilen.
@MainActor
@Observable
public final class ShareProfileViewModel {
    /// Ein möglicher Empfänger: ein Freund (privater Chat) oder eine eigene Gruppe (Gruppenchat).
    public struct Recipient: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case friend(SocialProfile)
            case group(GroupSummary.ID, name: String, imagePath: String?, memberCount: Int)
        }

        public let kind: Kind

        public var id: String {
            switch kind {
            case .friend(let profile): "friend-\(profile.publicID.uuidString)"
            case .group(let id, _, _, _): "group-\(id.uuidString)"
            }
        }

        public var title: String {
            switch kind {
            case .friend(let profile): profile.displayName
            case .group(_, let name, _, _): name
            }
        }

        public var target: ChatTarget {
            switch kind {
            case .friend(let profile): .direct(profile)
            case .group(let id, let name, _, _): .group(id: id, name: name)
            }
        }
    }

    public let profile: SocialProfile
    public private(set) var selection: Set<Recipient.ID> = []
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    /// Nach erfolgreichem Senden: die Seite schließt sich.
    public private(set) var didSend = false

    @ObservationIgnored private weak var social: SocialViewModel?

    public init(profile: SocialProfile, social: SocialViewModel?) {
        self.profile = profile
        self.social = social
    }

    /// Freunde (ohne die geteilte Person selbst) und eigene Gruppen.
    public var friendRecipients: [Recipient] {
        (social?.friends ?? [])
            .filter { $0.profile.publicID != profile.publicID }
            .sorted { $0.profile.displayName.localizedStandardCompare($1.profile.displayName) == .orderedAscending }
            .map { Recipient(kind: .friend($0.profile)) }
    }

    public var groupRecipients: [Recipient] {
        (social?.groups ?? []).map { Recipient(kind: .group($0.id, name: $0.name, imagePath: $0.imagePath, memberCount: $0.memberCount)) }
    }

    public var hasRecipients: Bool {
        !friendRecipients.isEmpty || !groupRecipients.isEmpty
    }

    /// Ohne Chat-Backend lässt sich nur der Link teilen.
    public var canShareInPace: Bool {
        social?.chats.isAvailable == true
    }

    public func isSelected(_ recipient: Recipient) -> Bool {
        selection.contains(recipient.id)
    }

    public func toggle(_ recipient: Recipient) {
        if selection.contains(recipient.id) {
            selection.remove(recipient.id)
        } else {
            selection.insert(recipient.id)
        }
        errorMessage = nil
    }

    public var selectedTargets: [ChatTarget] {
        (friendRecipients + groupRecipients).filter { selection.contains($0.id) }.map(\.target)
    }

    public var sendTitle: String {
        SocialText.sendToChats(selection.count)
    }

    public var canSend: Bool {
        canShareInPace && !selection.isEmpty && !isSending
    }

    public var shareURL: URL {
        PaceLink.profile(username: profile.username).url
    }

    public var shareText: String {
        SocialText.shareProfileText(username: profile.username, isOwn: profile.username == social?.ownUsernameValue)
    }

    public func dismissError() {
        errorMessage = nil
    }

    /// Schickt die Profilnachricht in alle gewählten Chats. Fehler stehen in `errorMessage`.
    @discardableResult
    public func send() async -> Bool {
        guard let social, canSend else { return false }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await social.chats.shareProfile(profile, with: selectedTargets)
            didSend = true
            social.show(SocialViewModel.Notice(text: SocialText.profileShared, isError: false))
            return true
        } catch let error as SocialError where error == .unavailable {
            errorMessage = SocialText.shareChatsUnavailable
        } catch {
            errorMessage = SocialText.actionMessage(for: error)
        }
        return false
    }
}
